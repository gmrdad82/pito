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

    it "renders one sub-shelf per non-empty genre, alphabetical (no outer h2 — Fix 1)" do
      adventure  = Genre.create!(igdb_id: 1, name: "Adventure",  slug: "adventure")
      platformer = Genre.create!(igdb_id: 2, name: "platformer", slug: "platformer")
      rpg        = Genre.create!(igdb_id: 3, name: "rpg",        slug: "rpg")

      [ [ adventure, "Zelda BotW" ], [ platformer, "Celeste" ], [ rpg, "Persona 5" ] ].each do |genre, title|
        g = create(:game, :synced, title: title, cover_image_id: "img-#{title.parameterize}")
        g.genres << genre
      end

      visit games_path
      outer = find("section.shelf--genres.outer-shelf")
      # 2026-05-11 polish (Fix 1) — the outer `<h2>genres</h2>` heading
      # was retired. Each sub-shelf still carries its own `<h3>`.
      expect(outer).to have_no_css("h2", text: "genres")
      # Phase 27 v2 spec 05 — display labels follow the locked
      # `GenresHelper::SHORT_NAMES` table. `Adventure` is mapped
      # one-to-one; `rpg` and `platformer` aren't IGDB canonical names
      # so they fall through unchanged.
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
      # Phase 27 v2 spec 05 — `Adventure` is the spec's one-to-one
      # mapping (canonical name preserved as the short label).
      expect(headings).to eq([ "Adventure" ])
    end
  end

  # Phase 27 v2 spec 01 — Single main genre per Game.
  #
  # Cross-cutting assertion: a multi-genre game appears under EXACTLY
  # ONE sub-shelf (the picker's alphabetical winner). When the genre
  # set changes (via picker re-run) the game hops to a new sub-shelf
  # and disappears from the old.
  describe "Single main genre per game (v2 spec 01)" do
    let!(:adventure) { Genre.create!(igdb_id: 1101, name: "Adventure", slug: "adv-v2") }
    let!(:rpg)       { Genre.create!(igdb_id: 1102, name: "RPG",       slug: "rpg-v2") }
    let!(:shooter)   { Genre.create!(igdb_id: 1103, name: "Shooter",   slug: "sho-v2") }
    let!(:game)      { create(:game, :synced, title: "Cyberpunk 2077", cover_image_id: "img-cp77") }

    before do
      # Three linked genres on a single game. The picker's
      # `LOWER(name) ASC, id ASC` tie-break makes "Adventure" the
      # alphabetical winner.
      game.genres << [ adventure, rpg, shooter ]
      # The `GameGenre.after_save :recompute_primary_genre` hook
      # already populated `primary_genre_id` — assert the precondition.
      expect(game.reload.primary_genre).to eq(adventure)
    end

    it "renders the game under EXACTLY ONE sub-shelf (the alphabetical winner)" do
      visit games_path

      # Adventure sub-shelf carries the tile.
      adv_shelf = find("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
      expect(adv_shelf.native.to_html).to include("img-cp77")

      # RPG / Shooter sub-shelves do NOT carry the tile.
      rpg_shelf = find("section.sub-shelf--genre[data-genre-id='#{rpg.id}']") rescue nil
      sho_shelf = find("section.sub-shelf--genre[data-genre-id='#{shooter.id}']") rescue nil
      # Empty buckets are hidden end-to-end — when the only game with
      # that genre is pinned elsewhere, the sub-shelf is suppressed.
      expect(rpg_shelf).to be_nil
      expect(sho_shelf).to be_nil
    end

    it "the game hops to a new sub-shelf when the picker is re-run after a genre change" do
      # Simulate a re-sync that drops Adventure and leaves only RPG +
      # Shooter. The picker chooses RPG (alphabetical winner among the
      # remaining set).
      visit games_path
      expect(page).to have_css("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")

      # Remove the Adventure link; re-run the picker explicitly (as
      # `Igdb::SyncGame#re_assign_primary_genre` would).
      game.game_genres.where(genre_id: adventure.id).destroy_all
      game.update_column(:primary_genre_id, nil)
      new_pick = Games::PrimaryGenrePicker.new.pick(game.reload)
      game.update_column(:primary_genre_id, new_pick&.id)
      expect(game.reload.primary_genre).to eq(rpg)

      # Refresh.
      visit games_path

      # The game is now under RPG, NOT under Adventure (Adventure has
      # zero games now → sub-shelf hidden).
      rpg_shelf = find("section.sub-shelf--genre[data-genre-id='#{rpg.id}']")
      expect(rpg_shelf.native.to_html).to include("img-cp77")
      expect(page).not_to have_css("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
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

    it "[see all] on the adventure sub-shelf navigates to /games?genre=adventure and narrows the letter shelves" do
      visit games_path
      adventure_shelf = find("section.sub-shelf--genre[data-genre-id='#{adventure.id}']")
      adventure_shelf.click_link("see all")

      expect(page).to have_current_path(games_path(genre: "adventure"))
      # Phase 27 v2 spec 05 — the all-games partition retired. The
      # letter shelves wrapper narrows to adventure-only games; Elden
      # Ring (RPG) is filtered out.
      listing = find("section.all-games-shelves-by-letter")
      expect(listing).not_to have_content("Elden Ring")
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

  # Phase 27 v2 spec 05 — the legacy `section.all-games-grid` partition
  # retired with the display-mode switcher. The new layout's letter
  # shelves render games inside `section.all-games-shelves-by-letter`
  # (the per-letter `<section class="shelf shelf--letter">` rows live
  # inside that wrapper). Tiles render via `Games::CoverComponent`
  # which emits only `<img>` (no visible title text); assertions use
  # the `data-tile-game-id` data attribute to identify games. When
  # the filter empties `@letter_buckets`, the wrapper is suppressed
  # entirely (no muted `"no games match"` copy carries over).
  describe "chip toggle navigation" do
    def listing_has_game?(game)
      page.has_css?("section.all-games-shelves-by-letter [data-tile-game-id='#{game.id}']")
    end

    def listing_has_no_game?(game)
      page.has_no_css?("section.all-games-shelves-by-letter [data-tile-game-id='#{game.id}']")
    end

    it "clicking [ps5] updates the URL and narrows the listing" do
      visit games_path
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      expect(page).to have_current_path(games_path(filters: "ps5"))
      expect(listing_has_game?(owned_ps5)).to be(true)
      expect(listing_has_game?(another_owned_ps5)).to be(true)
      expect(listing_has_no_game?(unowned_steam)).to be(true)
    end

    it "clicking [ps5] when already active clears it" do
      visit games_path(filters: "ps5")
      within "section.games-filter-row" do
        find("a[data-filter-token='ps5']").click
      end
      # Toggling off the only active chip drops `filters=` entirely.
      expect(page).to have_current_path(games_path)
      expect(listing_has_game?(unowned_steam)).to be(true)
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
      expect(listing_has_game?(owned_ps5)).to be(true)
      expect(listing_has_game?(another_owned_ps5)).to be(true)
      expect(listing_has_no_game?(unowned_steam)).to be(true)
    end
  end

  describe "sad: contradiction" do
    it "clicking [owned] then [not owned] renders the contradiction notice + suppresses the listing" do
      visit games_path
      within "section.games-filter-row" do
        find("a[data-filter-token='owned']").click
      end
      within "section.games-filter-row" do
        find("a[data-filter-token='not_owned']").click
      end
      expect(page).to have_content("owned and not owned together — no matches")
      # Phase 27 v2 spec 05 — the contradiction empties `@letter_buckets`,
      # so the entire letter-shelves wrapper is suppressed (no muted
      # "no games match this filter." copy carries over).
      expect(page).to have_no_css("section.all-games-shelves-by-letter")
    end
  end

  describe "edge: query param preservation" do
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
      # owned_ps5 + another_owned_ps5 + unowned_steam are all on at
      # least one canonical platform.
      [ owned_ps5, another_owned_ps5, unowned_steam ].each do |g|
        expect(page).to have_css("section.all-games-shelves-by-letter [data-tile-game-id='#{g.id}']")
      end
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
