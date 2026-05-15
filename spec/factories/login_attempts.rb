FactoryBot.define do
  factory :login_attempt do
    user { nil }
    email_attempted { "factory_user" }
    result { :failed }
    reason { :wrong_password }
    ip { "1.2.3.4" }
    ip_prefix { "1.2.3.0/24" }
    geo_city { nil }
    geo_region { nil }
    geo_country { nil }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15" }
    browser { "Safari" }
    os { "macOS" }
    sequence(:fingerprint_hash) { |n| Digest::SHA256.hexdigest("fp-#{n}") }

    trait :success do
      result { :success }
      reason { :trusted_location_success }
      association :user
    end

    trait :blocked do
      result { :blocked }
      reason { :blocked_pair }
    end

    trait :pending do
      result { :pending_approval }
      reason { :new_location_pending }
    end

    trait :with_geo do
      geo_city { "Bucharest" }
      geo_region { "Bucharest" }
      geo_country { "RO" }
    end

    trait :ipv6 do
      ip { "2001:db8::1" }
      ip_prefix { "2001:db8::/64" }
    end
  end
end
