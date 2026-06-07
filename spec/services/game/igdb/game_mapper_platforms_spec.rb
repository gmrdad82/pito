# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Igdb::GameMapper, type: :service do
  describe ".map_game platforms" do
    it "maps IGDB platform names into the platforms array" do
      json = {
        "id" => 1, "name" => "Zelda",
        "platforms" => [
          { "id" => 130, "name" => "Nintendo Switch", "slug" => "switch" },
          { "id" => 6,   "name" => "PC (Microsoft Windows)", "slug" => "win" },
          { "id" => 0,   "name" => "" }
        ]
      }
      attrs = described_class.map_game(json)
      expect(attrs[:platforms]).to eq([ "Nintendo Switch", "PC (Microsoft Windows)" ])
    end

    it "resets platforms to [] when IGDB sends an empty list" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X", "platforms" => [] })
      expect(attrs[:platforms]).to eq([])
    end

    it "omits platforms when IGDB doesn't send the field" do
      attrs = described_class.map_game({ "id" => 1, "name" => "X" })
      expect(attrs).not_to have_key(:platforms)
    end
  end
end
