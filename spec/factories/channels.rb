# frozen_string_literal: true

# Minimal factory for P6 model specs. Full traits added in P11.
FactoryBot.define do
  factory :channel do
    sequence(:youtube_channel_id) { |n| "yt_channel_#{n}" }
    sequence(:title) { |n| "Channel #{n}" }
  end
end
