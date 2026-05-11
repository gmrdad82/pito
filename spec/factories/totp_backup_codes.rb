FactoryBot.define do
  factory :totp_backup_code do
    user
    code_digest { BCrypt::Password.create("ABCD2345") }
    used_at { nil }

    trait :used do
      used_at { Time.current }
    end
  end
end
