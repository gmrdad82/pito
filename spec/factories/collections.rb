FactoryBot.define do
  factory :collection do
    tenant
    sequence(:name) { |n| "Collection #{n}" }
  end
end
