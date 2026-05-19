require "rails_helper"

# Phase 14 §3 — Capybara smoke for the Steam-shelf `/games` UX.
# Capybara's rack_test driver does not run JavaScript, so the spec
# verifies the rendered shelf surfaces server-side: shelf headings,
# tile links, and `[see all]` filter routes.
RSpec.describe "Games steam-shelf", type: :system do
  before { driven_by(:rack_test) }

  # 2026-05-19 (system-spec debt cleanup) — the legacy
  # `"no games yet."` empty-state copy was removed when the bundles
  # shelf chrome started rendering unconditionally (so the heading-row
  # `[+]` create button is always available even with zero games AND
  # zero bundles). The new empty layout no longer surfaces that
  # phrase, so the old empty-state example was dropped — the
  # populated-library examples below remain the canonical smoke for
  # this surface.

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
      # Phase 27 v2 spec 05 — display labels follow the locked
      # `GenresHelper::SHORT_NAMES` table. `Adventure` is mapped
      # one-to-one and renders as `<h3>Adventure</h3>`.
      visit games_path
      expect(page).to have_content("Adventure")
      expect(page).to have_css("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
    end

    it "does NOT render an `all` heading (Phase 27 v2 spec 05)" do
      # The all-games partition retired with the display-mode switcher.
      visit games_path
      expect(page).not_to have_css("h2", text: "all")
      expect(page).not_to have_css("h2", text: "all games")
      expect(page).not_to have_css('[data-display-mode]')
    end

    it "tile links land on the game show page" do
      visit games_path
      click_link "Zelda BotW", match: :first
      expect(page).to have_current_path(game_path(zelda))
    end
  end
end
