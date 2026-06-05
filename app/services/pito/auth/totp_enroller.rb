# frozen_string_literal: true

# Enrolls the owner in TOTP 2FA.
#
# Post-Z1: there is no User model. The seed is persisted via
# `AppSetting.enroll_totp!(seed:)` on the singleton row.
#
# Generates a fresh 32-char base32 seed, persists the encrypted seed,
# and returns `{ seed: }` so the enrollment flow can display the
# one-shot value.
module Pito
  module Auth
    class TotpEnroller
      # 32 chars of base32 → 160 bits of entropy (RFC 6238 recommendation).
      SEED_LENGTH = 32

      # @return [Hash] { seed: String }
      def self.call
        seed = ROTP::Base32.random_base32
        AppSetting.enroll_totp!(seed: seed)

        { seed: seed }
      end
    end
  end
end
