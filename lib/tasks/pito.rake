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
  # Runs `Games::PrimaryGenrePicker#pick` row-by-row and writes via
  # `update_column` so callbacks DON'T fire — the model's
  # `before_save :assign_primary_genre_if_blank` would otherwise do the
  # same work redundantly, and we want a single, auditable write per
  # row. `find_each` keeps memory flat for large installs.
  desc "Backfill games.primary_genre_id for existing rows. Idempotent."
  task backfill_primary_genres: :environment do
    picker  = Games::PrimaryGenrePicker.new
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

  # Phase 29 — Unit A2 (R2). Operator-only TOTP-reset escape hatch.
  #
  # The friendly counterpart to the `docs/auth.md` §1a console snippet.
  # pito has no email, so the only self-service browser recovery is
  # reset-via-2FA — which itself needs a working second factor. A user
  # who loses BOTH their authenticator device AND every backup code is
  # locked out of the browser surface. This task is how an operator
  # with shell access on the box rescues them.
  #
  # Given a username, it clears the user's TOTP enrollment
  # (`totp_seed_encrypted` / `totp_enabled_at` / `totp_disabled_at` /
  # `totp_last_used_step` all nil — the same "never enrolled" state a
  # fresh seed produces, NOT a "disabled" state), destroys their
  # backup codes, and revokes every session. After this, the user logs
  # in with their password and the mandatory-2FA gate forces a clean
  # re-enrollment.
  #
  # Idempotent: running it on a user who already has no TOTP writes
  # nils over nils and still prints the confirmation. An unknown
  # username prints a clear error to `$stderr` and exits non-zero.
  # Not gated by anything — operator possession of shell access on the
  # box IS the authorization boundary.
  namespace :user do
    desc "Clear a user's TOTP enrollment + backup codes + sessions so " \
         "they re-enroll on next login. Usage: " \
         "bin/rails pito:user:reset_totp[username]"
    task :reset_totp, [ :username ] => :environment do |_t, args|
      username = args[:username].to_s.strip.downcase
      user = User.find_by(username: username) if username.present?

      if user.nil?
        warn "user not found: #{args[:username]}"
        exit 1
      end

      revoked_at_now = Time.current
      api_tokens_revoked = 0
      oauth_tokens_revoked = 0
      oauth_grants_revoked = 0

      ActiveRecord::Base.transaction do
        user.update!(
          totp_seed_encrypted: nil,
          totp_enabled_at: nil,
          totp_disabled_at: nil,
          totp_last_used_step: nil
        )
        user.totp_backup_codes.delete_all
        user.sessions.destroy_all

        # Phase 29 — Unit A2 follow-up — security finding F1. A user
        # whose TOTP an operator is resetting is, by assumption, a
        # compromised or recovery-mode account. Every bearer credential
        # the user holds must die alongside the sessions; otherwise an
        # attacker with a leaked password + an exfiltrated ApiToken /
        # Doorkeeper grant survives the reset. `update_all` for the
        # bulk path; no per-row callbacks are needed.
        api_tokens_revoked = ApiToken
                               .where(user_id: user.id, revoked_at: nil)
                               .update_all(revoked_at: revoked_at_now)
        oauth_tokens_revoked = Doorkeeper::AccessToken
                                 .where(resource_owner_id: user.id, revoked_at: nil)
                                 .update_all(revoked_at: revoked_at_now)
        oauth_grants_revoked = Doorkeeper::AccessGrant
                                 .where(resource_owner_id: user.id, revoked_at: nil)
                                 .update_all(revoked_at: revoked_at_now)
      end

      # Audit the rake-task escape hatch so the revocation tally is
      # traceable in `AuthAuditLog`. The operator is the acting user —
      # but the rake task has no `Current.user`, so the affected user
      # is recorded as both `acting_user` and `target`. The metadata
      # carries the revocation tallies for incident forensics.
      Pito::Auth::AuditLogger.call(
        acting_user: user,
        source_surface: :tui,
        action: :password_reset,
        target: user,
        metadata: {
          source: "rake:pito:user:reset_totp",
          reset_user_id: user.id,
          api_tokens_revoked: api_tokens_revoked,
          oauth_access_tokens_revoked: oauth_tokens_revoked,
          oauth_access_grants_revoked: oauth_grants_revoked
        }
      )

      puts "TOTP reset for #{user.username} — sessions revoked, backup " \
           "codes cleared, bearer credentials revoked " \
           "(api_tokens=#{api_tokens_revoked}, " \
           "oauth_access_tokens=#{oauth_tokens_revoked}, " \
           "oauth_access_grants=#{oauth_grants_revoked}). " \
           "They will be forced through TOTP setup on next login."
    end

    # Phase 32 follow-up (2026-05-16). Operator-only backup-code
    # rotation.
    #
    # The web-side `[manage backup codes]` surface was dropped along
    # with the disable flow — mandatory-2FA means the web app never
    # asks "are you sure?" about either of those. When the user
    # exhausts or loses their backup codes, the operator regenerates
    # via this task. Style mirrors `pito:user:reset_totp` above.
    #
    # The TOTP seed is NOT touched — the user keeps their
    # authenticator app entry. Only the 10 backup-code rows rotate.
    # Calling on a user who is NOT enrolled in 2FA is a clear error
    # (stderr + non-zero exit) — there is nothing to regenerate.
    desc "Regenerate the 10 backup codes for a user. Prints the new " \
         "codes ONCE — they cannot be retrieved later. Usage: " \
         "bin/rails pito:user:regenerate_backup_codes[username]"
    task :regenerate_backup_codes, [ :username ] => :environment do |_t, args|
      username = args[:username].to_s.strip.downcase
      user = User.find_by(username: username) if username.present?

      if user.nil?
        warn "user not found: #{args[:username]}"
        exit 1
      end

      unless user.totp_enabled?
        warn "user #{user.username} is not enrolled in 2FA — nothing to " \
             "regenerate. Use `pito:user:reset_totp` to clear them entirely, " \
             "then have them re-enroll via the web."
        exit 1
      end

      # `Pito::Auth::BackupCodeRegenerator` destroys every existing
      # (used + unused) backup-code row, mints 10 fresh ones, persists
      # the BCrypt digests, and writes an `AuthAuditLog` row. The
      # rake invocation tags `source_surface: :tui` (no `Current.user`
      # in this context — the user IS the acting user).
      plaintext_codes = Pito::Auth::BackupCodeRegenerator.call(
        user: user,
        acting_user: user,
        source_surface: :tui
      )

      puts "Regenerated 10 backup codes for #{user.username}. " \
           "Save them NOW — they cannot be retrieved later."
      puts ""
      plaintext_codes.each { |code| puts "  #{code}" }
      puts ""
      puts "Each code works once. Any previous backup codes are invalidated."
    end
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
