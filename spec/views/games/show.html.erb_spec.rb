require "rails_helper"

# Phase 27 v2 spec 07 (v7: theme-aware) — game show page
# platform-logo row.
#
# The show page LEFT pane renders 0..3 56-px platform-logo entries
# after the genres / platforms paragraph. Order is the locked
# PS5 / Switch2 / Steam walk (GoG / Epic dropped — PC stores
# collapsed into Steam). The Rake-downloaded 64-px assets are
# scaled down to 56 px via the helper's `display_size:` arg.
#
# Each entry is a `.platform-logo-pair` wrapper holding BOTH a
# black and a white `<img>` variant; CSS picks the visible one off
# `<html data-theme>`. Assertions target the black variant for
# canonical paths and alt text — the white variant carries the
# same metadata, just the `-white.png` URL.
RSpec.describe "games/show.html.erb", type: :view do
  def make_platform(slug:, name: nil, igdb_id: nil)
    record = create(:platform, name: name || "Platform-#{slug}", igdb_id: igdb_id)
    record.update_column(:slug, slug) if slug
    record.reload
  end

  let(:ps5)     { make_platform(slug: "ps5") }
  let(:switch2) { make_platform(slug: "switch2") }
  let(:xbox_one) { create(:platform, name: "Xbox One", igdb_id: 49) }

  # The `:synced` trait stamps `external_steam_app_id` by default,
  # which would trigger the Steam logo for the empty-state cases. We
  # override it to nil so every example can opt platforms in
  # explicitly.
  let(:game) { create(:game, :synced, title: "Show Game", external_steam_app_id: nil) }

  before { assign(:game, game) }

  describe "platform-logo row — happy paths" do
    it "renders one 56-px PS5 logo pair when the game is on PS5" do
      game.platforms_available << ps5
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      pair = container.find(".platform-logo-pair--ps5")
      black = pair.find("img.platform-logo--black")
      expect(black[:src]).to eq("/platforms/ps5-64-black.png")
      expect(black[:width]).to eq("56")
      expect(black[:height]).to eq("56")
      expect(black[:alt]).to eq("PS5")

      white = pair.find("img.platform-logo--white")
      expect(white[:src]).to eq("/platforms/ps5-64-white.png")
    end

    it "renders multiple logos in the locked KNOWN_LOGOS order" do
      game.platforms_available << switch2
      game.platforms_available << ps5
      game.update!(external_steam_app_id: "111")
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      black_srcs = container.all("img.platform-logo--black").map { |img| img[:src] }
      expect(black_srcs).to eq([
        "/platforms/ps5-64-black.png",
        "/platforms/switch2-64-black.png",
        "/platforms/steam-64-black.png"
      ])
    end

    it "renders the Steam logo pair when only external_steam_app_id is set" do
      game.update!(external_steam_app_id: "1")
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      expect(container).to have_css(".platform-logo-pair--steam")
      expect(container.find("img.platform-logo--black")[:src]).to eq("/platforms/steam-64-black.png")
    end

    it "applies the flex/gap layout to the logo row" do
      game.platforms_available << ps5
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      expect(container[:style]).to include("display: flex")
      expect(container[:style]).to include("gap: 8px")
    end
  end

  describe "platform-logo row — empty state" do
    it "renders NO logo container when the game has no known platform exposure" do
      # `game` let — no platforms attached, no external store ids.
      render
      expect(rendered).not_to have_css(".game-detail-platform-logos")
    end

    it "renders NO logo container for an Xbox-only game" do
      game.platforms_available << xbox_one
      render
      expect(rendered).not_to have_css(".game-detail-platform-logos")
    end
  end
end
