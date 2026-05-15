# Pito-namespaced one-off maintenance tasks.
#
# These tasks exist for situations where a clean, idempotent CLI surface
# is preferable to a one-shot console statement: anything that ought to
# show up in shell history with a recognizable name, that an operator
# might want to re-run on multiple environments, or that wants a count
# of rows touched printed back.
namespace :pito do
  desc "Delete every Channel whose youtube_connection_id is NULL (legacy " \
       "seed rows). Idempotent — safe to run on any environment."
  task drop_seeded_channels: :environment do
    # The pre-2026-05-10 seed (`db/seeds.rb`) created up to 100 placeholder
    # Channel rows with `youtube_connection_id: nil`. They have been removed
    # from the seed file; this task cleans up environments that ran the old
    # seed at least once. Real channels minted through the OAuth flow always
    # carry a `youtube_connection_id`, so the filter never deletes anything
    # an operator would want to keep.
    scope = Channel.where(youtube_connection_id: nil)
    count = scope.count

    if count.zero?
      puts "no seeded channels to drop."
      next
    end

    # `destroy_all` so the standard `dependent: :destroy` cascade fires for
    # related rows (videos, calendar entries, change logs, etc.). The
    # legacy seed populated those tables, so a bare `delete_all` would
    # leave orphans behind.
    scope.destroy_all

    puts "dropped #{count} seeded channel#{'s' unless count == 1}."
  end

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
      Auth::AuditLogger.call(
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
  end
end
