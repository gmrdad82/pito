FactoryBot.define do
  factory :trusted_location do
    association :user
    sequence(:fingerprint_hash) { |n| Digest::SHA256.hexdigest("tl-fp-#{n}") }
    sequence(:ip_prefix) { |n| "10.1.#{n % 255}.0/24" }
    first_seen_at { 1.week.ago }
    last_seen_at  { Time.current }
  end
end
