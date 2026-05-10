FactoryBot.define do
  factory :video_daily_by_operating_system do
    video
    sequence(:date)             { |n| Date.current - (n + 1).days }
    sequence(:operating_system) { |n| %w[IOS ANDROID WINDOWS MACINTOSH LINUX OTHER][n % 6] }
  end
end
