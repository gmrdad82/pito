FactoryBot.define do
  factory :project_reference do
    project
    tenant { project.tenant }
    referenceable factory: :game

    trait :collection do
      referenceable factory: :collection
    end
  end
end
