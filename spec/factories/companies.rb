# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:igdb_id) { |n| n + 10_000 }
    sequence(:name) { |n| "Company #{n}" }
    sequence(:slug) { |n| "company-#{n}" }
  end
end
