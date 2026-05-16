FactoryBot.define do
  factory :session do
    user
    sequence(:token_digest) { |n| Pito::TokenDigest.call("session-plaintext-#{n}-#{SecureRandom.hex(4)}") }
    ip { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (test) RspecAgent" }
    last_activity_at { Time.current }
    state { :active }

    # Post-Phase-25 rollback. The `pending_approval` state and the
    # `approval_required_until` column are gone; remaining states are
    # `active`, `expired`, `revoked`.
    trait :expired do
      state { :expired }
    end

    trait :revoked_state do
      state { :revoked }
      revoked_at { Time.current }
    end
  end
end
