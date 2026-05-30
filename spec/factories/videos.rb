# frozen_string_literal: true

# Minimal factory for P6 model specs. Full traits added in P11.
FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "yt_video_#{n}" }
    sequence(:title) { |n| "Video #{n}" }
  end
end
