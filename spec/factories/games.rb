# frozen_string_literal: true

# Minimal factory for model specs. Full traits added later.
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
        game.score = Pito::Games::ScoreCalculator.call(game)
      end
    end

    trait :with_igdb_id do
      sequence(:igdb_id) { |n| n + 100 }
      sequence(:igdb_slug) { |n| "game-#{n}" }
    end

    trait :with_genres do
      after(:create) do |game|
        create_list(:genre, 2).each do |genre|
          create(:game_genre, game: game, genre: genre)
        end
      end
    end

    trait :with_developers do
      after(:create) do |game|
        create_list(:company, 2).each do |company|
          create(:game_developer, game: game, company: company)
        end
      end
    end

    # A representative valid games.traits jsonb payload — one classified
    # scale, one owner-overridden scale, a mix of classified/owner/derived
    # tags, plus an owner-pinned-absent tag (see traits-design.md section 1
    # for the shape this mirrors).
    trait :with_traits do
      traits do
        {
          "schema_version" => 1,
          "values" => {
            "difficulty" => "brutal",
            "story" => "catching",
            "tags" => %w[skill_based worth_it action]
          },
          "sources" => {
            "difficulty" => "classified",
            "story" => "owner",
            "skill_based" => "classified",
            "worth_it" => "owner",
            "action" => "derived",
            "war" => "owner"
          },
          "classified_at" => Time.current.utc.iso8601
        }
      end
    end
  end
end
