# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    sequence(:message) { |n| "Notification #{n}" }
    read_at { nil }

    trait :read do
      read_at { 1.hour.ago }
    end
  end
end
