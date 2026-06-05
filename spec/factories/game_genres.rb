# frozen_string_literal: true

FactoryBot.define do
  factory :game_genre do
    game
    genre
    sequence(:position) { |n| n }
  end
end
