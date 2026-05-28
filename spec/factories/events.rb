# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    conversation
    turn
    sequence(:position) { |n| n }
    kind { "echo" }
    payload { {} }
  end
end
