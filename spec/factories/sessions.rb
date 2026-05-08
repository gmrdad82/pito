FactoryBot.define do
  factory :session do
    tenant { Current.tenant || association(:tenant) }
    user   { association(:user, tenant: tenant) }
    sequence(:token_digest) { |n| Pito::TokenDigest.call("session-plaintext-#{n}-#{SecureRandom.hex(4)}") }
    ip { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (test) RspecAgent" }
    remember { false }
    last_activity_at { Time.current }
  end
end
