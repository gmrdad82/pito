FactoryBot.define do
  factory :session do
    user
    sequence(:token_digest) { |n| Pito::TokenDigest.call("session-plaintext-#{n}-#{SecureRandom.hex(4)}") }
    ip { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (test) RspecAgent" }
    remember { false }
    last_activity_at { Time.current }
    state { :active }

    # Phase 25 — 01b. Pending-approval traits cover the three terminal
    # / transient states the new state machine introduces.
    trait :pending do
      state { :pending_approval }
      approval_required_until { 10.minutes.from_now }
    end

    trait :expired_pending do
      state { :pending_approval }
      approval_required_until { 1.minute.ago }
    end

    trait :expired do
      state { :expired }
      approval_required_until { 11.minutes.ago }
    end

    trait :revoked_state do
      state { :revoked }
      revoked_at { Time.current }
    end
  end
end
