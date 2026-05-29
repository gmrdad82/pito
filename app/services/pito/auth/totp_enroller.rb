# Z2a (2026-05-25). Enrolls the owner in TOTP 2FA.
#
# Post-Z1: there is no User model. The seed is persisted via
# `AppSetting.enroll_totp!(seed:)` on the singleton row. Backup codes
# are standalone `TotpBackupCode` rows with no user_id.
#
# Generates a fresh 32-char base32 seed + 10 backup codes, persists
# the encrypted seed + BCrypt digests, and returns `{ seed:, codes: }`
# so the rake task / enrollment flow can display the one-shot values.
#
# Re-enrollment guard: raises AlreadyEnrolled when
# AppSetting.totp_enabled? is true. Caller must disable first.
#
# The `totp_enabled_at` stamp is set by this service (unlike the
# old user-model flow that split seed write from confirmation). The
# rake-task-only enrollment surface does not need a split.
module Pito
  module Auth
    class TotpEnroller
      class AlreadyEnrolled < StandardError; end

      # 32 chars of base32 → 160 bits of entropy (RFC 6238 recommendation).
      SEED_LENGTH        = 32
      BACKUP_CODE_LENGTH = 8
      BACKUP_CODE_COUNT  = 10

      # Safe alphabet: base32 minus visually-confusable glyphs.
      BACKUP_CODE_ALPHABET = (
        ("A".."Z").to_a + ("2".."9").to_a -
        %w[O I L B 8]
      ).freeze

      # @return [Hash] { seed: String, codes: Array<String> }
      def self.call
        if AppSetting.totp_enabled?
          raise AlreadyEnrolled, "TOTP is already enrolled — disable first"
        end

        seed = ROTP::Base32.random_base32
        plaintext_codes = Array.new(BACKUP_CODE_COUNT) { generate_code }

        ActiveRecord::Base.transaction do
          # Clean up any prior half-enrolled backup codes.
          TotpBackupCode.destroy_all

          AppSetting.enroll_totp!(seed: seed)

          plaintext_codes.each do |code|
            TotpBackupCode.create!(code_digest: BCrypt::Password.create(code))
          end
        end

        { seed: seed, codes: plaintext_codes }
      end

      # CSPRNG-backed code generation (Mersenne Twister is not a
      # cryptographic RNG; draw each character via SecureRandom).
      def self.generate_code
        Array.new(BACKUP_CODE_LENGTH) {
          BACKUP_CODE_ALPHABET[SecureRandom.random_number(BACKUP_CODE_ALPHABET.length)]
        }.join
      end
    end
  end
end
