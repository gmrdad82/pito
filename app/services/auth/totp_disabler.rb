# Phase 25 — 01e. Disables TOTP 2FA on a user.
#
# Clears `totp_seed_encrypted`, stamps `totp_disabled_at`, destroys
# every backup-code row, and audit-logs the action. Idempotent: a
# user who is not enrolled is a no-op (no audit row written, no
# exception).
#
# The disable controller MUST re-verify a fresh TOTP code before
# calling this service (the spec requires it; this service does not
# self-gate). Once invoked, the destruction is unconditional and
# atomic within a single transaction.
module Auth
  class TotpDisabler
    def self.call(user:, acting_user: nil, source_surface: :web)
      raise ArgumentError, "user required" if user.nil?
      return :noop unless user.totp_enabled?

      acting_user ||= user

      ActiveRecord::Base.transaction do
        user.totp_backup_codes.destroy_all
        user.update!(
          totp_seed_encrypted: nil,
          totp_enabled_at: nil,
          totp_disabled_at: Time.current
        )

        Auth::AuditLogger.call(
          acting_user: acting_user,
          source_surface: source_surface,
          action: :totp_disable,
          target: user,
          metadata: { disabled_user_id: user.id }
        )
      end

      :ok
    end
  end
end
