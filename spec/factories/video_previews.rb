# frozen_string_literal: true

FactoryBot.define do
  factory :video_preview do
    video
    status { :draft }
  end
end
