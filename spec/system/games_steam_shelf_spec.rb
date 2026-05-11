require "rails_helper"

# Phase 14 §3 — Capybara smoke for the Steam-shelf `/games` UX.
# Capybara's rack_test driver does not run JavaScript, so the spec
# verifies the rendered shelf surfaces server-side: shelf headings,
# tile links, and `[see all]` filter routes.
RSpec.describe "Games steam-shelf", type: :system do
  before { driven_by(:rack_test) }

  it "renders the empty-state copy when no games exist" do
    visit games_path
    expect(page).to have_content("no games yet.")
    # Phase 14 §1 polish (2026-05-10) — inline `_add_form` retired in
    # favor of `[+]` next to the H1 + the layout-level IGDB-search
    # modal (also reachable via `i` keypress).
    expect(page).to have_content("[+]")
    expect(page).to have_content("igdb")
  end

  context "with a populated library" do
    let!(:zelda) do
      create(:game, :synced,
             title: "Zelda BotW",
             igdb_id: 7346, release_year: 2017, igdb_rating: 95.0,
             played_at: 2.weeks.ago)
    end
    let!(:elden) do
      create(:game, :synced, title: "Elden Ring",
             igdb_id: 7347, release_year: 2022, igdb_rating: 96.0)
    end
    let!(:bundle)   { create(:bundle, name: "Soulslikes") }
    let!(:adventure) do
      g = Genre.create!(igdb_id: 5001, name: "Adventure")
      zelda.genres << g
      g
    end

    it "renders the bundles shelf at the top" do
      visit games_path
      expect(page).to have_content("bundles")
      expect(page).to have_content("Soulslikes")
    end

    it "renders the recently-played shelf" do
      visit games_path
      expect(page).to have_content("recently played")
      expect(page).to have_content("Zelda BotW")
    end

    it "renders per-genre nested sub-shelves (Phase 27 polish 2026-05-11)" do
      # The legacy `@genres_shelves` per-genre rows (which always
      # rendered `[see all]` regardless of bucket size) were retired
      # in the 2026-05-11 polish pass; the 01c-v2 nested Genres outer
      # shelf at the top of the page is the single source of truth
      # for genre-grouped tile rows. `[see all]` now renders only
      # when a sub-shelf exceeds the 30-tile cap.
      # Phase 27 follow-up (2026-05-11) — display labels are lowercase.
      visit games_path
      expect(page).to have_content("adventure")  # rendered as <h3>adventure</h3>
      expect(page).to have_css("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
    end

    it "renders the all-games heading as 'all' (Fix 8, 2026-05-11)" do
      visit games_path
      # The all-games partition heading was renamed from `all games`
      # to plain `all` in the 2026-05-11 polish pass.
      expect(page).to have_css('section[data-display-mode="grid"] h2', text: "all")
      expect(page).not_to have_css('section[data-display-mode="grid"] h2', text: "all games")
    end

    it "tile links land on the game show page" do
      visit games_path
      click_link "Zelda BotW", match: :first
      expect(page).to have_current_path(game_path(zelda))
    end
  end
end
