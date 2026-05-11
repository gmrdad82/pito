FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 8)}#{n}" }

    title { Faker::Lorem.sentence(word_count: 5).first(100) }
    description { Faker::Lorem.paragraph(sentence_count: 5) }
    tags { [] }
    category_id { "20" } # Gaming, per the YouTube category catalog.
    privacy_status { :private }
    publish_at { nil }
    self_declared_made_for_kids { false }
    contains_synthetic_media { false }
    star { false }
    last_synced_at { nil }

    trait :starred do
      star { true }
    end

    trait :public do
      privacy_status { :public }
      published_at { 1.day.ago }
    end

    trait :unlisted do
      privacy_status { :unlisted }
      published_at { 1.day.ago }
    end

    trait :scheduled do
      privacy_status { :private }
      publish_at { 1.day.from_now }
    end

    # An imported / pre-pito video — already public on YouTube when pito
    # first synced it, so the pre-publish checklist never fired.
    trait :imported do
      privacy_status { :public }
      published_at { 30.days.ago }
      pre_publish_checked_at { nil }
    end

    trait :pre_publish_complete do
      pre_publish_game_ok { true }
      pre_publish_age_ok { true }
      pre_publish_paid_promotion_ok { true }
      pre_publish_end_screen_ok { true }
      pre_publish_checked_at { Time.current }
    end

    trait :with_sync_error do
      last_sync_error { "title too long" }
    end

    # Phase 11 §01a — Video edit page polish.
    trait :with_thumbnail do
      after(:build) do |video|
        video.thumbnail.attach(
          io: StringIO.new(VideoFactoryHelpers.png_bytes),
          filename: "thumb.png",
          content_type: "image/png"
        )
      end
    end

    trait :with_chapters do
      transient do
        chapter_count { 2 }
      end
      after(:create) do |video, evaluator|
        evaluator.chapter_count.times do |i|
          create(:video_chapter,
                 video: video,
                 start_seconds: i * 60,
                 label: "chapter #{i + 1}")
        end
      end
    end

    trait :with_end_screens do
      transient do
        end_screen_count { 1 }
      end
      after(:create) do |video, evaluator|
        evaluator.end_screen_count.times do |i|
          create(:video_end_screen,
                 video: video,
                 kind: :related_video,
                 target_id: "yt_#{video.id}_#{i}",
                 target_label: "watch #{i + 1}",
                 position: i)
        end
      end
    end
  end
end

# Phase 11 §01a — tiny PNG byte sequence for thumbnail factory traits.
# 1×1 transparent PNG; valid Active Storage payload for `image/png`.
module VideoFactoryHelpers
  module_function

  def png_bytes
    [
      "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4" \
      "890000000d49444154789c63000100000005000100020d010200000000004945" \
      "4e44ae426082"
    ].pack("H*")
  end
end
