FactoryBot.define do
  factory :video_daily_by_traffic_source do
    video
    sequence(:date)                { |n| Date.current - (n + 1).days }
    sequence(:traffic_source_type) { |n| %w[YT_SEARCH EXT_URL RELATED_VIDEO SUBSCRIBER YT_CHANNEL YT_OTHER_PAGE PLAYLIST NOTIFICATION SHORTS][n % 9] }
  end
end
