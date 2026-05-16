require "rails_helper"

# Phase 27 v2 spec 07 — game show page platform-logo row.
#
# The show page LEFT pane renders 0..5 56-px platform-logo `<img>`
# tags after the genres / platforms paragraph. Order is the locked
# PS5 / Switch2 / Steam / GoG / Epic walk. The Rake-downloaded
# 64-px assets are scaled down to 56 px via inline styling.
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
    it "renders one 56-px PS5 logo when the game is on PS5" do
      game.platforms_available << ps5
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      img = container.find("img.platform-logo--ps5")
      expect(img[:src]).to eq("/platform_logos/ps5-64.png")
      expect(img[:width]).to eq("56")
      expect(img[:height]).to eq("56")
      expect(img[:alt]).to eq("PS5")
    end

    it "renders multiple logos in the locked KNOWN_LOGOS order" do
      game.platforms_available << switch2
      game.platforms_available << ps5
      game.update!(external_steam_app_id: "111", external_gog_id: "222", external_epic_id: "333")
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      slugs_in_order = container.all("img.platform-logo").map { |img| img[:src] }
      expect(slugs_in_order).to eq([
        "/platform_logos/ps5-64.png",
        "/platform_logos/switch2-64.png",
        "/platform_logos/steam-64.png",
        "/platform_logos/gog-64.png",
        "/platform_logos/epic-64.png"
      ])
    end

    it "renders the steam/gog/epic logos when only the external_* ids are set" do
      game.update!(external_steam_app_id: "1", external_gog_id: "2", external_epic_id: "3")
      render

      container = Capybara.string(rendered).find(".game-detail-platform-logos")
      expect(container).to have_css("img.platform-logo--steam")
      expect(container).to have_css("img.platform-logo--gog")
      expect(container).to have_css("img.platform-logo--epic")
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
