# frozen_string_literal: true

FactoryBot.define do
  factory :video_preview do
    video
    status { :draft }

    trait :published do
      status { :published }
      published_at { Time.current }
    end

    trait :failed do
      status { :failed }
      error_message { "API error: quota exceeded" }
    end

    trait :with_thumbnail do
      after(:build) do |preview|
        preview.thumbnail.attach(
          io: StringIO.new("fake image data"),
          filename: "thumb.png",
          content_type: "image/png"
        )
      end
    end
  end
end
