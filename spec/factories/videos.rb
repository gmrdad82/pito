FactoryBot.define do
  factory :video do
    channel
    tenant { channel.tenant }
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 11)}#{n}" }
    title { Faker::Lorem.sentence(word_count: 5) }
    description { Faker::Lorem.paragraph }
    published_at { Faker::Time.backward(days: 365) }
    duration_seconds { Faker::Number.between(from: 30, to: 3600) }
    thumbnail_url { Faker::Internet.url }
    tags { Array.new(3) { Faker::Lorem.word } }
    privacy_status { :public_video }
    default_language { "en" }
    made_for_kids { false }

    trait :unlisted do
      privacy_status { :unlisted }
    end

    trait :private_video do
      privacy_status { :private_video }
    end

    trait :scheduled do
      privacy_status { :private_video }
      scheduled_publish_at { Faker::Time.forward(days: 30) }
    end
  end
end
