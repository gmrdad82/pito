FactoryBot.define do
  factory :project do
    tenant { Current.tenant || association(:tenant) }
    sequence(:name) { |n| "Project #{n}" }
  end
end
