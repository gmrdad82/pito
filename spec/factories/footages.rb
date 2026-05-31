# frozen_string_literal: true

FactoryBot.define do
  factory :footage do
    game
    sequence(:filename) { |n| "clip_#{n}.mov" }
    audio_track_names { [] }
    needs_grading { false }

    trait :needs_grading do
      needs_grading { true }
    end

    trait :portrait do
      orientation { Footage::ORIENTATIONS[:portrait] }
    end

    trait :with_audio_tracks do
      audio_track_names { [ "English", " Commentary" ] }
    end
  end
end
