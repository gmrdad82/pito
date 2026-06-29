# frozen_string_literal: true

FactoryBot.define do
  factory :share do
    conversation
    event
    uuid { SecureRandom.uuid }
  end
end
