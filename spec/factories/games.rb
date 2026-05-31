# frozen_string_literal: true

# Minimal factory for P6 model specs. Full traits added in P11.
FactoryBot.define do
  factory :game do
    sequence(:title) { |n| "Game #{n}" }

    trait :with_ratings do
      igdb_rating { 85.0 }
      igdb_rating_count { 150 }
      aggregated_rating { 82.5 }
      aggregated_rating_count { 80 }
      total_rating { 83.75 }
      total_rating_count { 230 }
    end

    trait :tba do
      release_year { nil }
      release_quarter { nil }
      release_month { nil }
      release_day { nil }
      igdb_synced_at { Time.current }
    end

    trait :unreleased do
      release_year { 1.year.from_now.year }
      release_month { 12 }
      release_day { 25 }
    end

    trait :with_score do
      with_ratings
      after(:build) do |game|
        game.score = Pito::Game::ScoreCalculator.call(game)
      end
    end

    trait :with_igdb_id do
      sequence(:igdb_id) { |n| n + 100 }
      sequence(:igdb_slug) { |n| "game-#{n}" }
    end
  end
end
