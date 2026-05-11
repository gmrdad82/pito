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

# Phase 27 §01b — Filter row system spec. Additive; the existing
# 01c describe block above is preserved verbatim.
RSpec.describe "Games index — filter row (01b)", type: :system do
  before { driven_by(:rack_test) }

  let!(:platform_ps5)     { create(:platform, name: "ps5",     slug: "ps5") }
  let!(:platform_switch2) { create(:platform, name: "switch2", slug: "switch2") }
  let!(:platform_steam)   { create(:platform, name: "steam",   slug: "steam") }

  let!(:owned_ps5) do
    g = create(:game, title: "Owned PS5 Game", release_date: 1.year.ago)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end
  let!(:unowned_steam) do
    g = create(:game, title: "Steam Only Game", release_date: 1.year.ago)
    g.game_platforms.create!(platform: platform_steam)
    g
  end
  let!(:another_owned_ps5) do
    g = create(:game, title: "Other PS5 Game", release_date: 1.year.ago)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end

  describe "chip toggle navigation" do
    it "clicking [ps5] updates the URL and narrows the listing" do
      visit games_path
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      expect(page).to have_current_path(games_path(filters: "ps5"))
      grid = find("section.all-games-grid")
      expect(grid).to have_content("Owned PS5 Game")
      expect(grid).to have_content("Other PS5 Game")
      expect(grid).not_to have_content("Steam Only Game")
    end

    it "clicking [ps5] when already active clears it" do
      visit games_path(filters: "ps5")
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      # Toggling off the only active chip drops `filters=` entirely.
      expect(page).to have_current_path(games_path)
      grid = find("section.all-games-grid")
      expect(grid).to have_content("Steam Only Game")
    end

    it "[clear all] appears when at least one chip is active" do
      visit games_path
      expect(page).not_to have_link("clear all")
      visit games_path(filters: "ps5")
      expect(page).to have_link("clear all")
    end

    it "[clear all] clears the filter set" do
      visit games_path(filters: "ps5,owned")
      click_link "clear all"
      expect(page).to have_current_path(games_path)
      expect(page).not_to have_link("clear all")
    end

    it "composing chips: [ps5] then [owned] narrows to owned-on-ps5" do
      visit games_path
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      within "section.games-filter-row" do
        find("a[data-filter-token='owned']").click
      end
      grid = find("section.all-games-grid")
      expect(grid).to have_content("Owned PS5 Game")
      expect(grid).to have_content("Other PS5 Game")
      expect(grid).not_to have_content("Steam Only Game")
    end
  end

  describe "sad: contradiction" do
    it "clicking [owned] then [not owned] renders the contradiction notice" do
      visit games_path
      within "section.games-filter-row" do
        find("a[data-filter-token='owned']").click
      end
      within "section.games-filter-row" do
        find("a[data-filter-token='not_owned']").click
      end
      expect(page).to have_content("owned and not owned together — no matches")
      grid = find("section.all-games-grid")
      expect(grid).to have_content("no games match this filter.")
    end
  end

  describe "edge: query param preservation" do
    it "preserves ?display=list when toggling a chip" do
      visit games_path(display: "list")
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      # Both keys must be present; order is not asserted.
      expect(current_url).to include("filters=ps5")
      expect(current_url).to include("display=list")
    end

    it "preserves ?genre=<slug> when toggling a chip" do
      action = Genre.create!(igdb_id: 8001, name: "Action", slug: "action")
      owned_ps5.genres << action
      visit games_path(genre: "action")
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      expect(current_url).to include("filters=ps5")
      expect(current_url).to include("genre=action")
    end

    it "selecting all five platform chips without owned widens to the union" do
      visit games_path
      %w[ps5 switch2 steam gog epic].each do |t|
        within "section.games-filter-row" do
          find("a[data-filter-token='#{t}']").click
        end
      end
      grid = find("section.all-games-grid")
      # owned_ps5 + another_owned_ps5 + unowned_steam are all on at
      # least one canonical platform.
      expect(grid).to have_content("Owned PS5 Game")
      expect(grid).to have_content("Other PS5 Game")
      expect(grid).to have_content("Steam Only Game")
    end
  end

  describe "flaw: defensive surface" do
    it "the filter row contains no <script> tag" do
      visit games_path(filters: "ps5")
      row = find("section.games-filter-row")
      expect(row.native.to_html).not_to include("<script")
    end

    it "no data-turbo-confirm anywhere on the row" do
      visit games_path(filters: "ps5")
      row = find("section.games-filter-row")
      expect(row.native.to_html).not_to include("data-turbo-confirm")
    end
  end
end
