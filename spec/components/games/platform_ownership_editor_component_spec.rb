require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor component (revamped
# 2026-05-12).
#
# Renders a flat list of bracketed-checkbox rows — one per release-
# platform plus any platform the user already owns the game on. Uses
# the project's canonical `.md-check` pattern: a real
# `<input type="checkbox">` (visually hidden via CSS) and a
# `<span class="md-check-indicator">` whose `[ ]` / `[x]` is drawn by
# CSS pseudo-element. No per-row metadata inputs.
RSpec.describe Games::PlatformOwnershipEditorComponent, type: :component do
  let(:game) { create(:game, :synced, title: "Test Game") }
  let(:ps5)   { create(:platform, name: "PS5", slug: "ps5") }
  let(:steam) { create(:platform, name: "Steam", slug: "steam") }

  describe "happy: one row per platform" do
    before do
      game.platforms_available << ps5
      game.platforms_available << steam
      render_inline(described_class.new(
        game: game,
        platforms: [ ps5, steam ],
        owned_platform_ids: []
      ))
    end

    it "renders one .md-check label per platform" do
      expect(page).to have_css("label.md-check", count: 2)
    end

    it "renders one checkbox per platform with value=<platform.id>" do
      expect(page).to have_css('input[type="checkbox"][value="' + ps5.id.to_s + '"]')
      expect(page).to have_css('input[type="checkbox"][value="' + steam.id.to_s + '"]')
    end

    it "uses the flat `platform_owned_ids[]` array name on every input" do
      checkboxes = page.all('input[type="checkbox"]', visible: :all)
      expect(checkboxes.size).to eq(2)
      checkboxes.each { |cb| expect(cb["name"]).to eq("platform_owned_ids[]") }
    end

    it "renders the bracketed indicator span per row (CSS draws [ ] / [x])" do
      expect(page).to have_css("span.md-check-indicator", count: 2)
    end

    it "renders the platform name as the label text" do
      expect(page).to have_css("span.md-check-label", text: "PS5")
      expect(page).to have_css("span.md-check-label", text: "Steam")
    end

    it "stamps the platform slug on the label as a data attribute" do
      expect(page).to have_css('label.md-check[data-platform-slug="ps5"]')
      expect(page).to have_css('label.md-check[data-platform-slug="steam"]')
    end

    it "renders NO acquired_at / store / notes inputs (dropped in 2026-05-12 revamp)" do
      expect(page).to have_no_css('input[type="date"]')
      expect(page).to have_no_css("textarea")
      # No text inputs in the editor body at all.
      expect(page.native.to_html).not_to include("[store]")
      expect(page.native.to_html).not_to include("[notes]")
      expect(page.native.to_html).not_to include("[acquired_at]")
    end

    it "renders NO <fieldset> per-platform groupings" do
      expect(page).to have_no_css("fieldset")
    end
  end

  describe "happy: owned platform is checked" do
    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        platforms: [ ps5 ],
        owned_platform_ids: [ ps5.id ]
      ))
    end

    it "checks the box for the owned platform" do
      checkbox = page.find('input[type="checkbox"]', visible: :all)
      expect(checkbox.checked?).to be(true)
    end
  end

  describe "happy: un-owned platform is unchecked" do
    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        platforms: [ ps5 ],
        owned_platform_ids: []
      ))
    end

    it "leaves the box unchecked" do
      checkbox = page.find('input[type="checkbox"]', visible: :all)
      expect(checkbox.checked?).to be(false)
    end
  end

  describe "sad: never renders JS confirm" do
    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        platforms: [ ps5 ],
        owned_platform_ids: []
      ))
    end

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a red destructive class on a row" do
      label = page.find("label.md-check")
      expect(label[:class]).not_to include("text-danger")
    end
  end

  describe "edge: zero platforms" do
    before do
      render_inline(described_class.new(
        game: game,
        platforms: [],
        owned_platform_ids: []
      ))
    end

    it "renders the muted '(no platforms available)' placeholder" do
      expect(page).to have_css("p.text-muted", text: "(no platforms available)")
    end

    it "renders no checkbox row" do
      expect(page).to have_no_css("label.md-check")
    end
  end
end
