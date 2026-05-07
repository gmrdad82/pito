FactoryBot.define do
  factory :playlist do
    channel
    tenant { channel.tenant }
    sequence(:youtube_playlist_id) { |n| "PL#{Faker::Alphanumeric.alphanumeric(number: 22)}#{n}" }
    title { Faker::Lorem.sentence(word_count: 3) }
    description { Faker::Lorem.paragraph }
    privacy_status { :public_playlist }
    item_count { 0 }
    thumbnail_url { Faker::Internet.url }
    published_at { Faker::Time.backward(days: 365) }
  end
end
