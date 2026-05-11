FactoryBot.define do
  factory :video_change_log do
    video
    field { "title" }
    old_value { "old" }
    new_value { "new" }
    source { :pito_apply }
    changed_at { Time.current }
    changed_by_user_id { nil }

    trait :youtube_pull do
      source { :youtube_pull }
    end

    trait :initial_sync do
      source { :initial_sync }
    end
  end
end
