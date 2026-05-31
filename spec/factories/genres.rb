# frozen_string_literal: true

FactoryBot.define do
  factory :genre do
    sequence(:igdb_id) { |n| n + 1_000 }
    sequence(:name) { |n| "Genre #{n}" }
    sequence(:slug) { |n| "genre-#{n}" }
  end
end
