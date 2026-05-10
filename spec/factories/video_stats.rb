FactoryBot.define do
  factory :video_stat do
    video
    sequence(:date) { |n| n.days.ago.to_date }
    views { Faker::Number.between(from: 0, to: 100_000) }
    likes { Faker::Number.between(from: 0, to: 5_000) }
    comments { Faker::Number.between(from: 0, to: 500) }
    shares { Faker::Number.between(from: 0, to: 200) }
    watch_time_minutes { Faker::Number.between(from: 0.0, to: 50_000.0).round(2) }
    average_view_duration_seconds { Faker::Number.between(from: 10.0, to: 600.0).round(2) }
    average_view_percentage { Faker::Number.between(from: 5.0, to: 100.0).round(2) }
    subscribers_gained { Faker::Number.between(from: 0, to: 100) }
    subscribers_lost { Faker::Number.between(from: 0, to: 10) }
  end
end
