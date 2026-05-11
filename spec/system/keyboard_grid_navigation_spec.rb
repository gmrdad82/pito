require "rails_helper"

# Vim-style `j`/`k` highlight navigation was first wired for list-page
# rows (`[data-keyboard-row]` in `app/javascript/controllers/keyboard_controller.js`).
# This spec covers the extension to tile / grid surfaces:
#
#   * `/games` and `/bundles` — tile grids. The container declares
#     `data-keyboard-grid="true"` and each tile carries
#     `data-keyboard-tile`. `j`/`k` move between visual rows of tiles
#     (geometry-driven); `h`/`l` step within the active row.
#   * `/calendar/month/...` — calendar month grid. The `<table>`
#     declares `data-keyboard-grid="calendar-month"` and each `<td>`
#     carries `data-keyboard-grid-cell`. `j`/`k` jump a full week
#     (`±7` cells); `h`/`l` step a day.
#   * `/calendar/schedule` and `/notifications` — list rows. Each row
#     carries `data-keyboard-row` so the existing list-page navigation
#     works without further controller changes.
#
# rack_test does not fire JS, so these are markup-contract specs: we
# verify the data attributes the `keyboard` Stimulus controller reads
# at runtime are present in the rendered HTML. Actual keystroke
# behaviour is exercised by hand via the manual playbook (no Selenium
# / cuprite driver in this project).
RSpec.describe "Keyboard grid / tile navigation markup", type: :system do
  before { driven_by(:rack_test) }

  describe "/games (tile grid)" do
    let!(:game_a) { create(:game, title: "Alpha") }
    let!(:game_b) { create(:game, title: "Bravo") }

    it "tags the all-games grid container with data-keyboard-grid=\"true\"" do
      visit "/games"
      expect(page).to have_css("section.all-games-grid div.grid[data-keyboard-grid='true']")
    end

    it "tags each game tile with data-keyboard-tile" do
      visit "/games"
      tiles = page.all("section.all-games-grid div.grid > a.tile[data-keyboard-tile]")
      expect(tiles.size).to eq(2)
    end

    it "does NOT opt the horizontally-scrolling shelves into grid navigation" do
      # Shelves use their own `steam-shelf` drag-scroll controller; the
      # canonical browse surface is the flat all-games grid below.
      visit "/games"
      shelves = page.all("section.shelf:not(.all-games-grid)")
      shelves.each do |shelf|
        expect(shelf["data-keyboard-grid"]).to be_nil
      end
    end
  end

  describe "/bundles (tile grid)" do
    let!(:bundle_a) { create(:bundle, name: "Mass Effect") }
    let!(:bundle_b) { create(:bundle, name: "Halo") }

    it "tags the bundles grid container with data-keyboard-grid=\"true\"" do
      visit "/bundles"
      expect(page).to have_css("div.bundles-grid[data-keyboard-grid='true']")
    end

    it "tags each bundle tile with data-keyboard-tile" do
      visit "/bundles"
      tiles = page.all("div.bundles-grid > a.tile[data-keyboard-tile]")
      expect(tiles.size).to eq(2)
    end
  end

  describe "/calendar/month (calendar grid)" do
    it "tags the month grid table with data-keyboard-grid=\"calendar-month\"" do
      visit "/calendar/month/2026/05"
      expect(page).to have_css("table.calendar-grid[data-keyboard-grid='calendar-month']")
    end

    it "tags every cell with data-keyboard-grid-cell" do
      visit "/calendar/month/2026/05"
      cells = page.all("table.calendar-grid td[data-keyboard-grid-cell]")
      # The Monday-first grid spans whole weeks, so the cell count is
      # always a multiple of 7. May 2026 starts on Friday and ends on
      # Sunday, so we expect 35 (5 rows) or 42 (6 rows). Either is fine
      # — we assert on the modulus, which is what the navigation logic
      # depends on (`j`/`k` shift ±7).
      expect(cells.size).to be > 0
      expect(cells.size % 7).to eq(0)
    end

    it "renders 7 weekday header columns matching the grid stride" do
      visit "/calendar/month/2026/05"
      headers = page.all("table.calendar-grid thead th")
      expect(headers.size).to eq(7)
    end
  end

  describe "/calendar/schedule (list rows)" do
    it "tags each schedule row with data-keyboard-row" do
      create(:calendar_entry, :milestone_manual, title: "podcast", starts_at: 2.days.from_now)
      create(:calendar_entry, :milestone_manual, title: "stream", starts_at: 4.days.from_now)

      visit "/calendar/schedule"
      rows = page.all("tr[data-keyboard-row]")
      expect(rows.size).to be >= 2
    end

    it "does NOT declare data-keyboard-grid on the schedule surface" do
      visit "/calendar/schedule"
      # Schedule is a flat list, not a grid; verifying its absence
      # protects the controller's dispatch order (grid surfaces win
      # over row surfaces when both are present).
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/notifications (list rows + modal mount)" do
    let!(:notification_a) { create(:notification, title: "alpha event") }
    let!(:notification_b) { create(:notification, title: "bravo event") }

    it "tags each notification row with data-keyboard-row + data-keyboard-row-id" do
      visit "/notifications"
      rows = page.all("tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "renders the same data-keyboard-row hook when the index is mounted in modal mode" do
      # The layout-level notifications modal pulls `/notifications?modal=yes`
      # into a Turbo Frame. The list partial is shared with the standalone
      # page, so the row hooks must survive into the modal context.
      visit "/notifications?modal=yes"
      rows = page.all("tr[data-keyboard-row]")
      expect(rows.size).to eq(2)
    end
  end

  describe "negative coverage — non-grid surfaces" do
    it "/channels does NOT declare data-keyboard-grid" do
      # `/channels` is a list table, not a grid. The controller's
      # `gridContainer()` lookup must return null so `j`/`k` route to
      # the row handler (the existing list-page navigation). Confirms
      # the negative side of the dispatch.
      visit "/channels"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end

    it "/videos does NOT declare data-keyboard-grid" do
      visit "/videos"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end
end
