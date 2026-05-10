FactoryBot.define do
  factory :note do
    project
    sequence(:path) { |n| "untitled-note-#{n}.md" }
    title { "Untitled note" }
    last_modified_at { Time.current }
  end
end
