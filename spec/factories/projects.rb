FactoryBot.define do
  factory :project do
    tenant
    sequence(:name) { |n| "Project #{n}" }
    concept { nil }
  end
end
