# frozen_string_literal: true

require "rails_helper"

# L6 flip (2026-07-17): game_modes / hypes / age_ratings — the IGDB facts
# that let multiplayer/single_player/hyped/family_friendly move from
# `source: classified` to `source: derived` (traits-design.md L6,
# config/pito/traits.yml). Mirrors game_mapper_platforms_spec.rb's style.
RSpec.describe Game::Igdb::GameMapper, type: :service do
  describe ".map_game game_modes" do
    it "maps IGDB game mode names into the game_modes array" do
      json = {
        "id" => 1, "name" => "Elden Ring",
        "game_modes" => [
          { "id" => 1, "name" => "Single player" },
          { "id" => 2, "name" => "Multiplayer" },
          { "id" => 3, "name" => "Co-operative" }
        ]
      }
      attrs = described_class.map_game(json)
      expect(attrs[:game_modes]).to eq([ "Single player", "Multiplayer", "Co-operative" ])
    end

    it "resets game_modes to [] when IGDB sends an empty list" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X", "game_modes" => [] })
      expect(attrs[:game_modes]).to eq([])
    end

    it "omits game_modes when IGDB doesn't send the field" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X" })
      expect(attrs).not_to have_key(:game_modes)
    end
  end

  describe ".map_game hypes" do
    it "passes the raw integer through" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X", "hypes" => 96 })
      expect(attrs[:hypes]).to eq(96)
    end

    it "omits hypes when IGDB doesn't send the field" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X" })
      expect(attrs).not_to have_key(:hypes)
    end
  end

  describe ".map_game age_ratings" do
    it "maps IGDB age_ratings rows into an organization-name => rating hash" do
      json = {
        "id" => 1, "name" => "Elden Ring",
        "age_ratings" => [
          { "id" => 1, "organization" => { "id" => 1, "name" => "ESRB" }, "rating_category" => { "id" => 11, "rating" => "M" } },
          { "id" => 2, "organization" => { "id" => 2, "name" => "PEGI" }, "rating_category" => { "id" => 4,  "rating" => "16" } }
        ]
      }
      attrs = described_class.map_game(json)
      expect(attrs[:age_ratings]).to eq({ "ESRB" => "M", "PEGI" => "16" })
    end

    it "skips a row missing organization or rating_category" do
      json = {
        "id" => 1, "name" => "X",
        "age_ratings" => [
          { "id" => 1, "organization" => { "name" => "ESRB" } },
          { "id" => 2, "rating_category" => { "rating" => "E" } },
          { "id" => 3, "organization" => { "name" => "PEGI" }, "rating_category" => { "rating" => "3" } }
        ]
      }
      attrs = described_class.map_game(json)
      expect(attrs[:age_ratings]).to eq({ "PEGI" => "3" })
    end

    it "resets age_ratings to {} when IGDB sends an empty list" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X", "age_ratings" => [] })
      expect(attrs[:age_ratings]).to eq({})
    end

    it "omits age_ratings when IGDB doesn't send the field" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X" })
      expect(attrs).not_to have_key(:age_ratings)
    end
  end
end
