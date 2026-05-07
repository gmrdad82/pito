FactoryBot.define do
  factory :collection do
    tenant { Current.tenant || association(:tenant) }
    sequence(:name) { |n| "Collection #{n}" }
  end
end
