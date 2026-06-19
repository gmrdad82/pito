# frozen_string_literal: true

# Minimal factory for model specs. Full traits added later.
FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "yt_video_#{n}" }
    sequence(:title) { |n| "Video #{n}" }

    trait :scheduled do
      privacy_status { :private }
      publish_at { 1.day.from_now }
    end

    trait :public do
      privacy_status { :public }
      published_at { 1.day.ago }
    end

    trait :private do
      privacy_status { :private }
    end

    trait :unlisted do
      privacy_status { :unlisted }
    end

    trait :with_linked_games do
      after(:create) do |video|
        create_list(:game, 2).each do |game|
          create(:video_game_link, video: video, game: game)
        end
      end
    end
  end
end
