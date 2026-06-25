# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_primitive do
    sequence(:video_youtube_id) { |n| "yt_vid_prim_#{n}" }
    report       { "scalars" }
    period_token { "7d" }
    start_date   { 7.days.ago.to_date }
    end_date     { Date.current }
    metrics      { { "views" => 100 } }
    fetched_at   { Time.current }
    expires_at   { 1.hour.from_now }

    trait :live do
      expires_at { 1.hour.from_now }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :frozen do
      expires_at { nil }
    end
  end
end
