require "rails_helper"

# Phase 27 follow-up (2026-05-11) — canonical platform display.
#
# Locks the IGDB → canonical short-name mapping rendered on the game
# show page (and anywhere else PlatformsHelper#display_platforms is
# called). The six canonical short names are:
#
#   PS5, Switch2, Steam, GoG, Epic, Xbox
#
# Anything outside the canonical six is DROPPED from the display.
RSpec.describe PlatformsHelper, type: :helper do
  let(:game) { create(:game) }

  # FriendlyId regenerates `slug` from `name` during the save callback
  # (see `Platform#should_generate_new_friendly_id?`), so the factory
  # convention is `create` + `update_column(:slug, "...")` whenever a
  # spec needs to pin a specific slug (canonical or otherwise).
  def make_platform(name:, slug: nil, igdb_id: nil)
    record = create(:platform, name: name, igdb_id: igdb_id)
    record.update_column(:slug, slug) if slug
    record.reload
  end

  describe "#display_platforms" do
    it "renders `—` when the game has no canonical platforms" do
      expect(helper.display_platforms(game)).to eq("—")
    end

    it "renders the canonical short name for a seed PS5 platform" do
      ps5 = make_platform(name: "PlayStation 5", slug: "ps5", igdb_id: nil)
      game.platforms_available << ps5
      expect(helper.display_platforms(game)).to eq("PS5")
    end

    it "renders 'Switch2' for the manually-seeded Switch 2 platform" do
      sw2 = make_platform(name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil)
      game.platforms_available << sw2
      expect(helper.display_platforms(game)).to eq("Switch2")
    end

    it "renders 'Xbox' when the game ships on Xbox One (igdb_id=49)" do
      xbox_one = make_platform(name: "Xbox One", igdb_id: 49)
      game.platforms_available << xbox_one
      expect(helper.display_platforms(game)).to eq("Xbox")
    end

    it "renders 'Xbox' when the game ships on Xbox Series X|S (igdb_id=169)" do
      xsxs = make_platform(name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << xsxs
      expect(helper.display_platforms(game)).to eq("Xbox")
    end

    it "collapses Xbox One + Xbox Series X|S into a single 'Xbox' label" do
      xbox_one = make_platform(name: "Xbox One", igdb_id: 49)
      xsxs = make_platform(name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << xbox_one
      game.platforms_available << xsxs
      expect(helper.display_platforms(game)).to eq("Xbox")
    end

    it "drops non-canonical IGDB platforms (PlayStation 4)" do
      ps4 = make_platform(name: "PlayStation 4", igdb_id: 48)
      game.platforms_available << ps4
      expect(helper.display_platforms(game)).to eq("—")
    end

    it "drops non-canonical IGDB platforms (Nintendo Switch OG)" do
      switch = make_platform(name: "Nintendo Switch", igdb_id: 130)
      game.platforms_available << switch
      expect(helper.display_platforms(game)).to eq("—")
    end

    it "drops 'PC (Microsoft Windows)' entirely (no canonical alias)" do
      pc = make_platform(name: "PC (Microsoft Windows)", igdb_id: 6)
      game.platforms_available << pc
      expect(helper.display_platforms(game)).to eq("—")
    end

    it "infers 'Steam' from external_steam_app_id" do
      game.update!(external_steam_app_id: "12345")
      expect(helper.display_platforms(game)).to eq("Steam")
    end

    it "infers 'GoG' from external_gog_id" do
      game.update!(external_gog_id: "987654321")
      expect(helper.display_platforms(game)).to eq("GoG")
    end

    it "infers 'Epic' from external_epic_id" do
      game.update!(external_epic_id: "abc-xyz")
      expect(helper.display_platforms(game)).to eq("Epic")
    end

    it "renders all canonical labels in the locked order" do
      ps5  = make_platform(name: "PlayStation 5",     slug: "ps5",     igdb_id: nil)
      sw2  = make_platform(name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil)
      xbox = make_platform(name: "Xbox One",          igdb_id: 49)
      game.platforms_available << ps5
      game.platforms_available << sw2
      game.platforms_available << xbox
      game.update!(
        external_steam_app_id: "1",
        external_gog_id:       "2",
        external_epic_id:      "3"
      )
      expect(helper.display_platforms(game)).to eq("PS5, Switch2, Steam, GoG, Epic, Xbox")
    end

    it "deduplicates when both the canonical seed AND an IGDB row map to the same slug" do
      ps5_seed = make_platform(name: "PlayStation 5",        slug: "ps5",      igdb_id: nil)
      ps5_igdb = make_platform(name: "PlayStation 5 (IGDB)", slug: "ps5-igdb", igdb_id: 167)
      game.platforms_available << ps5_seed
      game.platforms_available << ps5_igdb
      expect(helper.display_platforms(game)).to eq("PS5")
    end
  end

  describe "#canonical_platform_short_names_for" do
    it "returns an empty array when the game has no canonical platforms" do
      expect(helper.canonical_platform_short_names_for(game)).to eq([])
    end

    it "returns the canonical short names as an array" do
      xbox = make_platform(name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << xbox
      game.update!(external_steam_app_id: "42")
      expect(helper.canonical_platform_short_names_for(game)).to eq(%w[Steam Xbox])
    end
  end
end
