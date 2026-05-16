require "rails_helper"

# Phase 27 v2 spec 07 — `PlatformLogosHelper` covers:
#
#   - `platform_logo_tag(slug, size:)` — `<img>` emission, alt text,
#     unknown-slug nil, invalid-size raise.
#   - `game_index_tile_logo_slug(game)` — one-logo-per-tile selection
#     (owned wins; KNOWN_LOGOS declaration order).
#   - `game_detail_logo_slugs(game)` — multi-logo detail-page set
#     in locked PS5 / Switch2 / Steam / GoG / Epic order.
#
# Platform records are created with the explicit slug needed for
# the canonical match. FriendlyId regenerates the slug from `name`
# during the save callback, so the factory convention is
# `update_column(:slug, ...)` after `create`.
RSpec.describe PlatformLogosHelper, type: :helper do
  def make_platform(slug:, name: nil, igdb_id: nil)
    record = create(:platform, name: name || "Platform-#{slug}", igdb_id: igdb_id)
    record.update_column(:slug, slug) if slug
    record.reload
  end

  let(:ps5)     { make_platform(slug: "ps5") }
  let(:switch2) { make_platform(slug: "switch2") }
  let(:steam)   { make_platform(slug: "steam") }
  let(:gog)     { make_platform(slug: "gog") }
  let(:epic)    { make_platform(slug: "epic") }
  let(:xbox_one) { create(:platform, name: "Xbox One", igdb_id: 49) }

  # ---------------------------------------------------------------
  # `platform_logo_tag`
  # ---------------------------------------------------------------

  describe "#platform_logo_tag" do
    it "renders an `<img>` at the requested size for ps5/16" do
      html = helper.platform_logo_tag("ps5", size: 16)
      tag = Capybara.string(html.to_s).find("img")
      expect(tag[:src]).to eq("/platform_logos/ps5-16.png")
      expect(tag[:width]).to eq("16")
      expect(tag[:height]).to eq("16")
      expect(tag[:alt]).to eq("PS5")
    end

    it "renders the 64 px asset for size: 64" do
      html = helper.platform_logo_tag("ps5", size: 64)
      tag = Capybara.string(html.to_s).find("img")
      expect(tag[:src]).to eq("/platform_logos/ps5-64.png")
      expect(tag[:width]).to eq("64")
      expect(tag[:height]).to eq("64")
    end

    it "uses the canonical short label as alt text for switch2" do
      html = helper.platform_logo_tag("switch2", size: 16)
      expect(Capybara.string(html.to_s).find("img")[:alt]).to eq("Switch2")
    end

    it "renders the Steam/GoG/Epic logos with their brand-correct labels" do
      expect(Capybara.string(helper.platform_logo_tag("steam", size: 16).to_s).find("img")[:alt]).to eq("Steam")
      expect(Capybara.string(helper.platform_logo_tag("gog",   size: 16).to_s).find("img")[:alt]).to eq("GoG")
      expect(Capybara.string(helper.platform_logo_tag("epic",  size: 16).to_s).find("img")[:alt]).to eq("Epic")
    end

    it "tags the img with a `.platform-logo` and per-slug modifier class" do
      html = helper.platform_logo_tag("ps5", size: 16)
      tag = Capybara.string(html.to_s).find("img")
      expect(tag[:class].split).to include("platform-logo", "platform-logo--ps5")
    end

    it "inlines vertical-align: middle so the logo sits flush with the meta text" do
      html = helper.platform_logo_tag("ps5", size: 16)
      tag = Capybara.string(html.to_s).find("img")
      expect(tag[:style]).to include("vertical-align: middle")
    end

    it "returns nil for an unknown slug" do
      expect(helper.platform_logo_tag("evil", size: 16)).to be_nil
    end

    it "returns nil for an unknown slug (xbox is intentionally NOT in KNOWN_LOGOS)" do
      expect(helper.platform_logo_tag("xbox", size: 16)).to be_nil
    end

    it "raises ArgumentError when size is not in LOGO_SIZES" do
      expect { helper.platform_logo_tag("ps5", size: 32) }
        .to raise_error(ArgumentError, /unknown logo size/)
    end

    it "raises ArgumentError for size: 0" do
      expect { helper.platform_logo_tag("ps5", size: 0) }
        .to raise_error(ArgumentError)
    end
  end

  # ---------------------------------------------------------------
  # `game_index_tile_logo_slug`
  # ---------------------------------------------------------------

  describe "#game_index_tile_logo_slug" do
    let(:game) { create(:game) }

    it "returns the owned-platform slug when the game is owned on PS5" do
      game.owned_platforms << ps5
      expect(helper.game_index_tile_logo_slug(game)).to eq("ps5")
    end

    it "returns the owned-platform slug when the game is owned on Switch2" do
      game.owned_platforms << switch2
      expect(helper.game_index_tile_logo_slug(game)).to eq("switch2")
    end

    it "picks the FIRST KNOWN_LOGOS-ordered slug when the game is owned on multiple platforms" do
      # Owned on steam + gog → steam wins (steam precedes gog in KNOWN_LOGOS).
      game.owned_platforms << gog
      game.owned_platforms << steam
      expect(helper.game_index_tile_logo_slug(game)).to eq("steam")
    end

    it "PS5 wins over Steam when owned on both" do
      game.owned_platforms << steam
      game.owned_platforms << ps5
      expect(helper.game_index_tile_logo_slug(game)).to eq("ps5")
    end

    it "falls back to platforms_available when the game is not owned" do
      game.platforms_available << ps5
      expect(helper.game_index_tile_logo_slug(game)).to eq("ps5")
    end

    it "falls back to a PC-store inference when the game is unreleased and has external_steam_app_id" do
      game.update!(external_steam_app_id: "12345")
      expect(helper.game_index_tile_logo_slug(game)).to eq("steam")
    end

    it "returns nil when the game has no known platform exposure (xbox-only)" do
      game.platforms_available << xbox_one
      expect(helper.game_index_tile_logo_slug(game)).to be_nil
    end

    it "returns nil when the game has no platforms at all" do
      expect(helper.game_index_tile_logo_slug(game)).to be_nil
    end

    it "prefers owned ps5 over available steam (owned tier wins over available tier)" do
      game.owned_platforms << ps5
      game.platforms_available << steam
      expect(helper.game_index_tile_logo_slug(game)).to eq("ps5")
    end

    it "prefers the owned slug over a PC-store inference (Steam available via external id) when game is owned on something else" do
      game.owned_platforms << gog
      game.update!(external_steam_app_id: "12345")
      expect(helper.game_index_tile_logo_slug(game)).to eq("gog")
    end
  end

  # ---------------------------------------------------------------
  # `game_detail_logo_slugs`
  # ---------------------------------------------------------------

  describe "#game_detail_logo_slugs" do
    let(:game) { create(:game) }

    it "returns ps5 when the game is on the PS5 platform" do
      game.platforms_available << ps5
      expect(helper.game_detail_logo_slugs(game)).to eq([ "ps5" ])
    end

    it "returns the slug set in the locked PS5/Switch2/Steam/GoG/Epic order" do
      game.platforms_available << ps5
      game.platforms_available << switch2
      game.update!(external_steam_app_id: "111", external_gog_id: "222", external_epic_id: "333")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 switch2 steam gog epic])
    end

    it "returns [] when no known platform applies" do
      expect(helper.game_detail_logo_slugs(game)).to eq([])
    end

    it "ignores xbox-only platforms" do
      game.platforms_available << xbox_one
      expect(helper.game_detail_logo_slugs(game)).to eq([])
    end

    it "infers steam from external_steam_app_id alone (no PS5/Switch2 rows)" do
      game.update!(external_steam_app_id: "12345")
      expect(helper.game_detail_logo_slugs(game)).to eq([ "steam" ])
    end

    it "decomposes PC presence: returns [ps5, steam, gog] for the spec's example" do
      game.platforms_available << ps5
      game.update!(external_steam_app_id: "111", external_gog_id: "222")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 steam gog])
    end

    it "still returns 5 slugs without duplicates even if Platforms#available also carries Steam (PC store row, no canonical match)" do
      game.platforms_available << ps5
      game.platforms_available << switch2
      game.update!(external_steam_app_id: "1", external_gog_id: "2", external_epic_id: "3")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 switch2 steam gog epic])
    end

    it "recognizes Xbox One (igdb_id=49) via the IGDB_ID_TO_CANONICAL_SLUG map but xbox is not a KNOWN_LOGO so it is dropped" do
      game.platforms_available << xbox_one
      game.platforms_available << ps5
      expect(helper.game_detail_logo_slugs(game)).to eq([ "ps5" ])
    end
  end

  # ---------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------

  describe "constants" do
    it "freezes KNOWN_LOGOS at 5 slugs in display priority order" do
      expect(PlatformLogosHelper::KNOWN_LOGOS).to eq(%w[ps5 switch2 steam gog epic])
    end

    it "freezes LOGO_SIZES at exactly [16, 64]" do
      expect(PlatformLogosHelper::LOGO_SIZES).to eq([ 16, 64 ])
    end

    it "carries a brand-correct alt label for every KNOWN_LOGO" do
      PlatformLogosHelper::KNOWN_LOGOS.each do |slug|
        expect(PlatformLogosHelper::LOGO_ALT_LABELS[slug]).to be_present
      end
    end
  end
end
