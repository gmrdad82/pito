FactoryBot.define do
  factory :video_daily_by_country do
    video
    sequence(:date)         { |n| Date.current - (n + 1).days }
    sequence(:country_code) { |n| %w[US GB CA DE FR JP BR ZZ][n % 8] }
  end
end
