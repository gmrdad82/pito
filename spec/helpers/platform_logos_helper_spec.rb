require "rails_helper"

# Phase 27 v2 spec 07 (v7) — `PlatformLogosHelper` covers:
#
#   - `platform_logo_tag(slug, size:, color:, display_size:)` —
#     `<img>` emission per color variant, theme-aware pair emission
#     for `color: :auto` (default), alt text, unknown-slug nil,
#     invalid-size / invalid-color raise.
#   - `game_index_tile_logo_slug(game)` — one-logo-per-tile selection
#     (owned wins; KNOWN_LOGOS declaration order).
#   - `game_detail_logo_slugs(game)` — multi-logo detail-page set
#     in locked PS5 / Switch2 / Steam order.
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
  let(:xbox_one) { create(:platform, name: "Xbox One", igdb_id: 49) }

  # ---------------------------------------------------------------
  # `platform_logo_tag` — `color: :auto` (default, theme-aware)
  # ---------------------------------------------------------------

  describe "#platform_logo_tag (default color: :auto — theme-aware pair)" do
    it "wraps both black + white variants in a `.platform-logo-pair` span" do
      html = helper.platform_logo_tag("ps5", size: 16)
      wrapper = Capybara.string(html.to_s).find(".platform-logo-pair")
      expect(wrapper[:class].split).to include("platform-logo-pair", "platform-logo-pair--ps5")
    end

    it "emits both the black AND the white img inside the pair wrapper" do
      html = helper.platform_logo_tag("ps5", size: 16)
      doc = Capybara.string(html.to_s)
      expect(doc).to have_css("img.platform-logo--black")
      expect(doc).to have_css("img.platform-logo--white")
    end

    it "points the black img at `/platforms/<slug>-<size>-black.png`" do
      html = helper.platform_logo_tag("ps5", size: 16)
      img = Capybara.string(html.to_s).find("img.platform-logo--black")
      expect(img[:src]).to eq("/platforms/ps5-16-black.png")
    end

    it "points the white img at `/platforms/<slug>-<size>-white.png`" do
      html = helper.platform_logo_tag("ps5", size: 16)
      img = Capybara.string(html.to_s).find("img.platform-logo--white")
      expect(img[:src]).to eq("/platforms/ps5-16-white.png")
    end

    it "tags the black img with data-theme='light' and the white img with data-theme='dark'" do
      html = helper.platform_logo_tag("ps5", size: 16)
      doc = Capybara.string(html.to_s)
      expect(doc.find("img.platform-logo--black")["data-theme"]).to eq("light")
      expect(doc.find("img.platform-logo--white")["data-theme"]).to eq("dark")
    end

    it "scopes BOTH inner imgs to the theme via the .platform-logo--{black,white} CSS hook" do
      html = helper.platform_logo_tag("ps5", size: 16)
      doc = Capybara.string(html.to_s)
      expect(doc.find("img.platform-logo--black")[:class].split).to include("platform-logo--black")
      expect(doc.find("img.platform-logo--white")[:class].split).to include("platform-logo--white")
    end

    it "sizes the wrapper to the rendered footprint (`width: 16px; height: 16px`)" do
      html = helper.platform_logo_tag("ps5", size: 16)
      wrapper = Capybara.string(html.to_s).find(".platform-logo-pair")
      expect(wrapper[:style]).to include("width: 16px")
      expect(wrapper[:style]).to include("height: 16px")
    end

    it "honors `display_size:` for the wrapper footprint (16-px asset rendered at 14 px)" do
      html = helper.platform_logo_tag("ps5", size: 16, display_size: 14)
      wrapper = Capybara.string(html.to_s).find(".platform-logo-pair")
      expect(wrapper[:style]).to include("width: 14px")
      expect(wrapper[:style]).to include("height: 14px")
    end

    it "applies the display_size to BOTH inner imgs as width/height attrs" do
      html = helper.platform_logo_tag("ps5", size: 16, display_size: 14)
      doc = Capybara.string(html.to_s)
      [ "img.platform-logo--black", "img.platform-logo--white" ].each do |selector|
        img = doc.find(selector)
        expect(img[:width]).to eq("14")
        expect(img[:height]).to eq("14")
      end
    end

    it "defaults display_size to size when omitted (16 px asset renders at 16 px)" do
      html = helper.platform_logo_tag("ps5", size: 16)
      img = Capybara.string(html.to_s).find("img.platform-logo--black")
      expect(img[:width]).to eq("16")
      expect(img[:height]).to eq("16")
    end

    it "renders the 64-px paired set with matching srcs and alt labels" do
      html = helper.platform_logo_tag("ps5", size: 64)
      doc = Capybara.string(html.to_s)
      expect(doc.find("img.platform-logo--black")[:src]).to eq("/platforms/ps5-64-black.png")
      expect(doc.find("img.platform-logo--white")[:src]).to eq("/platforms/ps5-64-white.png")
      expect(doc.find("img.platform-logo--black")[:alt]).to eq("PS5")
      expect(doc.find("img.platform-logo--white")[:alt]).to eq("PS5")
    end

    it "carries the slug modifier on BOTH inner imgs" do
      html = helper.platform_logo_tag("switch2", size: 16)
      doc = Capybara.string(html.to_s)
      expect(doc.find("img.platform-logo--black")[:class].split).to include("platform-logo--switch2")
      expect(doc.find("img.platform-logo--white")[:class].split).to include("platform-logo--switch2")
    end

    it "returns nil for an unknown slug" do
      expect(helper.platform_logo_tag("evil", size: 16)).to be_nil
    end

    it "raises ArgumentError for the dropped 128 px size" do
      expect { helper.platform_logo_tag("ps5", size: 128) }
        .to raise_error(ArgumentError, /unknown logo size/)
    end
  end

  # ---------------------------------------------------------------
  # `platform_logo_tag` — explicit `color: :black`
  # ---------------------------------------------------------------

  describe "#platform_logo_tag (color: :black — single variant)" do
    it "renders a single `<img>` pointing at the black variant" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :black)
      doc = Capybara.string(html.to_s)
      # No pair wrapper — caller asked for one specific color.
      expect(doc).to have_no_css(".platform-logo-pair")
      img = doc.find("img")
      expect(img[:src]).to eq("/platforms/ps5-16-black.png")
    end

    it "tags the img with `.platform-logo--black`" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :black)
      img = Capybara.string(html.to_s).find("img")
      expect(img[:class].split).to include("platform-logo", "platform-logo--ps5", "platform-logo--black")
    end

    it "tags the img with data-theme='light' so the off-theme rule could hide it" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :black)
      img = Capybara.string(html.to_s).find("img")
      expect(img["data-theme"]).to eq("light")
    end

    it "uses the canonical short label as alt text" do
      html = helper.platform_logo_tag("switch2", size: 16, color: :black)
      expect(Capybara.string(html.to_s).find("img")[:alt]).to eq("Switch2")
    end

    it "honors display_size when provided" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :black, display_size: 14)
      img = Capybara.string(html.to_s).find("img")
      expect(img[:width]).to eq("14")
      expect(img[:height]).to eq("14")
      expect(img[:style]).to include("width: 14px")
    end
  end

  # ---------------------------------------------------------------
  # `platform_logo_tag` — explicit `color: :white`
  # ---------------------------------------------------------------

  describe "#platform_logo_tag (color: :white — single variant)" do
    it "renders a single `<img>` pointing at the white variant" do
      html = helper.platform_logo_tag("ps5", size: 64, color: :white)
      doc = Capybara.string(html.to_s)
      expect(doc).to have_no_css(".platform-logo-pair")
      img = doc.find("img")
      expect(img[:src]).to eq("/platforms/ps5-64-white.png")
    end

    it "tags the img with `.platform-logo--white`" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :white)
      img = Capybara.string(html.to_s).find("img")
      expect(img[:class].split).to include("platform-logo", "platform-logo--ps5", "platform-logo--white")
    end

    it "tags the img with data-theme='dark' so the off-theme rule could hide it" do
      html = helper.platform_logo_tag("ps5", size: 16, color: :white)
      img = Capybara.string(html.to_s).find("img")
      expect(img["data-theme"]).to eq("dark")
    end

    it "carries the alt label" do
      html = helper.platform_logo_tag("steam", size: 16, color: :white)
      expect(Capybara.string(html.to_s).find("img")[:alt]).to eq("Steam")
    end
  end

  # ---------------------------------------------------------------
  # `platform_logo_tag` — input validation + nil-out-of-set
  # ---------------------------------------------------------------

  describe "#platform_logo_tag input validation" do
    it "raises ArgumentError when color is not :auto / :black / :white" do
      expect { helper.platform_logo_tag("ps5", size: 16, color: :red) }
        .to raise_error(ArgumentError, /unknown logo color/)
    end

    it "raises ArgumentError for color as a string (must be a Symbol)" do
      expect { helper.platform_logo_tag("ps5", size: 16, color: "black") }
        .to raise_error(ArgumentError, /unknown logo color/)
    end

    it "raises ArgumentError when size is not in LOGO_SIZES" do
      expect { helper.platform_logo_tag("ps5", size: 32) }
        .to raise_error(ArgumentError, /unknown logo size/)
    end

    it "raises ArgumentError for size: 0" do
      expect { helper.platform_logo_tag("ps5", size: 0) }
        .to raise_error(ArgumentError)
    end

    it "returns nil for the dropped gog slug (no longer in KNOWN_LOGOS)" do
      expect(helper.platform_logo_tag("gog", size: 16)).to be_nil
    end

    it "returns nil for the dropped epic slug (no longer in KNOWN_LOGOS)" do
      expect(helper.platform_logo_tag("epic", size: 16)).to be_nil
    end

    it "returns nil for xbox (intentionally NOT in KNOWN_LOGOS)" do
      expect(helper.platform_logo_tag("xbox", size: 16)).to be_nil
    end

    it "returns nil for an unknown slug even when an explicit color is supplied" do
      expect(helper.platform_logo_tag("evil", size: 16, color: :black)).to be_nil
      expect(helper.platform_logo_tag("evil", size: 16, color: :white)).to be_nil
    end
  end

  # ---------------------------------------------------------------
  # URL composition contracts
  # ---------------------------------------------------------------

  describe "URL composition" do
    it "points srcs at /platforms/ (not the retired /platform_logos/ folder)" do
      html = helper.platform_logo_tag("ps5", size: 64)
      Capybara.string(html.to_s).all("img").each do |img|
        expect(img[:src]).to start_with("/platforms/")
        expect(img[:src]).not_to include("/platform_logos/")
      end
    end

    it "includes the color segment in the URL (never the pre-v7 color-less filename)" do
      html_auto  = helper.platform_logo_tag("ps5", size: 16)
      html_black = helper.platform_logo_tag("ps5", size: 16, color: :black)
      html_white = helper.platform_logo_tag("ps5", size: 16, color: :white)

      all_srcs = [ html_auto, html_black, html_white ].flat_map { |html| Capybara.string(html.to_s).all("img").map { |img| img[:src] } }

      # No legacy color-less filename should appear in any of the three.
      expect(all_srcs).not_to include("/platforms/ps5-16.png")
      expect(all_srcs.uniq).to match_array([ "/platforms/ps5-16-black.png", "/platforms/ps5-16-white.png" ])
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

    it "PS5 wins over Steam when owned on both" do
      game.owned_platforms << steam
      game.owned_platforms << ps5
      expect(helper.game_index_tile_logo_slug(game)).to eq("ps5")
    end

    it "Switch2 wins over Steam when owned on both" do
      game.owned_platforms << steam
      game.owned_platforms << switch2
      expect(helper.game_index_tile_logo_slug(game)).to eq("switch2")
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

    it "returns the slug set in the locked PS5/Switch2/Steam order" do
      game.platforms_available << ps5
      game.platforms_available << switch2
      game.update!(external_steam_app_id: "111")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 switch2 steam])
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

    it "decomposes PC presence: returns [ps5, steam] for a ps5 + steam game" do
      game.platforms_available << ps5
      game.update!(external_steam_app_id: "111")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 steam])
    end

    it "returns all 3 slugs without duplicates when every channel applies" do
      game.platforms_available << ps5
      game.platforms_available << switch2
      game.update!(external_steam_app_id: "1")
      expect(helper.game_detail_logo_slugs(game)).to eq(%w[ps5 switch2 steam])
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
    it "freezes KNOWN_LOGOS at 3 slugs in display priority order" do
      expect(PlatformLogosHelper::KNOWN_LOGOS).to eq(%w[ps5 switch2 steam])
    end

    it "freezes LOGO_SIZES at exactly [16, 64] (128 dropped)" do
      expect(PlatformLogosHelper::LOGO_SIZES).to eq([ 16, 64 ])
    end

    it "freezes LOGO_COLORS at exactly [:black, :white]" do
      expect(PlatformLogosHelper::LOGO_COLORS).to eq(%i[black white])
    end

    it "carries a brand-correct alt label for every KNOWN_LOGO" do
      PlatformLogosHelper::KNOWN_LOGOS.each do |slug|
        expect(PlatformLogosHelper::LOGO_ALT_LABELS[slug]).to be_present
      end
    end

    it "does NOT carry alt labels for the dropped gog/epic slugs" do
      expect(PlatformLogosHelper::LOGO_ALT_LABELS).not_to have_key("gog")
      expect(PlatformLogosHelper::LOGO_ALT_LABELS).not_to have_key("epic")
    end
  end
end
