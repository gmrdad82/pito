FactoryBot.define do
  factory :blocked_location do
    sequence(:fingerprint_hash) { |n| Digest::SHA256.hexdigest("bl-fp-#{n}") }
    sequence(:ip_prefix) { |n| "10.0.#{n % 255}.0/24" }
    blocked_at { Time.current }
    association :blocked_by_user, factory: :user
    source_surface { :web }
    attempt_count { 0 }

    trait :unblocked do
      unblocked_at { Time.current }
      association :unblocked_by_user, factory: :user
    end
  end
end
