require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor component.
#
# Renders one fieldset per release-platform (sourced from IGDB) plus
# any platform the user already owns the game on. Each row carries an
# `_own` yes/no checkbox + optional metadata fields. The leading
# hidden field with value="no" guarantees the controller always sees
# a value regardless of the checkbox state (project rule: yes/no
# strings, never true/false/0/1).
RSpec.describe Games::PlatformOwnershipEditorComponent, type: :component do
  let(:game) { create(:game, :synced, title: "Test Game") }
  let(:ps5)   { create(:platform, name: "PS5", slug: "ps5") }
  let(:steam) { create(:platform, name: "Steam", slug: "steam") }

  # Mirror the controller's `build_ownership_rows` helper: a hash
  # keyed by Platform → in-memory or persisted ownership row.
  def build_rows(platforms)
    rows = {}
    platforms.each do |platform|
      existing = game.game_platform_ownerships.find_by(platform: platform)
      rows[platform] = existing || game.game_platform_ownerships.new(platform: platform)
    end
    rows
  end

  describe "happy: one row per release-platform" do
    before do
      game.platforms_available << ps5
      game.platforms_available << steam
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: build_rows([ ps5, steam ])
      ))
    end

    it "renders one fieldset per row" do
      expect(page).to have_css("fieldset.platform-ownership-row", count: 2)
    end

    it "renders one checkbox per row with value='yes'" do
      expect(page).to have_css('input[type="checkbox"][value="yes"]', count: 2)
    end

    it "carries a leading hidden input with value='no' (unchecked fallback)" do
      hidden_no = page.all('input[type="hidden"][value="no"]', visible: :all)
      expect(hidden_no.size).to eq(2)
    end

    it "carries a hidden platform_id field per row" do
      platform_ids = page.all('input[type="hidden"]', visible: :all).select { |i| i["name"].to_s.include?("[platform_id]") }
      expect(platform_ids.size).to eq(2)
    end

    it "labels each fieldset with the platform name" do
      expect(page).to have_css("legend", text: "PS5")
      expect(page).to have_css("legend", text: "Steam")
    end

    it "renders acquired_at, store, notes inputs per row" do
      expect(page).to have_css('input[type="date"]', count: 2)
      store_inputs = page.all('input[type="text"]').select { |i| i["name"].to_s.include?("[store]") }
      expect(store_inputs.size).to eq(2)
      notes_inputs = page.all("textarea").select { |t| t["name"].to_s.include?("[notes]") }
      expect(notes_inputs.size).to eq(2)
    end

    it "uses indexed nested-attribute names (game[game_platform_ownerships_attributes][0][...])" do
      expect(page.native.to_html).to include("game[game_platform_ownerships_attributes][0][platform_id]")
      expect(page.native.to_html).to include("game[game_platform_ownerships_attributes][1][platform_id]")
    end

    it "stamps the platform slug on the row as a data attribute" do
      expect(page).to have_css('fieldset[data-platform-slug="ps5"]')
      expect(page).to have_css('fieldset[data-platform-slug="steam"]')
    end
  end

  describe "happy: persisted row carries id hidden field and is checked" do
    let!(:ownership) { create(:game_platform_ownership, game: game, platform: ps5) }

    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: build_rows([ ps5 ])
      ))
    end

    it "carries a hidden id field for existing ownership" do
      id_inputs = page.all('input[type="hidden"]', visible: :all).select { |i| i["name"].to_s.include?("[id]") && !i["name"].to_s.include?("[platform_id]") }
      expect(id_inputs.size).to eq(1)
      expect(id_inputs.first["value"]).to eq(ownership.id.to_s)
    end

    it "checks the _own box for the existing ownership" do
      checkbox = page.find('input[type="checkbox"][value="yes"]')
      expect(checkbox.checked?).to be(true)
    end
  end

  describe "happy: un-persisted row is unchecked" do
    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: build_rows([ ps5 ])
      ))
    end

    it "leaves the _own box unchecked when no ownership exists yet" do
      checkbox = page.find('input[type="checkbox"][value="yes"]')
      expect(checkbox.checked?).to be(false)
    end

    it "still scaffolds the row so the user can tick it" do
      expect(page).to have_css("fieldset.platform-ownership-row", count: 1)
    end
  end

  describe "happy: existing values populate the row" do
    let!(:ownership) do
      create(:game_platform_ownership, game: game, platform: ps5,
             acquired_at: Date.new(2024, 3, 1),
             store: "PSN",
             notes: "from sale")
    end

    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: build_rows([ ps5 ])
      ))
    end

    it "populates acquired_at" do
      expect(page).to have_css('input[type="date"][value="2024-03-01"]')
    end

    it "populates store" do
      store_input = page.find('input[type="text"]')
      expect(store_input["value"]).to eq("PSN")
    end

    it "populates notes" do
      expect(page.find("textarea").text).to eq("from sale")
    end
  end

  describe "sad: never renders JS confirm" do
    before do
      game.platforms_available << ps5
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: build_rows([ ps5 ])
      ))
    end

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a red destructive class on the row" do
      fieldset = page.find("fieldset.platform-ownership-row")
      expect(fieldset[:class]).not_to include("text-danger")
    end
  end

  describe "edge: zero release-platforms" do
    before do
      render_inline(described_class.new(
        game: game,
        ownerships_by_platform: {}
      ))
    end

    it "renders the muted '(no platforms available)' placeholder" do
      expect(page).to have_css("p.text-muted", text: "(no platforms available)")
    end

    it "renders no fieldset" do
      expect(page).to have_no_css("fieldset.platform-ownership-row")
    end
  end
end
