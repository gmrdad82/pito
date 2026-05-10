FactoryBot.define do
  factory :video_daily_by_subscribed_status do
    video
    sequence(:date)              { |n| Date.current - (n + 1).days }
    sequence(:subscribed_status) { |n| %w[SUBSCRIBED UNSUBSCRIBED][n % 2] }
  end
end
