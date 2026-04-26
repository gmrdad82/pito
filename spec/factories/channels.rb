FactoryBot.define do
  factory :channel do
    sequence(:youtube_channel_id) { |n| "UC#{Faker::Alphanumeric.alphanumeric(number: 22)}#{n}" }
    title { Faker::Internet.username }
    description { Faker::Lorem.paragraph }
    thumbnail_url { Faker::Internet.url }
    subscriber_count { Faker::Number.between(from: 100, to: 1_000_000) }
    video_count { Faker::Number.between(from: 1, to: 500) }
    view_count { Faker::Number.between(from: 1_000, to: 100_000_000) }
    owned { false }

    trait :owned do
      owned { true }
    end
  end
end
