FactoryBot.define do
  factory :channel_daily do
    channel
    sequence(:date) { |n| Date.current - (n + 1).days }
  end
end
