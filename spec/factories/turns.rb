# frozen_string_literal: true

FactoryBot.define do
  factory :turn do
    conversation
    sequence(:position) { |n| n }
    input_kind { "slash" }
    input_text { "/help" }
  end
end
