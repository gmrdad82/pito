FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 8)}#{n}" }

    # Phase 7 Path A2 (literal full retract). Video is a thin
    # YouTube-reference record: youtube_video_id + channel + star +
    # oauth_identity_id + last_synced_at. All metadata fields
    # (title/description/tags/privacy_status/etc.) are gone.
    star { false }
    last_synced_at { nil }

    trait :starred do
      star { true }
    end
  end
end
