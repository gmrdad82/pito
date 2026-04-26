FactoryBot.define do
  factory :playlist_item do
    playlist
    video
    sequence(:youtube_playlist_item_id) { |n| "PLI#{Faker::Alphanumeric.alphanumeric(number: 20)}#{n}" }
    position { 0 }
  end
end
