# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    uuid { SecureRandom.uuid }

    trait :named do
      sequence(:title) { |n| "Conversation #{n}" }
    end
  end
end
