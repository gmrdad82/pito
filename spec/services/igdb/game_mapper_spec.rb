require "rails_helper"

RSpec.describe Igdb::GameMapper do
  let(:fixture_root) { Rails.root.join("spec/fixtures/igdb") }
  let(:game_json)    { JSON.parse(File.read(fixture_root.join("7346_game.json"))).first }
  let(:ttb_json)     { JSON.parse(File.read(fixture_root.join("7346_time_to_beat.json"))) }
  let(:extern_json)  { JSON.parse(File.read(fixture_root.join("7346_external_games.json"))) }

  describe ".map_game" do
    subject(:attrs) { described_class.map_game(game_json, ttb_json, extern_json) }

    it "maps the title from `name`" do
      expect(attrs[:title]).to eq("The Legend of Zelda: Breath of the Wild")
    end

    it "maps the slug" do
      expect(attrs[:igdb_slug]).to eq("the-legend-of-zelda-breath-of-the-wild")
    end

    it "maps the summary verbatim" do
      expect(attrs[:summary]).to start_with("The Legend of Zelda")
    end

    it "maps cover.image_id to cover_image_id" do
      expect(attrs[:cover_image_id]).to eq("co1u7n")
    end

    it "converts Unix-second first_release_date to a UTC Date" do
      expect(attrs[:release_date]).to eq(Date.new(2017, 3, 3))
    end

    it "computes release_year from release_date" do
      expect(attrs[:release_year]).to eq(2017)
    end

    it "maps the four rating columns" do
      expect(attrs[:igdb_rating]).to eq(BigDecimal("95.5"))
      expect(attrs[:aggregated_rating]).to eq(BigDecimal("96.25"))
      expect(attrs[:total_rating]).to eq(BigDecimal("95.88")) # rounded(2)
    end

    it "passes through rating sample counts" do
      expect(attrs[:igdb_rating_count]).to eq(1456)
      expect(attrs[:aggregated_rating_count]).to eq(87)
      expect(attrs[:total_rating_count]).to eq(1543)
    end

    it "merges TTB seconds into the attribute hash" do
      expect(attrs[:ttb_main_seconds]).to eq(180_000)
      expect(attrs[:ttb_extras_seconds]).to eq(360_000)
      expect(attrs[:ttb_completionist_seconds]).to eq(720_000)
    end

    it "merges the Steam external ID into the attribute hash" do
      # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `external_gog_id`
      # and `external_epic_id` were retired. The mapper preserves only
      # `external_steam_app_id`; categories 5 (GOG) and 26 (Epic) are
      # silently dropped.
      expect(attrs[:external_steam_app_id]).to eq("1086940")
      expect(attrs).not_to have_key(:external_gog_id)
      expect(attrs).not_to have_key(:external_epic_id)
    end

    it "does NOT include local-only columns" do
      %i[played_at notes hours_of_footage_manual hours_of_footage_cached].each do |k|
        expect(attrs).not_to have_key(k)
      end
    end

    it "handles nil cover gracefully" do
      stripped = game_json.except("cover")
      attrs = described_class.map_game(stripped, ttb_json, extern_json)
      expect(attrs[:cover_image_id]).to be_nil
    end

    it "handles nil first_release_date" do
      stripped = game_json.except("first_release_date")
      attrs = described_class.map_game(stripped, ttb_json, extern_json)
      expect(attrs[:release_date]).to be_nil
      expect(attrs[:release_year]).to be_nil
    end
  end

  describe ".map_external_games" do
    # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — the mapper
    # preserves only `external_steam_app_id`. GOG (5) and Epic (26)
    # external rows surface as the PC umbrella via the Steam Platform
    # row instead of dedicated columns.
    it "maps Steam = category 1" do
      result = described_class.map_external_games([ { "category" => 1, "uid" => "1086940" } ])
      expect(result).to eq(external_steam_app_id: "1086940")
    end

    it "ignores GOG = category 5 (collapsed into steam 2026-05-17)" do
      result = described_class.map_external_games([ { "category" => 5, "uid" => "gog-1" } ])
      expect(result).to eq(external_steam_app_id: nil)
    end

    it "ignores Epic = category 26 (collapsed into steam 2026-05-17)" do
      result = described_class.map_external_games([ { "category" => 26, "uid" => "epic-1" } ])
      expect(result).to eq(external_steam_app_id: nil)
    end

    it "ignores categories pito does not surface" do
      result = described_class.map_external_games([ { "category" => 11, "uid" => "x" } ])
      expect(result).to eq(external_steam_app_id: nil)
    end

    it "handles nil input" do
      expect(described_class.map_external_games(nil)).to eq(external_steam_app_id: nil)
    end
  end

  describe ".map_time_to_beat" do
    it "extracts the three TTB fields" do
      expect(described_class.map_time_to_beat([ { "hastily" => 100, "normally" => 200, "completely" => 300 } ]))
        .to eq(ttb_main_seconds: 100, ttb_extras_seconds: 200, ttb_completionist_seconds: 300)
    end

    it "handles nil (game with no TTB row)" do
      expect(described_class.map_time_to_beat(nil))
        .to eq(ttb_main_seconds: nil, ttb_extras_seconds: nil, ttb_completionist_seconds: nil)
    end

    it "handles an empty array" do
      expect(described_class.map_time_to_beat([]))
        .to eq(ttb_main_seconds: nil, ttb_extras_seconds: nil, ttb_completionist_seconds: nil)
    end
  end

  describe ".developers / .publishers" do
    let(:involved) do
      [
        { "developer" => true, "publisher" => false, "company" => { "id" => 1, "name" => "DevA" } },
        { "developer" => false, "publisher" => true, "company" => { "id" => 2, "name" => "PubA" } },
        { "developer" => true, "publisher" => true, "company" => { "id" => 3, "name" => "Both" } }
      ]
    end

    it "extracts developers" do
      list = described_class.developers(involved)
      expect(list.map { |c| c[:igdb_id] }).to contain_exactly(1, 3)
    end

    it "extracts publishers" do
      list = described_class.publishers(involved)
      expect(list.map { |c| c[:igdb_id] }).to contain_exactly(2, 3)
    end

    it "deduplicates by igdb_id" do
      doubled = involved + involved
      expect(described_class.developers(doubled).map { |c| c[:igdb_id] }).to contain_exactly(1, 3)
    end
  end

  describe ".map_genre / .map_platform / .map_company" do
    it "maps a genre" do
      expect(described_class.map_genre("id" => 31, "name" => "Adventure", "slug" => "adventure"))
        .to eq(igdb_id: 31, name: "Adventure", slug: "adventure")
    end

    it "maps a platform with abbreviation" do
      expect(described_class.map_platform("id" => 130, "name" => "Switch",
                                          "abbreviation" => "NSW", "slug" => "switch"))
        .to eq(igdb_id: 130, name: "Switch", abbreviation: "NSW", slug: "switch")
    end

    it "maps a company" do
      expect(described_class.map_company("id" => 70, "name" => "Nintendo EPD", "slug" => "nintendo-epd"))
        .to eq(igdb_id: 70, name: "Nintendo EPD", slug: "nintendo-epd")
    end
  end
end
