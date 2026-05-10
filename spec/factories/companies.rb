FactoryBot.define do
  factory :company do
    sequence(:igdb_id) { |n| 3_000 + n }
    sequence(:name) { |n| "Company #{n}" }
    sequence(:slug) { |n| "company-#{n}" }
  end
end
