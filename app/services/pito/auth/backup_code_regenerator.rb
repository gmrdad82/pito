# Phase 25 — 01e. Regenerates backup codes for an enrolled user.
#
# Destroys every existing `TotpBackupCode` row (both used and unused)
# and mints ten fresh ones from the same safe alphabet
# `Pito::Auth::TotpEnroller` uses. The TOTP seed itself is NOT touched —
# only the backup codes rotate. Returns the plaintext codes ONCE so
# the controller can display the one-shot view.
#
# Raises `NotEnrolled` when the user does not have 2FA on; the
# controller surfaces a generic redirect in that case. The settings
# UI requires a fresh TOTP code AND the current password before
# invoking this service (per spec); this service does not self-gate
# on those — it only enforces the "user must be enrolled" invariant.
module Pito
  module Auth
    class BackupCodeRegenerator
      class NotEnrolled < StandardError; end

      def self.call(user:, acting_user: nil, source_surface: :web)
        raise ArgumentError, "user required" if user.nil?
        raise NotEnrolled, "user #{user.id} is not enrolled in 2FA" unless user.totp_enabled?

        acting_user ||= user
        plaintext_codes = Array.new(Pito::Auth::TotpEnroller::BACKUP_CODE_COUNT) do
          Pito::Auth::TotpEnroller.generate_code
        end

        ActiveRecord::Base.transaction do
          user.totp_backup_codes.destroy_all
          plaintext_codes.each do |code|
            user.totp_backup_codes.create!(
              code_digest: BCrypt::Password.create(code)
            )
          end

          Pito::Auth::AuditLogger.call(
            acting_user: acting_user,
            source_surface: source_surface,
            action: :backup_code_regenerate,
            target: user,
            metadata: { regenerated_count: plaintext_codes.size }
          )
        end

        plaintext_codes
      end
    end
  end
end
