FactoryBot.define do
  factory :video_viewer_time_bucket do
    video
    day_of_week_utc { 0 }
    hour_of_day_utc { 0 }
    view_count { 1 }
    watch_time_seconds { 60 }
    last_synced_at { Time.current }
  end
end
