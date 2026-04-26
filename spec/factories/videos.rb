FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 11)}#{n}" }
    title { Faker::Lorem.sentence(word_count: 5) }
    description { Faker::Lorem.paragraph }
    published_at { Faker::Time.backward(days: 365) }
    duration_seconds { Faker::Number.between(from: 30, to: 3600) }
    thumbnail_url { Faker::Internet.url }
    tags { Array.new(3) { Faker::Lorem.word } }
  end
end
