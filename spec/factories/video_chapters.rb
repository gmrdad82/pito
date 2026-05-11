# Phase 11 §01a — Video edit page polish. Chapter factory.
FactoryBot.define do
  factory :video_chapter do
    video
    sequence(:start_seconds) { |n| n * 60 }
    sequence(:label) { |n| "chapter #{n}" }
    position { 0 }
  end
end
