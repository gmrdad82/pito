# Pito-namespaced one-off maintenance tasks.
#
# These tasks exist for situations where a clean, idempotent CLI surface
# is preferable to a one-shot console statement: anything that ought to
# show up in shell history with a recognizable name, that an operator
# might want to re-run on multiple environments, or that wants a count
# of rows touched printed back.
namespace :pito do
  # Phase 27 follow-up (2026-05-11) — backfill `games.primary_genre_id`
  # for rows that pre-date the column. Idempotent — already-pinned rows
  # are skipped; rows whose pick resolves to `nil` (zero linked genres)
  # stay `nil` (no row touched, no UPDATE issued).
  #
  # Runs `Game::PrimaryGenrePicker#pick` row-by-row and writes via
  # `update_column` so callbacks DON'T fire — the model's
  # `before_save :assign_primary_genre_if_blank` would otherwise do the
  # same work redundantly, and we want a single, auditable write per
  # row. `find_each` keeps memory flat for large installs.
  desc "Backfill games.primary_genre_id for existing rows. Idempotent."
  task backfill_primary_genres: :environment do
    picker  = Game::PrimaryGenrePicker.new
    updated = 0
    skipped = 0
    no_pick = 0

    Game.where(primary_genre_id: nil).find_each do |game|
      pick = picker.pick(game)
      if pick.nil?
        no_pick += 1
        next
      end
      game.update_column(:primary_genre_id, pick.id)
      updated += 1
    end

    Game.where.not(primary_genre_id: nil).find_each { skipped += 1 } if ENV["VERBOSE"] == "1"

    puts "backfilled primary_genre_id on #{updated} game#{'s' unless updated == 1}."
    puts "  #{no_pick} game#{'s' unless no_pick == 1} had no linked genres (left NULL)."
    puts "  (re-run is a no-op — already-pinned rows are skipped.)"
  end

  # 2026-05-16 (sessions revamp v2). Operator-only audit access to
  # every Session row (including revoked + expired).
  #
  # The web-side Security pane only surfaces ACTIVE sessions — that is
  # the day-to-day actionable surface. Audit access to the full history
  # (a revoked session row from last month, an expired login from a
  # specific incident) belongs on the shell, alongside the other
  # `pito:*` operator tasks.
  #
  # Usage:
  #
  #   bin/rails pito:sessions:list              # active only (default).
  #   bin/rails 'pito:sessions:list[active]'    # explicit active.
  #   bin/rails 'pito:sessions:list[revoked]'   # revoked only.
  #   bin/rails 'pito:sessions:list[expired]'   # expired only.
  #   bin/rails 'pito:sessions:list[all]'       # all states; output
  #                                             # includes a `state` column.
  #
  # Output is plain-text tabular on stdout, columns:
  #   id / user / user-agent / ip / pinged / created-at [/ state].
  # The `state` column only appears when `state=all`; narrowed scopes
  # omit it (redundant — every row carries the same state). Mirrors
  # the `pito:tokens:list` / `pito:oauth_apps:list` style.
  namespace :sessions do
    SESSIONS_LIST_VALID_STATES = %w[all active revoked expired].freeze

    desc "List sessions for audit. Default: active only. " \
         "Usage: bin/rails 'pito:sessions:list[state]' " \
         "(state in: #{SESSIONS_LIST_VALID_STATES.join('|')})."
    task :list, [ :state ] => :environment do |_t, args|
      state = (args[:state].presence || "active").to_s.strip.downcase

      unless SESSIONS_LIST_VALID_STATES.include?(state)
        warn "unknown state: #{args[:state]} " \
             "(allowed: #{SESSIONS_LIST_VALID_STATES.join(', ')})"
        exit 1
      end

      scope =
        case state
        when "all"     then Session.all
        when "active"  then Session.active_sessions
        when "revoked" then Session.where.not(revoked_at: nil)
        when "expired" then Session.state_expired
        end

      rows = scope.order(last_activity_at: :desc, created_at: :desc).to_a

      if rows.empty?
        puts "no sessions match: #{state}."
        next
      end

      include_state_column = (state == "all")

      headers = %w[id user user-agent ip pinged created-at]
      headers << "state" if include_state_column

      table = rows.map do |s|
        row = [
          s.id.to_s,
          s.user&.username.to_s.presence || "(deleted user ##{s.user_id})",
          s.user_agent.to_s.presence || "—",
          s.ip.to_s.presence || "—",
          s.last_activity_at&.utc&.iso8601 || "never",
          s.created_at.utc.iso8601
        ]
        if include_state_column
          row << session_list_state_label(s)
        end
        row
      end

      widths = headers.map.with_index do |h, i|
        ([ h ] + table.map { |r| r[i] }).map(&:length).max
      end

      print_session_row = ->(values) do
        line = values.each_with_index.map { |v, i| v.ljust(widths[i]) }.join("  ")
        puts line.rstrip
      end

      print_session_row.call(headers)
      print_session_row.call(widths.map { |w| "-" * w })
      table.each { |row| print_session_row.call(row) }

      puts ""
      puts "#{rows.size} session#{'s' if rows.size != 1} (#{state})."
    end

    # State label printed in the `all`-mode `state` column. Prefers
    # the revoked flag (a row may be `state=active` with
    # `revoked_at` set if a code path bypassed the model's
    # `#revoke!`); otherwise reads the enum.
    def session_list_state_label(session)
      return "revoked" if session.revoked_at.present?
      session.state.to_s
    end
  end
end
