FactoryBot.define do
  factory :video_daily_by_device_type do
    video
    sequence(:date)        { |n| Date.current - (n + 1).days }
    sequence(:device_type) { |n| %w[MOBILE TABLET DESKTOP TV GAME_CONSOLE UNKNOWN_PLATFORM][n % 6] }
  end
end
