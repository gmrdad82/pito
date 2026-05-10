FactoryBot.define do
  factory :genre do
    sequence(:igdb_id) { |n| 1_000 + n }
    sequence(:name) { |n| "Genre #{n}" }
    sequence(:slug) { |n| "genre-#{n}" }
  end
end
