FactoryBot.define do
  factory :video_upload do
    channel
    tenant { channel.tenant }
    video { nil }
    status { :pending }
    title { Faker::Lorem.sentence(word_count: 5) }
    description { Faker::Lorem.paragraph }
    privacy_status { :public_video }
    file_name { "#{Faker::File.file_name(ext: 'mp4')}" }
    file_size { Faker::Number.between(from: 1_000_000, to: 10_000_000_000) }
    bytes_sent { 0 }

    trait :uploading do
      status { :uploading }
      resumable_uri { "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&upload_id=#{SecureRandom.hex}" }
      bytes_sent { file_size / 2 }
    end

    trait :completed do
      status { :completed }
      bytes_sent { file_size }
      youtube_video_id { "vid_#{Faker::Alphanumeric.alphanumeric(number: 11)}" }
      video
    end

    trait :failed do
      status { :failed }
      error_message { "Upload interrupted" }
    end
  end
end
