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
    expect(page).to have_content("type in the search box above")
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

    it "renders per-genre shelves with [see all] links" do
      visit games_path
      expect(page).to have_content("adventure")
      expect(page).to have_link("see all", href: games_path(genre: adventure.id))
    end

    it "renders the all-games heading" do
      visit games_path
      expect(page).to have_content("all games")
    end

    it "tile links land on the game show page" do
      visit games_path
      click_link "Zelda BotW", match: :first
      expect(page).to have_current_path(game_path(zelda))
    end
  end
end
