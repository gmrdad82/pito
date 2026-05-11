require "rails_helper"

# Phase 27 §01c — Genres + Collections shelves on `/games`.
#
# Both shelves render at the top of `/games`, alphabetical (case-
# insensitive) with a stable `id` tiebreak. Each tile is a link to
# `/games?genre=<slug>` or `/games?collection=<slug>`; the existing
# filter codepath narrows `@all_games` so the shelves work standalone
# while 01b's filter row is still in flight.
#
# Capybara's rack_test driver is sufficient — there is no JS in this
# surface beyond the steam-shelf wheel/drag controller, which is a
# pure UX affordance and not under test.
RSpec.describe "Games index — shelves (01c)", type: :system do
  before { driven_by(:rack_test) }

  describe "Genres shelf" do
    it "renders the heading even when no genres exist" do
      visit games_path
      expect(page).to have_content("genres")
      expect(page).to have_content("(no genres yet)")
    end

    it "renders one tile per genre, alphabetical (case-insensitive)" do
      Genre.create!(igdb_id: 1, name: "rpg",       slug: "rpg")
      Genre.create!(igdb_id: 2, name: "Adventure", slug: "adventure")
      Genre.create!(igdb_id: 3, name: "platformer", slug: "platformer")

      visit games_path
      # Section-scope the lookup so the recently-played/per-genre shelves
      # below don't shadow the order we're asserting.
      shelf = find("section.shelf--genres")
      names = shelf.all(".tile-caption").map(&:text)
      expect(names).to eq(%w[Adventure platformer rpg])
    end

    it "renders an empty-state placeholder when there are no genres" do
      visit games_path
      shelf = find("section.shelf--genres")
      expect(shelf).to have_content("(no genres yet)")
    end

    it "stamps the steam-shelf Stimulus controller on the shelf row" do
      visit games_path
      expect(page).to have_css("section.shelf--genres[data-controller='steam-shelf']")
    end
  end

  describe "Collections shelf" do
    it "renders the heading even when no collections exist" do
      visit games_path
      expect(page).to have_content("collections")
      expect(page).to have_content("(no collections yet)")
    end

    it "renders one tile per collection, alphabetical (case-insensitive)" do
      create(:collection, name: "zelda")
      create(:collection, name: "Action games")
      create(:collection, name: "mecha")

      visit games_path
      shelf = find("section.shelf--collections")
      names = shelf.all(".tile-caption").map(&:text)
      expect(names).to eq([ "Action games", "mecha", "zelda" ])
    end

    it "renders an empty-state placeholder when there are no collections" do
      visit games_path
      shelf = find("section.shelf--collections")
      expect(shelf).to have_content("(no collections yet)")
    end

    it "stamps the steam-shelf Stimulus controller on the shelf row" do
      visit games_path
      expect(page).to have_css("section.shelf--collections[data-controller='steam-shelf']")
    end
  end

  describe "Tile navigation" do
    let!(:adventure) { Genre.create!(igdb_id: 1001, name: "Adventure", slug: "adventure") }
    let!(:rpg)       { Genre.create!(igdb_id: 1002, name: "RPG",       slug: "rpg") }
    let!(:zelda) do
      g = create(:game, :synced, title: "Zelda BotW", release_year: 2017)
      g.genres << adventure
      g
    end
    let!(:elden) do
      g = create(:game, :synced, title: "Elden Ring", release_year: 2022)
      g.genres << rpg
      g
    end
    let!(:retro) { create(:collection, name: "Retro favorites") }

    it "Genre tile links to /games?genre=<slug> and narrows the listing" do
      visit games_path
      # `match: :first` because the per-genre legacy shelf below also
      # has tiles; the topmost link in document order is the 01c shelf.
      adventure_tile = find("section.shelf--genres .tile-caption", text: "Adventure")
      adventure_tile.find(:xpath, "..").click

      expect(page).to have_current_path(games_path(genre: "adventure"))
      expect(page).to have_content("Zelda BotW")
      # Elden Ring (RPG genre) is filtered out of the all-games grid.
      expect(page).not_to have_selector(".grid", text: "Elden Ring")
    end

    it "Collection tile links to /games?collection=<slug>" do
      visit games_path
      retro_tile = find("section.shelf--collections .tile-caption", text: "Retro favorites")
      retro_tile.find(:xpath, "..").click

      expect(page).to have_current_path(games_path(collection: retro.slug))
    end

    it "falls back to ?genre=<id> when the genre has no slug" do
      no_slug = Genre.create!(igdb_id: 9999, name: "Slugless")
      no_slug.update_column(:slug, nil)

      visit games_path
      shelf = find("section.shelf--genres")
      link = shelf.find(".tile-caption", text: "Slugless").find(:xpath, "..")
      expect(link[:href]).to eq(games_path(genre: no_slug.id))
    end
  end
end
