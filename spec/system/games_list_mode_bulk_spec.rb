require "rails_helper"

# 2026-05-11 polish (Games list-mode bulk actions, Fixes 4-6 + 1-3) —
# system-level coverage for:
#   - Two-row filter row layout + casing on platform chip labels
#   - Display-mode switcher renders `[default][grid][list]`
#   - List-mode column reorder (title, genre, released, rating, owned)
#   - Header `[ ]` select-all toggles every per-row `[ ]` checkbox
#   - URL round-trip: `?filters=released,owned,ps5&display=default`
#     renders the correct mode + active chips.
#
# Driver: rack_test where adequate (pure HTML / forms). The header
# checkbox + bulk toolbar are wired in JS (Stimulus); for the click +
# toolbar tests we'd need a JS-capable driver. Rack-test still exercises
# the HTML shape (checkbox presence, toolbar markup).
RSpec.describe "Games list-mode bulk actions + filter polish", type: :system do
  before { driven_by(:rack_test) }

  let!(:platform_ps5) { Platform.find_by(slug: "ps5") || create(:platform, name: "ps5", slug: "ps5") }
  let!(:game_owned) do
    g = create(:game, title: "Owned Game", release_date: 2.years.ago.to_date)
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end
  let!(:game_unowned) { create(:game, title: "Unowned Game", release_date: 2.years.ago.to_date) }

  describe "filter row — two-row layout (Fixes 1 + 3)" do
    it "renders row 1 with status + platform chips (including xbox)" do
      visit games_path

      row_1_chips = page.all(".games-filter-row__chips--1 a.filter-chip")
                       .map { |a| a["data-filter-token"] }
      expect(row_1_chips).to eq(%w[released scheduled ps5 switch2 steam gog epic xbox])
    end

    it "renders row 2 with ownership + recorded chips" do
      visit games_path

      row_2_chips = page.all(".games-filter-row__chips--2 a.filter-chip")
                       .map { |a| a["data-filter-token"] }
      expect(row_2_chips).to eq(%w[owned not_owned recorded])
    end

    it "renders platform chip labels in canonical casing (PS5, Switch2, etc)" do
      visit games_path

      [ "PS5", "Switch2", "Steam", "GoG", "Epic", "Xbox" ].each do |label|
        expect(page).to have_css(".games-filter-row__chips--1 a.filter-chip", text: label)
      end
    end

    it "places the display-mode switcher in row 2's right slot" do
      visit games_path

      expect(page).to have_css(".games-filter-row__row--2 .games-filter-row__right .display-mode-switcher")
    end
  end

  describe "display-mode switcher (Fix 2) — `[default][grid][list]`" do
    it "renders the three buttons in order" do
      visit games_path

      buttons = find(".display-mode-switcher").all("button.bracketed").map(&:text).map(&:strip)
      expect(buttons).to eq([ "[default]", "[grid]", "[list]" ])
    end

    it "treats `default` as the canonical nested-shelves view" do
      visit games_path(display: "default")
      expect(page).to have_css('section[data-display-mode="shelves_by_letter"]')

      switcher = find(".display-mode-switcher")
      expect(switcher).to have_css("button.bracketed.active", text: "default")
    end
  end

  describe "list-mode column order (Fix 4) — title, genre, released, rating, owned" do
    it "renders the column header row in the locked v2 order" do
      visit games_path(display: "list")

      headers = find('section[data-display-mode="list"] table.list-table thead tr')
                  .all("th").map(&:text)
      expect(headers).to eq([
        "", "", "title", "genre", "released", "rating", "owned"
      ])
    end

    it "renders a real `[ ]` header checkbox in the select cell" do
      visit games_path(display: "list")

      header_row = find('section[data-display-mode="list"] table.list-table thead tr')
      expect(header_row).to have_css('input[type="checkbox"][data-bulk-select-target="headerCheckbox"]')
    end

    it "renders a per-row `[ ]` checkbox carrying the game id" do
      visit games_path(display: "list")

      row = find("tr.game-row[data-game-id='#{game_owned.id}']")
      checkbox = row.find('input[type="checkbox"][data-bulk-select-target="checkbox"]')
      expect(checkbox.value).to eq(game_owned.id.to_s)
    end
  end

  describe "list-mode bulk-action toolbar (Fix 5) — wired to /syncs and /deletions" do
    it "wraps the list-mode section in a `bulk-select` Stimulus controller" do
      visit games_path(display: "list")

      section = find('section[data-display-mode="list"]')
      expect(section["data-controller"]).to include("bulk-select")
      expect(section["data-bulk-select-delete-type-value"]).to eq("game")
      expect(section["data-bulk-select-sync-type-value"]).to eq("game")
    end

    it "renders the bulk-toolbar shell (hidden actions; the controller unhides them when selection ≥ 1)" do
      visit games_path(display: "list")

      toolbar = find('section[data-display-mode="list"] .games-bulk-toolbar')
      expect(toolbar["data-bulk-select-target"]).to eq("actions")
      expect(toolbar).to have_css('[data-bulk-select-target="syncAction"]', visible: :all)
      expect(toolbar).to have_css('[data-bulk-select-target="deleteAction"]', visible: :all)
    end
  end

  describe "URL round-trip (Fix 6) — `?filters=...&display=default`" do
    it "honors filters + display together; clear-all preserves display" do
      visit games_path(filters: "released,owned,ps5", display: "default")

      # The resolved display mode is the nested-shelves view.
      expect(page).to have_css('section[data-display-mode="shelves_by_letter"]')

      # The three requested chips render as `[x]` (active).
      [ "released", "owned", "PS5" ].each do |label|
        expect(page).to have_css("a.filter-chip.chip--active", text: label)
      end

      # `[clear all]` preserves display=default.
      clear_all = find(".games-filter-row__clear-all a")
      expect(clear_all["href"]).to eq("/games?display=default")
    end

    it "platform chip hrefs preserve display=default" do
      visit games_path(display: "default")

      page.all(".games-filter-row__chips--1 a.filter-chip").each do |a|
        expect(a["href"]).to include("display=default")
      end
    end

    it "renders only `Owned Game` when filters=owned" do
      visit games_path(filters: "owned", display: "list")

      list_section = find('section[data-display-mode="list"]')
      expect(list_section).to have_link("Owned Game")
      expect(list_section).to have_no_link("Unowned Game")
    end
  end
end
