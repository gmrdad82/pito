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
  end
end
