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

      def self.call
        raise NotEnrolled, "owner is not enrolled in 2FA" unless AppSetting.totp_enabled?

        plaintext_codes = Array.new(Pito::Auth::TotpEnroller::BACKUP_CODE_COUNT) do
          Pito::Auth::TotpEnroller.generate_code
        end

        ActiveRecord::Base.transaction do
          TotpBackupCode.delete_all
          plaintext_codes.each do |code|
            TotpBackupCode.create!(
              code_digest: BCrypt::Password.create(code)
            )
          end
        end

        plaintext_codes
      end
    end
  end
end
