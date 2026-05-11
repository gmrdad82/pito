# Phase 11 §01a — Video edit page polish. End-screen factory.
FactoryBot.define do
  factory :video_end_screen do
    video
    kind { :related_video }
    sequence(:target_id) { |n| "yt_target_#{n}" }
    target_label { "watch next" }
    sequence(:position) { |n| n }

    trait :related_channel do
      kind { :related_channel }
    end

    trait :related_playlist do
      kind { :related_playlist }
    end

    trait :none do
      kind { :none }
      target_id { nil }
      target_label { nil }
    end
  end
end
