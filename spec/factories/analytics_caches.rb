# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_cache do
    sequence(:signature) { |n| "test:sig:#{n}" }
    status { "pending" }

    trait :ready do
      status     { "ready" }
      payload    { { "value" => 42 } }
      expires_at { 1.hour.from_now }
    end

    trait :failed do
      status { "failed" }
      error  { "Something went wrong" }
    end

    trait :expired do
      status     { "ready" }
      payload    { { "value" => 0 } }
      expires_at { 1.hour.ago }
    end
  end
end
