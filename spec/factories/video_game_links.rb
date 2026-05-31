# frozen_string_literal: true

FactoryBot.define do
  factory :video_game_link do
    video
    game
  end
end
