# frozen_string_literal: true

FactoryBot.define do
  factory :app_setting do
    # Key/value pair (non-singleton)
    sequence(:key) { |n| "test_key_#{n}" }
    value { "test_value" }

    trait :singleton do
      key { AppSetting::SINGLETON_KEY }
      value { nil }
    end

    trait :with_totp do
      totp_seed_encrypted { "encrypted_seed_xyz" }
      totp_enabled_at { Time.current }
      totp_disabled_at { nil }
    end
  end
end
