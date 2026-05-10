FactoryBot.define do
  factory :video_daily do
    video
    sequence(:date) { |n| Date.current - (n + 1).days }
  end
end
