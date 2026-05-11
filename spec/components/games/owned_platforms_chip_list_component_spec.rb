require "rails_helper"

# Phase 27 §01f — Owned-platforms chip list component.
#
# Renders one bracketed chip per platform the user owns the game on,
# alphabetical case-insensitive. Each chip links to the filtered
# `/games?filters=<slug>,owned` URL that Phase 27 01b's filter row
# consumes. Empty ownership renders a muted placeholder.
RSpec.describe Games::OwnedPlatformsChipListComponent, type: :component do
  let(:game) { create(:game, :synced, title: "Test Game") }

  describe "happy: one chip per owned platform" do
    let!(:steam) { create(:platform, name: "Steam", slug: "steam") }
    let!(:ps5)   { create(:platform, name: "PS5", slug: "ps5") }

    before do
      create(:game_platform_ownership, game: game, platform: ps5)
      create(:game_platform_ownership, game: game, platform: steam)
      render_inline(described_class.new(game: game))
    end

    it "renders a bracketed chip for each owned platform" do
      expect(page).to have_css("a.bracketed", count: 2)
    end

    it "labels each chip with the platform name" do
      expect(page).to have_link("PS5")
      expect(page).to have_link("Steam")
    end

    it "links each chip to /games?filters=<slug>,owned" do
      ps5_link   = page.find_link("PS5")
      steam_link = page.find_link("Steam")
      expect(ps5_link["href"]).to include("filters=ps5%2Cowned").or include("filters=ps5,owned")
      expect(steam_link["href"]).to include("filters=steam%2Cowned").or include("filters=steam,owned")
    end

    it "renders chips in alphabetical (case-insensitive) order" do
      labels = page.all("a.bracketed").map(&:text)
      # `text` includes the surrounding brackets — order is what we assert on.
      expect(labels.first).to include("PS5")
      expect(labels.last).to include("Steam")
    end
  end

  describe "happy: alphabetical case-insensitive ordering" do
    it "orders 'epic' before 'PS5' before 'Steam'" do
      epic  = create(:platform, name: "epic",  slug: "epic")
      ps5   = create(:platform, name: "PS5",   slug: "ps5")
      steam = create(:platform, name: "Steam", slug: "steam")
      [ ps5, steam, epic ].each { |p| create(:game_platform_ownership, game: game, platform: p) }

      render_inline(described_class.new(game: game))
      labels = page.all("a.bracketed").map(&:text)
      expect(labels[0]).to include("epic")
      expect(labels[1]).to include("PS5")
      expect(labels[2]).to include("Steam")
    end
  end

  describe "sad: empty ownership" do
    before { render_inline(described_class.new(game: game)) }

    it "renders the muted placeholder" do
      expect(page).to have_css("span.text-muted",
                               text: "(not owned on any platform)")
    end

    it "renders no chip" do
      expect(page).to have_no_css("a.bracketed")
    end
  end

  # Project hard rule: no JS confirm anywhere. The chip list is a
  # bracketed link list; verify no `data-turbo-confirm` slips in.
  describe "flaw: no JS confirm" do
    let!(:steam) { create(:platform, name: "Steam", slug: "steam") }

    before do
      create(:game_platform_ownership, game: game, platform: steam)
      render_inline(described_class.new(game: game))
    end

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a destructive class" do
      expect(page.native.to_html).not_to include("text-danger")
    end
  end
end
