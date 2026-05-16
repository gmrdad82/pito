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
      # Phase 27 follow-up (2026-05-11) — lowercase display labels.
      # "Adventure" → "adventure"; "rpg" / "platformer" already lower.
      headings = outer.all("h3").map(&:text)
      expect(headings).to eq(%w[adventure platformer rpg])
    end

    it "skips empty genres entirely (no sub-shelf rendered for them)" do
      adventure = Genre.create!(igdb_id: 1, name: "Adventure", slug: "adventure")
      Genre.create!(igdb_id: 2, name: "Empty Genre", slug: "empty")  # zero games

      g = create(:game, :synced, title: "Zelda BotW", cover_image_id: "img-zelda")
      g.genres << adventure

      visit games_path
      outer = find("section.shelf--genres.outer-shelf")
      headings = outer.all("h3").map(&:text)
      # Phase 27 follow-up (2026-05-11) — lowercase display label.
      expect(headings).to eq([ "adventure" ])
    end
  end

  describe "Collections outer shelf (single-row tile-per-collection)" do
    it "is HIDDEN when no collection owns any game" do
      create(:collection, name: "Empty collection")  # zero games
      visit games_path
      expect(page).not_to have_css("section.shelf--collections")
      expect(page).not_to have_content("(no collections yet)")
    end

    it "renders the 'collections' <h2> and ONE tile per non-empty collection, alphabetical" do
      # Phase 27 follow-up (2026-05-11) — restructured from nested
      # sub-shelves to a single horizontal-scroll row of collection
      # tiles. Click a tile → modal lists the games (Turbo Frame).
      retro  = create(:collection, name: "Retro")
      replay = create(:collection, name: "Replay queue")

      create(:game, :synced, title: "Chrono Trigger", collection: retro)
      create(:game, :synced, title: "Hollow Knight",  collection: replay)

      visit games_path
      outer = find("section.shelf--collections.outer-shelf")
      expect(outer).to have_css("h2", text: "collections")
      tiles = outer.all(".collection-tile")
      names = tiles.map { |t| t.find(".collection-tile-name").text }
      expect(names).to eq([ "Replay queue", "Retro" ])
    end

    it "does NOT render the legacy per-collection sub-shelves on /games" do
      retro = create(:collection, name: "Retro")
      create(:game, :synced, title: "Chrono Trigger", collection: retro)
      visit games_path
      expect(page).not_to have_css('[data-shelf="collection-sub"]')
    end

    it "wires each tile to the collections-modal-trigger Stimulus controller" do
      retro = create(:collection, name: "Retro")
      create(:game, :synced, title: "Chrono Trigger", collection: retro)
      visit games_path
      tile = find(".collection-tile")
      expect(tile["data-controller"]).to include("collections-modal-trigger")
      expect(tile["data-action"]).to include("click->collections-modal-trigger#open")
      expect(tile["data-collections-modal-trigger-url-value"]).to end_with("/games_pane")
    end

    it "emits the layout-level <dialog id=\"collections-modal\"> with a Turbo Frame" do
      retro = create(:collection, name: "Retro")
      create(:game, :synced, title: "Chrono Trigger", collection: retro)
      visit games_path
      expect(page).to have_css('dialog#collections-modal', visible: false)
      expect(page).to have_css('turbo-frame#collections_modal_frame', visible: false)
    end
  end

  describe "Collections modal flow (full click chain via JS-off fallback + pane GET)" do
    # `Games::PrepareCollectionsForShelf` (composer warmup) runs on
    # the `/games` index path; 2+ games per collection triggers a
    # live IGDB CDN GET that WebMock blocks in test. Stub the
    # composer so the `visit games_path` test stays focused on the
    # collection-tile wiring rather than the CDN fetch path.
    before do
      allow(Games::PrepareCollectionsForShelf).to receive(:new).and_return(
        instance_double(Games::PrepareCollectionsForShelf, call: nil)
      )
    end

    let!(:retro)  { create(:collection, name: "Retro") }
    let!(:chrono) { create(:game, :synced, title: "Chrono Trigger", collection: retro) }
    let!(:bound)  { create(:game, :synced, title: "EarthBound",     collection: retro) }

    it "the tile's href fallback navigates to the collection show page (JS-off path)" do
      visit games_path
      tile = find(".collection-tile")
      expect(tile["href"]).to eq("/collections/#{retro.slug}")
    end

    it "the games-pane fragment lists each game with an <a> linking to its show page" do
      # The modal Turbo Frame populates via this URL; visiting it
      # directly is the rack_test-friendly equivalent of opening the
      # modal and waiting for the frame to swap in.
      visit games_pane_collection_path(retro)
      expect(page).to have_link(href: game_path(chrono))
      expect(page).to have_link(href: game_path(bound))
    end

    it "clicking a game tile from the games-pane fragment navigates to the game show page" do
      visit games_pane_collection_path(retro)
      find("a[data-tile-game-id='#{chrono.id}']").click
      expect(page).to have_current_path(game_path(chrono))
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

# Phase 27 v2 spec 07 — platform-logo tile footer system spec. ONE
# scenario seeds three games (PS5-owned, Steam+GoG-owned, Xbox-only)
# and asserts each tile's footer markup. The spec stays
# network-free — assertions cover only the rendered `<img>` markup,
# not whether the PNG bytes actually exist on disk (the Rake task's
# job).
RSpec.describe "Games index — platform-logo tile footer (v2 spec 07)", type: :system do
  before { driven_by(:rack_test) }

  let!(:platform_ps5)   { create(:platform, name: "ps5",   slug: "ps5") }
  let!(:platform_steam) { create(:platform, name: "steam", slug: "steam") }
  let!(:platform_gog)   { create(:platform, name: "gog",   slug: "gog") }
  let!(:platform_xbox)  { create(:platform, name: "Xbox One", igdb_id: 49) }

  # `:synced` stamps `external_steam_app_id`, which would force the
  # Steam logo onto every tile regardless of intent. Each game opts
  # back to a clean slate so the seeded ownerships are the sole
  # source of platform exposure on the test tiles.
  let!(:ps5_game) do
    g = create(:game, :synced,
               title: "Logo PS5 Game",
               external_steam_app_id: nil,
               igdb_id: 5_007_001, igdb_slug: "logo-ps5-game")
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end

  let!(:steam_gog_game) do
    g = create(:game, :synced,
               title: "Logo Steam GoG Game",
               external_steam_app_id: nil,
               igdb_id: 5_007_002, igdb_slug: "logo-steam-gog-game")
    g.game_platform_ownerships.create!(platform: platform_steam)
    g.game_platform_ownerships.create!(platform: platform_gog)
    g
  end

  let!(:xbox_only_game) do
    g = create(:game, :synced,
               title: "Logo Xbox Only Game",
               external_steam_app_id: nil,
               igdb_id: 5_007_003, igdb_slug: "logo-xbox-only")
    g.game_platforms.create!(platform: platform_xbox)
    g
  end

  # Scope all tile lookups to the all-games grid — the same game
  # renders in the shelves at the top of the page too, which would
  # otherwise return ambiguous Capybara matches.
  def tile_in_grid(game)
    within "section.all-games-grid" do
      find("a[data-tile-game-id='#{game.id}']")
    end
  end

  it "renders the PS5 logo on the PS5-owned tile" do
    visit games_path
    expect(tile_in_grid(ps5_game).native.to_html).to include("/platform_logos/ps5-16.png")
  end

  it "renders the Steam logo (Steam wins over GoG per KNOWN_LOGOS order) on the multi-owned tile" do
    visit games_path
    html = tile_in_grid(steam_gog_game).native.to_html
    expect(html).to include("/platform_logos/steam-16.png")
    expect(html).not_to include("/platform_logos/gog-16.png")
  end

  it "renders NO platform logo on the Xbox-only tile" do
    visit games_path
    expect(tile_in_grid(xbox_only_game).native.to_html).not_to include("/platform_logos/")
  end
end
