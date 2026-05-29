# Enrolls the owner in TOTP 2FA.
#
# Post-Z1: there is no User model. The seed is persisted via
# `AppSetting.enroll_totp!(seed:)` on the singleton row.
#
# Generates a fresh 32-char base32 seed, persists the encrypted seed,
# and returns `{ seed: }` so the rake task / enrollment flow can display
# the one-shot value.
#
# Re-enrollment guard: raises AlreadyEnrolled when
# AppSetting.totp_enabled? is true. Caller must disable first.
module Pito
  module Auth
    class TotpEnroller
      class AlreadyEnrolled < StandardError; end

      # 32 chars of base32 → 160 bits of entropy (RFC 6238 recommendation).
      SEED_LENGTH = 32

      # @return [Hash] { seed: String }
      def self.call
        if AppSetting.totp_enabled?
          raise AlreadyEnrolled, "TOTP is already enrolled — disable first"
        end

        seed = ROTP::Base32.random_base32
        AppSetting.enroll_totp!(seed: seed)

        { seed: seed }
      end
    end
  end
end
