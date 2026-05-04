FactoryBot.define do
  factory :note do
    project
    tenant { project.tenant }
    sequence(:path) { |n| "untitled-note-#{n}.md" }
    title { "Untitled note" }
    last_modified_at { Time.current }
  end
end
