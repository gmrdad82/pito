FactoryBot.define do
  factory :project do
    tenant
    sequence(:name) { |n| "Project #{n}" }
  end
end
