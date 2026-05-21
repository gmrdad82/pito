# Phase 25 — 01e. Enrolls a user in TOTP 2FA.
#
# Generates a fresh 32-char base32 seed (`ROTP::Base32.random`), mints
# ten 8-char backup codes from the safe 28-char alphabet (no
# `0` / `O` / `1` / `I` / `L` / `B` / `8`), persists the encrypted seed
# + BCrypt digests of every code, and returns `{ seed:, codes: }` so
# the controller can display the one-shot enrollment view.
#
# Re-enrollment SEMANTICS: the spec mandates that `Pito::Auth::TotpEnroller`
# raises when called for an already-enrolled user. Callers (the
# enrollment flow) must disable 2FA first. This is a guardrail against
# the controller letting the user "enroll again" and silently rotating
# their seed while their authenticator app still holds the old one.
#
# The `totp_enabled_at` stamp is NOT set here — `Pito::Auth::TotpEnroller`
# only seeds the row. The user must confirm a fresh 6-digit code via
# `Settings::Security::TotpEnrollmentsController#update` before
# `totp_enabled_at` flips. Until then the row is "seed-only" (no
# `enabled_at`) and `totp_enabled?` returns false; the seed remains
# encrypted at rest.
module Pito
  module Auth
    class TotpEnroller
      class AlreadyEnrolled < StandardError; end

      # 32 chars of base32 plaintext is the standard `ROTP` seed length
      # (`ROTP::Base32.random_base32` returns exactly this). 20 raw bytes
      # — 32 base32 chars — gives 160 bits of entropy, the RFC 6238
      # recommendation.
      SEED_LENGTH        = 32
      BACKUP_CODE_LENGTH = 8
      BACKUP_CODE_COUNT  = 10

      # Safe alphabet: base32 minus `0` / `O` / `1` / `I` / `L` plus the
      # additional `B` / `8` exclusion (the spec's "new" lock). The
      # exclusion list pairs visually-confusable glyphs the user would
      # otherwise miscopy off the one-shot view. `0` / `1` are NOT in
      # the digit pool `("2".."9")` anyway; they are listed for
      # documentation.
      BACKUP_CODE_ALPHABET = (
        ("A".."Z").to_a + ("2".."9").to_a -
        %w[O I L B 8]
      ).freeze

      def self.call(user:)
        raise ArgumentError, "user required" if user.nil?

        # Enrollment is gated on `totp_enabled_at`, NOT on
        # `totp_enabled?` — a user who started enrollment but did not
        # confirm has a seed at rest but no `enabled_at` stamp; they
        # MUST be allowed to start over (the original one-shot view's
        # flash is gone, so they have no way to scan the QR again).
        if user.totp_enabled_at.present?
          raise AlreadyEnrolled,
                "user #{user.id} is already enrolled — disable 2FA first"
        end

        seed = ROTP::Base32.random_base32
        plaintext_codes = Array.new(BACKUP_CODE_COUNT) { generate_code }

        ActiveRecord::Base.transaction do
          # Re-enrollment defense in depth: TOTP is mandatory (Phase 29
          # Unit A2) so there is no live disable path, but legacy rows
          # from the dropped pre-mandatory disable flow could still
          # sneak through — destroy any leftovers here so the new seed
          # comes up clean.
          user.totp_backup_codes.destroy_all

          user.update!(
            totp_seed_encrypted: seed,
            totp_enabled_at: nil,
            totp_disabled_at: nil
          )

          plaintext_codes.each do |code|
            user.totp_backup_codes.create!(
              code_digest: BCrypt::Password.create(code)
            )
          end
        end

        { seed: seed, codes: plaintext_codes }
      end

      # P25 follow-up — F10. Backup codes are minted from an explicit
      # CSPRNG. Ruby 3.x's `Array#sample` happens to seed from SecureRandom,
      # but the underlying generator is Mersenne Twister — NOT a
      # cryptographic RNG. Drawing each character via
      # `SecureRandom.random_number` makes the cryptographic guarantee
      # explicit at the source and survives any future change to the stdlib
      # `Random` default.
      def self.generate_code
        Array.new(BACKUP_CODE_LENGTH) {
          BACKUP_CODE_ALPHABET[SecureRandom.random_number(BACKUP_CODE_ALPHABET.length)]
        }.join
      end
    end
  end
end
