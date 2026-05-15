FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "user_#{n}" }
    password { "password123" }
    password_confirmation { "password123" }

    # Phase 25 — 01e. TOTP-enrolled trait. Seeds a deterministic
    # base32 secret + 10 backup codes (BCrypt-hashed). Useful when
    # the spec needs an already-2FA-on user (e.g. login flow,
    # backup-code consume, disable flow). Re-using the same seed
    # across specs keeps `ROTP::TOTP.new(seed).now` predictable.
    trait :totp_enabled do
      transient do
        totp_seed { "JBSWY3DPEHPK3PXP" }
        backup_code_plaintexts do
          %w[ALPHA2345 BETA3456X GAMMA567 DELTA678 EPSILON7
             ZETA9234 ETA56789 THETA678 IOTA2345 KAPPA678]
        end
      end

      totp_seed_encrypted { totp_seed }
      totp_enabled_at { Time.current }

      after(:create) do |user, evaluator|
        evaluator.backup_code_plaintexts.each do |code|
          user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(code))
        end
      end
    end
  end
end
