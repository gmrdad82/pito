# frozen_string_literal: true

# Minimal factory for model specs. Full traits added later.
FactoryBot.define do
  factory :channel do
    sequence(:youtube_channel_id) { |n| "yt_channel_#{n}" }
    sequence(:title) { |n| "Channel #{n}" }

    trait :with_videos do
      after(:create) do |channel|
        create_list(:video, 3, channel: channel)
      end
    end

    trait :on_connection do
      youtube_connection
    end
  end
end
