# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    uuid { SecureRandom.uuid }

    trait :named do
      sequence(:title) { |n| "Conversation #{n}" }
    end

    trait :with_turns do
      after(:create) do |conversation|
        create_list(:turn, 2, conversation: conversation)
      end
    end
  end
end
