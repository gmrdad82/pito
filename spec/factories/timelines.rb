FactoryBot.define do
  factory :timeline do
    project
    tenant { project.tenant }
    sequence(:title) { |n| "Timeline #{n}" }
    state { :editing }

    trait :exported do
      state { :exported }
    end

    trait :uploaded do
      state { :uploaded }
    end
  end
end
