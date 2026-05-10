FactoryBot.define do
  factory :platform do
    sequence(:igdb_id) { |n| 2_000 + n }
    sequence(:name) { |n| "Platform #{n}" }
    sequence(:abbreviation) { |n| "P#{n}" }
    sequence(:slug) { |n| "platform-#{n}" }
  end
end
