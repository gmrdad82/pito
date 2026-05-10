FactoryBot.define do
  factory :playlist_video do
    playlist
    video { association(:video, channel: playlist.channel) }
    sequence(:youtube_playlist_item_id) { |n| "PLI#{Faker::Alphanumeric.alphanumeric(number: 20)}#{n}" }
    position { 0 }
  end
end
