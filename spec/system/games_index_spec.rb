require "rails_helper"

# Phase 27 §01c-v2 — Nested Genres + Custom collections shelves on
# `/games`.
#
# Supersedes the v1 flat-tile system spec. Each outer shelf iterates
# one sub-shelf per non-empty bucket (genre / collection); empty
# buckets are hidden end-to-end. Per-sub-shelf the row holds game
# tiles at the `:shelf` cover variant (collections additionally lead
# with a composite cover tile from the 01h partial).
#
# Capybara's rack_test driver is sufficient — there is no JS in this
# surface beyond the steam-shelf wheel/drag controller, which is a
# pure UX affordance and not under test.
RSpec.describe "Games index — nested shelves (01c-v2)", type: :system do
  before { driven_by(:rack_test) }

  describe "Genres outer shelf" do
    it "is HIDDEN when no genre owns any game" do
      visit games_path
      expect(page).not_to have_css("section.shelf--genres")
      expect(page).not_to have_content("(no genres yet)")
    end

    it "renders one outer <h2> and one sub-shelf per non-empty genre, alphabetical" do
      adventure  = Genre.create!(igdb_id: 1, name: "Adventure",  slug: "adventure")
      platformer = Genre.create!(igdb_id: 2, name: "platformer", slug: "platformer")
      rpg        = Genre.create!(igdb_id: 3, name: "rpg",        slug: "rpg")

      [ [ adventure, "Zelda BotW" ], [ platformer, "Celeste" ], [ rpg, "Persona 5" ] ].each do |genre, title|
        g = create(:game, :synced, title: title, cover_image_id: "img-#{title.parameterize}")
        g.genres << genre
      end

      visit games_path
      outer = find("section.shelf--genres.outer-shelf")
      expect(outer).to have_css("h2", text: "genres")
      headings = outer.all("h3").map(&:text)
      expect(headings).to eq(%w[Adventure platformer rpg])
    end

    it "skips empty genres entirely (no sub-shelf rendered for them)" do
      adventure = Genre.create!(igdb_id: 1, name: "Adventure", slug: "adventure")
      Genre.create!(igdb_id: 2, name: "Empty Genre", slug: "empty")  # zero games

      g = create(:game, :synced, title: "Zelda BotW", cover_image_id: "img-zelda")
      g.genres << adventure

      visit games_path
      outer = find("section.shelf--genres.outer-shelf")
      headings = outer.all("h3").map(&:text)
      expect(headings).to eq([ "Adventure" ])
    end
  end

  describe "Custom collections outer shelf" do
    it "is HIDDEN when no collection owns any game" do
      create(:collection, name: "Empty collection")  # zero games
      visit games_path
      expect(page).not_to have_css("section.shelf--collections")
      expect(page).not_to have_content("(no collections yet)")
    end

    it "renders the 'custom collections' <h2> and one sub-shelf per non-empty collection, alphabetical" do
      retro  = create(:collection, name: "Retro")
      replay = create(:collection, name: "Replay queue")

      create(:game, :synced, title: "Chrono Trigger", collection: retro)
      create(:game, :synced, title: "Hollow Knight",  collection: replay)

      visit games_path
      outer = find("section.shelf--collections.outer-shelf")
      expect(outer).to have_css("h2", text: "custom collections")
      headings = outer.all("h3").map(&:text)
      expect(headings).to eq([ "Replay queue", "Retro" ])
    end
  end

  describe "Sub-shelf [see all] navigation (happy path)" do
    let!(:adventure) { Genre.create!(igdb_id: 1001, name: "Adventure", slug: "adventure") }
    let!(:rpg)       { Genre.create!(igdb_id: 1002, name: "RPG",       slug: "rpg") }

    before do
      # 31 adventure games → over the cap → [see all] visible.
      31.times do |i|
        g = create(:game, :synced, title: format("%04d adventure", i + 1))
        g.genres << adventure
      end
      g = create(:game, :synced, title: "Elden Ring", release_year: 2022)
      g.genres << rpg
    end

    it "[see all] on the adventure sub-shelf navigates to /games?genre=adventure and narrows the all-games grid" do
      visit games_path
      adventure_shelf = find("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
      adventure_shelf.click_link("see all")

      expect(page).to have_current_path(games_path(genre: "adventure"))
      # The all-games grid below narrows to adventure games — Elden
      # Ring (RPG) is filtered out.
      expect(page).not_to have_selector(".grid", text: "Elden Ring")
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
