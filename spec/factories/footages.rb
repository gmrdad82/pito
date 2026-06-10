# frozen_string_literal: true

FactoryBot.define do
  factory :footage do
    game
    sequence(:filename) { |n| "clip_#{n}.mov" }
    duration_seconds { 312 }
  end
end
