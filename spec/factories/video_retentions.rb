FactoryBot.define do
  factory :video_retention do
    video
    sequence(:elapsed_ratio_bucket) do |n|
      # 100 buckets per video, range 0.0000 to 0.9900.
      ((n - 1) % 100) / 100.0
    end
    audience_watch_ratio { 0.5 }
    started_watching     { 100 }
    stopped_watching     { 50 }
    total_segment_impressions { 200 }
  end
end
