# frozen_string_literal: true

# Minimal factory for model specs. Full traits added later.
FactoryBot.define do
  factory :channel do
    sequence(:youtube_channel_id) { |n| "yt_channel_#{n}" }
    sequence(:title) { |n| "Channel #{n}" }
    # Real channels are OAuth-created and ALWAYS belong to a youtube_connection;
    # the list/glance now skips connection-less orphans (defensive — F bug), so the
    # factory reflects reality by default. Use :orphan for the rare no-conn case.
    youtube_connection

    trait :orphan do
      youtube_connection { nil }
    end

    trait :with_videos do
      after(:create) do |channel|
        create_list(:video, 3, channel: channel)
      end
    end

    # Back-compat alias — the default already sets a connection.
    trait :on_connection do
      youtube_connection
    end
  end
end
