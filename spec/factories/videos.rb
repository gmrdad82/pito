FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 8)}#{n}" }

    # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
    # Video is a thin YouTube-reference record: youtube_video_id +
    # channel + star + youtube_connection_id + last_synced_at. All
    # metadata fields (title/description/tags/privacy_status/etc.)
    # are gone.
    star { false }
    last_synced_at { nil }

    trait :starred do
      star { true }
    end
  end
end
