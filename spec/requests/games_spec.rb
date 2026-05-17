require "rails_helper"
require "ostruct"

RSpec.describe "Games", type: :request do
  describe "GET /games" do
    # Phase 14 §3 — Steam-shelf rewrite. The flat sortable table was
    # replaced with shelf rows + a wrapping all-games grid.
    it "returns 200" do
      get games_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the empty-state copy when no rows exist" do
      get games_path
      expect(response.body).to include("no games yet.")
      # Phase 14 §1 polish (2026-05-10) — inline `_add_form` retired in
      # favor of `[+]` next to the H1 + the layout-level IGDB modal.
      expect(response.body).to include("igdb")
    end

    it "does not render a [search igdb] chip on the add form" do
      get games_path
      expect(response.body).not_to include("[search igdb]")
    end

    # Phase 14 §1 polish (2026-05-10) — `[+]` next to the H1 opens the
    # layout-level IGDB-search modal via the existing `modal-trigger`
    # Stimulus controller.
    it "renders a [+] bracketed link wired to the IGDB-search modal" do
      get games_path
      expect(response.body).to match(/\[<span class="bl">\+<\/span>\]/)
      expect(response.body).to include('data-modal-trigger-target-id-value="igdb-search-modal"')
    end

    it "does NOT render the retired inline igdb-search type-ahead form" do
      get games_path
      # The old `_add_form` partial mounted the `igdb-search` controller
      # and a sibling `<turbo-frame>` of its own. The frame now lives
      # only inside the layout's IGDB modal; the page-level controller
      # is gone.
      expect(response.body).not_to include('data-controller="igdb-search"')
    end

    context "with a populated library" do
      let!(:zelda) do
        create(:game, :synced, title: "Zelda BotW", igdb_id: 7346,
               release_year: 2017, igdb_rating: 95.0,
               played_at: 2.weeks.ago)
      end

      it "links a tile to the game show page" do
        get games_path
        expect(response.body).to include(%(href="#{game_path(zelda)}"))
        expect(response.body).to include("Zelda BotW")
      end

      it "renders the recently-played shelf when at least one game has played_at" do
        get games_path
        expect(response.body).to include(">recently played<")
      end

      it "does NOT render the recently-played shelf when no game has played_at" do
        zelda.update_column(:played_at, nil)
        get games_path
        expect(response.body).not_to include(">recently played<")
      end

      it "renders the bundles shelf when at least one bundle exists" do
        create(:bundle, name: "Soulslikes")
        get games_path
        expect(response.body).to include(">bundles<")
      end

      it "does NOT render the bundles shelf when no bundle exists" do
        get games_path
        # The `bundles` shelf-heading would appear inside the [see all] /
        # heading region — its absence is expected on a no-bundle install.
        expect(response.body.scan(">bundles<").length).to eq(0)
      end

      # Phase 27 v2 spec 05 — the `<h2>all</h2>` heading and the per-mode
      # partition section (`data-display-mode=...`) are gone. The new
      # layout is a single stack of shelves: filter row → bundles →
      # recently-played → genres → collections → per-letter shelves.
      it "does NOT render an `<h2>all</h2>` heading (display modes retired)" do
        get games_path
        expect(response.body).not_to match(%r{<h2[^>]*>\s*all\s*</h2>})
      end

      it "does NOT stamp any `data-display-mode=` attribute" do
        get games_path
        expect(response.body).not_to include("data-display-mode=")
      end

      it "renders the filter row ABOVE the per-letter shelves block (v2 spec 05)" do
        get games_path
        filter_row_pos = response.body.index('class="games-filter-row')
        letters_pos    = response.body.index('class="all-games-shelves-by-letter')
        expect(filter_row_pos).not_to be_nil
        expect(letters_pos).not_to be_nil
        expect(filter_row_pos).to be < letters_pos
      end

      it "stamps a steam-shelf Stimulus controller on each shelf" do
        get games_path
        expect(response.body).to include('data-controller="steam-shelf"')
      end

      it "renders one nested genre sub-shelf per genre that owns a game" do
        # Phase 27 v2 spec 05 — the helper now returns the spec's
        # locked short label. `Adventure` maps to `Adventure` (one-to-
        # one). The sub-shelf still carries the `data-shelf="genre-sub"`
        # hook.
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.genres << genre
        get games_path
        expect(response.body).to include('data-shelf="genre-sub"')
        expect(response.body).to match(%r{<h3[^>]*>\s*Adventure\s*</h3>})
      end

      it "renders exactly one `<h3>Adventure</h3>` heading (no duplicate per-genre row)" do
        # Phase 27 polish (2026-05-11) — the legacy duplicate iteration
        # is gone. Phase 27 v2 spec 05 — the all-games partition itself
        # is gone too. Only one render of each genre name should appear
        # in the page (the 01c-v2 nested sub-shelf <h3>).
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.genres << genre
        get games_path
        expect(response.body.scan(%r{<h3[^>]*>\s*Adventure\s*</h3>}).length).to eq(1)
      end
    end

    # P27 reviewer follow-up (non-blocking concern #2, 2026-05-11) —
    # the per-genre sub-shelves used to fire `genre.games.count` plus
    # `genre.games.order(...).limit(30)` per genre (2 queries per
    # genre). `Games::GenreShelfBatch` now resolves both with a
    # grouped count + windowed top-N fetch (2 queries total regardless
    # of genre count). The assertion below counts SELECT statements
    # via `ActiveSupport::Notifications` and asserts the count stays
    # flat as the number of genres grows.
    describe "N+1 guard on per-genre sub-shelves" do
      def count_select_statements
        select_count = 0
        callback = lambda do |_name, _start, _finish, _id, payload|
          next if payload[:name] == "SCHEMA"
          next if payload[:cached]
          sql = payload[:sql].to_s
          select_count += 1 if sql.match?(/\ASELECT/i)
        end
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
        select_count
      end

      let!(:adv)   { Genre.create!(igdb_id: 9_001, name: "Adventure", slug: "adventure") }
      let!(:rpg)   { Genre.create!(igdb_id: 9_002, name: "RPG",       slug: "rpg") }
      let!(:plat)  { Genre.create!(igdb_id: 9_003, name: "Platformer", slug: "platformer") }

      before do
        # One primary-genre-pinned game per genre keeps each
        # sub-shelf non-empty (the outer shelf hides empty buckets).
        [ adv, rpg, plat ].each_with_index do |g, i|
          game = create(:game, :synced, title: "Game-#{i}-#{g.name}", cover_image_id: "img-#{i}")
          game.update_column(:primary_genre_id, g.id)
        end
      end

      it "issues a bounded number of SELECTs across 3 sub-shelves (no N+1)" do
        # First request warms caches / loads code; the second is the
        # measurement. We assert a generous ceiling (50) because the
        # render pipeline issues legitimate SELECTs beyond the
        # sub-shelves (auth, AppSetting, layout fragments, etc.). The
        # specific N+1 we eliminated was `2 * genres`, so the ceiling
        # is set well below `baseline + 2 * 3` for a 3-genre fixture.
        get games_path
        baseline = count_select_statements { get games_path }
        expect(baseline).to be < 50
      end

      it "the SELECT count stays flat when the genre count grows from 3 to 6" do
        # Warm.
        get games_path
        small = count_select_statements { get games_path }

        # Add 3 more populated genres.
        3.times do |i|
          extra_genre = Genre.create!(igdb_id: 9_100 + i, name: "Extra-#{i}", slug: "extra-#{i}")
          game = create(:game, :synced, title: "Game-extra-#{i}", cover_image_id: "img-extra-#{i}")
          game.update_column(:primary_genre_id, extra_genre.id)
        end

        large = count_select_statements { get games_path }
        # The N+1 fix means doubling the genre count adds a single
        # extra SELECT at most (the grouped count + windowed fetch are
        # each one query regardless of N). A regression to the old
        # `2 * N` pattern would add 6 extra SELECTs (2 per new genre).
        # We assert the delta stays under 5 to leave a small buffer
        # for incidental query growth from new fixture rows.
        expect(large - small).to be < 5
      end
    end

    describe "filter routes" do
      let!(:zelda)   { create(:game, :synced, title: "Zelda", release_year: 2017) }
      let!(:elden)   { create(:game, :synced, title: "Elden Ring", release_year: 2022) }
      let(:adventure) { Genre.create!(igdb_id: 1001, name: "Adventure") }
      let(:rpg)       { Genre.create!(igdb_id: 1002, name: "RPG") }

      before do
        zelda.genres << adventure
        elden.genres << rpg
      end

      it "filters /games?genre=<id> to that genre's games" do
        get games_path, params: { genre: adventure.id }
        expect(response.body).to include("Zelda")
        expect(response.body).not_to include(">Elden Ring<")
      end

      it "drops invalid genre ids silently (no filter applied)" do
        get games_path, params: { genre: "evil; DROP TABLE games" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Zelda")
        expect(response.body).to include("Elden Ring")
      end
    end

    # Phase 27 follow-up (2026-05-11) — composer wiring assertion.
    # The P27 reviewer flagged `Collections::CoverComposer` as built
    # but never invoked. `GamesController#index` now calls
    # `Games::PrepareCollectionsForShelf` which delegates to the
    # composer for every collection slated for the outer shelf.
    describe "composite-cover warm-up wiring" do
      it "invokes `Collections::CoverComposer#call` for each non-empty collection" do
        coll = create(:collection, name: "two games")
        create(:game, :synced, title: "alpha", cover_image_id: "img-a", collection: coll)
        create(:game, :synced, title: "beta",  cover_image_id: "img-b", collection: coll)

        expect_any_instance_of(Collections::CoverComposer)
          .to receive(:call).with(have_attributes(id: coll.id)).at_least(:once)

        get games_path
        expect(response).to have_http_status(:ok)
      end
    end

    # Phase 27 §01c-v2 — Nested Genres + Custom collections shelves.
    # Outer shelf iterates one sub-shelf per non-empty bucket; empty
    # buckets are HIDDEN end-to-end (no muted placeholder, no `<h2>`).
    describe "Phase 27 §01c-v2 — nested top-of-page shelves" do
      it "HIDES the Genres outer shelf entirely when no genre owns any game" do
        get games_path
        expect(response.body).not_to include("outer-shelf")
        expect(response.body).not_to include("(no genres yet)")
        expect(response.body).not_to match(%r{<section[^>]*shelf--genres[^>]*outer-shelf})
      end

      it "HIDES the Custom collections outer shelf entirely when no collection owns any game" do
        create(:collection, name: "Empty bin")  # zero games
        get games_path
        expect(response.body).not_to include("(no collections yet)")
        expect(response.body).not_to match(%r{<section[^>]*shelf--collections[^>]*outer-shelf})
      end

      it "renders the genres outer shelf (Phase 27 v2 spec 05)" do
        # Phase 27 v2 spec 05 — hairlines now lead each major section
        # (genres / collections / letter shelves), not just the gap
        # between two specific shelves. The genres outer shelf still
        # renders when at least one genre owns a game.
        adventure = Genre.create!(igdb_id: 50, name: "Adventure", slug: "adventure")
        g = create(:game, :synced, title: "Tunic", cover_image_id: "img-tunic")
        g.genres << adventure
        get games_path
        expect(response.body).to include('data-shelf="outer-genres"')
      end

      context "with non-empty genres and collections" do
        let!(:adventure)  { Genre.create!(igdb_id: 1, name: "Adventure",  slug: "adventure") }
        let!(:rpg)        { Genre.create!(igdb_id: 2, name: "rpg",        slug: "rpg") }
        let!(:platformer) { Genre.create!(igdb_id: 3, name: "platformer", slug: "platformer") }
        let!(:retro)      { create(:collection, name: "Retro") }
        let!(:replay)     { create(:collection, name: "Replay queue") }

        before do
          zelda = create(:game, :synced, title: "Zelda BotW", cover_image_id: "img-zelda", collection: retro)
          zelda.genres << adventure
          persona = create(:game, :synced, title: "Persona 5", cover_image_id: "img-persona", collection: replay)
          persona.genres << rpg
          celeste = create(:game, :synced, title: "Celeste", cover_image_id: "img-celeste")
          celeste.genres << platformer
        end

        it "renders the Genres outer-shelf <section> without an outer <h2> (Fix 1, 2026-05-11)" do
          # 2026-05-11 polish (Fix 1) — the outer `<h2>genres</h2>`
          # heading was retired. The outer `<section>` still wraps the
          # iteration so the sub-shelf CSS hairline scope keeps working;
          # each sub-shelf carries its own `<h3>` heading.
          get games_path
          expect(response.body).to include('data-shelf="outer-genres"')
          expect(response.body).not_to match(%r{<h2[^>]*>\s*genres\s*</h2>})
        end

        it "renders a hairline BEFORE each of the genres + collections + letter shelves (Phase 27 v2 spec 05)" do
          get games_path
          # Phase 27 v2 spec 05 — hairlines lead each major section.
          # The genres outer shelf, collections outer shelf, and the
          # letter shelves block each get a leading `<hr>`.
          expect(response.body.scan('<hr class="hairline">').length).to be >= 2

          genres_pos     = response.body.index('data-shelf="outer-genres"')
          colls_pos      = response.body.index('data-shelf="outer-collections"')
          first_hairline = response.body.index('<hr class="hairline">')

          # The first hairline appears before the genres shelf — they
          # both follow the filter row.
          expect(first_hairline).not_to be_nil
          expect(genres_pos).not_to be_nil
          expect(first_hairline).to be < genres_pos

          # Genres come before collections.
          expect(genres_pos).to be < colls_pos
        end

        it "renders the Collections outer-shelf with the 'collections' <h2>" do
          # Phase 27 follow-up (2026-05-11) — renamed from
          # "custom collections" to plain "collections".
          get games_path
          expect(response.body).to include('data-shelf="outer-collections"')
          expect(response.body).to match(%r{<h2[^>]*>\s*collections\s*</h2>})
          expect(response.body).not_to match(%r{<h2[^>]*>\s*custom collections\s*</h2>})
        end

        it "renders one sub-shelf per non-empty genre, alphabetical" do
          get games_path
          genres_section = response.body[/<section[^>]*shelf--genres[^>]*outer-shelf.*?<\/section>\s*\z/m] ||
                           response.body[/<section[^>]*shelf--genres[^>]*outer-shelf[\s\S]*/]
          expect(genres_section).not_to be_nil
          # Phase 27 v2 spec 05 — display labels follow the locked
          # `GenresHelper::SHORT_NAMES` table. `Adventure` is mapped
          # one-to-one, `rpg` and `platformer` aren't in the IGDB
          # canonical key set so they fall through unchanged. SQL
          # ordering is `LOWER(genres.name)` so the canonical
          # mixed-case names still sort alphabetically.
          order_indexes = [ "Adventure", "platformer", "rpg" ].map { |n| genres_section.index(">#{n}<") }
          expect(order_indexes).to eq(order_indexes.sort)
        end

        it "renders one collection tile per non-empty collection, alphabetical" do
          # Phase 27 follow-up (2026-05-11) — collections restructured
          # from sub-shelves into a single row of tile-per-collection.
          get games_path
          colls_section = response.body[/<section[^>]*shelf--collections[^>]*outer-shelf[\s\S]*/]
          expect(colls_section).not_to be_nil
          order_indexes = [ "Replay queue", "Retro" ].map { |n| colls_section.index(">#{n}<") }
          expect(order_indexes).to eq(order_indexes.sort)
        end

        it "stamps `data-shelf=\"genre-sub\"` on each genre sub-shelf wrapper" do
          get games_path
          expect(response.body.scan('data-shelf="genre-sub"').length).to eq(3)
        end

        it "renders one `.collection-tile` anchor per collection" do
          get games_path
          expect(response.body.scan('class="collection-tile"').length).to eq(2)
        end

        it "stamps the steam-shelf Stimulus controller on each shelf row" do
          get games_path
          # 3 genre sub-shelves + 1 collections row + legacy Phase 14
          # shelves (per-genre, all-games) also stamp the controller, so
          # we assert a floor not an exact count.
          expect(response.body.scan('data-controller="steam-shelf"').length).to be >= 4
        end
      end

      describe "[see all] cap behavior" do
        let!(:adventure) { Genre.create!(igdb_id: 1, name: "Adventure", slug: "adventure") }

        it "omits `[see all]` when a genre sub-shelf is under the 30 cap" do
          g = create(:game, :synced, title: "Tunic")
          g.genres << adventure
          get games_path
          # The legacy Phase 14 per-genre shelf does emit a [see all]
          # link, so we scope this assertion to the v2 sub-shelf only.
          genre_sub = response.body[%r{<section[^>]*sub-shelf--genre[^>]*data-genre-id="#{adventure.id}"[\s\S]*?</section>}]
          expect(genre_sub).not_to be_nil
          expect(genre_sub).not_to include(">see all<")
        end

        it "renders `[see all]` when a genre sub-shelf exceeds the 30 cap" do
          31.times do |i|
            g = create(:game, :synced, title: format("%04d game", i + 1))
            g.genres << adventure
          end
          get games_path
          genre_sub = response.body[%r{<section[^>]*sub-shelf--genre[^>]*data-genre-id="#{adventure.id}"[\s\S]*?</section>}]
          expect(genre_sub).not_to be_nil
          expect(genre_sub).to include(">see all<")
          expect(genre_sub).to include('href="' + games_path(genre: "adventure") + '"')
        end
      end
    end

    # Phase 27 §01c — slug-based filter contract for both `?genre`
    # and `?collection`. The integer-id form keeps working (asserted
    # in the "filter routes" describe above); these specs cover the
    # slug form the new shelf tiles emit.
    describe "Phase 27 §01c — slug filter routes" do
      let!(:zelda)    { create(:game, :synced, title: "Zelda",      release_year: 2017) }
      let!(:elden)    { create(:game, :synced, title: "Elden Ring", release_year: 2022) }
      let(:adventure) { Genre.create!(igdb_id: 1001, name: "Adventure", slug: "adventure") }
      let(:rpg)       { Genre.create!(igdb_id: 1002, name: "RPG",       slug: "rpg") }

      before do
        zelda.genres << adventure
        elden.genres << rpg
      end

      it "filters /games?genre=<slug> to that genre's games" do
        get games_path, params: { genre: "adventure" }
        expect(response.body).to include("Zelda")
        expect(response.body).not_to include(">Elden Ring<")
      end

      it "drops an unknown genre slug silently (no filter applied)" do
        get games_path, params: { genre: "nonexistent" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Zelda")
        expect(response.body).to include("Elden Ring")
      end

      it "filters /games?collection=<slug> to games in that collection" do
        retro = create(:collection, name: "Retro")
        zelda.update!(collection: retro)

        get games_path, params: { collection: retro.slug }
        expect(response.body).to include("Zelda")
        expect(response.body).not_to include(">Elden Ring<")
      end

      it "drops an unknown collection slug silently (no filter applied)" do
        get games_path, params: { collection: "nope-no-collection" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Zelda")
        expect(response.body).to include("Elden Ring")
      end
    end
  end

  describe "GET /games/search" do
    let(:search_payload) { [ { "id" => 7346, "name" => "Zelda BotW", "slug" => "zelda-botw", "first_release_date" => 1488499200 } ] }

    before do
      allow(Rails.application.credentials).to receive(:igdb).and_return(
        OpenStruct.new(client_id: "id", client_secret: "secret")
      )
    end

    it "returns 200 with results when q is present" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: search_payload.to_json)

      get search_games_path, params: { q: "zelda" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Zelda BotW")
    end

    it "renders an empty-state when the query is blank" do
      get search_games_path, params: { q: "" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("type to search igdb")
    end

    it "truncates a query longer than 100 chars" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")

      get search_games_path, params: { q: "x" * 200 }
      expect(response).to have_http_status(:ok)
    end

    it "renders a 'no results' message on empty IGDB response" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")

      get search_games_path, params: { q: "xyznonexistent" }
      expect(response.body).to include("no results for 'xyznonexistent'")
    end

    # Phase 14 §1 polish (2026-05-10) — IGDB result rows differentiate
    # between "not in library" (renders `[add]` button posting to
    # /games) and "already in library" (renders `[update]` link wired
    # to the overwrite-confirmation modal).
    context "when an IGDB hit already maps to a local Game" do
      before do
        create(:game, :synced, igdb_id: 7346, title: "Zelda BotW")
        stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
          .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: search_payload.to_json)
      end

      it "renders [update] (NOT [add]) for that row" do
        get search_games_path, params: { q: "zelda" }
        expect(response.body).to match(/\[<span class="bl">update<\/span>\]/)
        expect(response.body).not_to match(/\[<span class="bl">add<\/span>\]/)
      end

      it "wires [update] to the overwrite-confirmation trigger" do
        get search_games_path, params: { q: "zelda" }
        expect(response.body).to include('data-controller="igdb-overwrite-trigger"')
        local_game = Game.find_by(igdb_id: 7346)
        expect(response.body).to include(%(data-igdb-overwrite-trigger-path-value="#{resync_game_path(local_game)}"))
      end
    end

    context "when an IGDB hit is NOT in the library" do
      before do
        stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
          .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: search_payload.to_json)
      end

      it "renders [add] (NOT [update]) for that row" do
        get search_games_path, params: { q: "zelda" }
        expect(response.body).to match(/\[<span class="bl">add<\/span>\]/)
        expect(response.body).not_to match(/\[<span class="bl">update<\/span>\]/)
      end
    end
  end

  describe "GET /games/:id" do
    let!(:game) { create(:game, :synced, title: "Zelda BotW") }

    it "renders 200" do
      get game_path(game)
      expect(response).to have_http_status(:ok)
    end

    # Phase 14 §1 polish (2026-05-10) — show page now uses the canonical
    # `.pane-row > .pane` two-pane layout (mirrors channels/videos).
    # Layout revamp (2026-05-10) — left pane carries `pane--narrow`
    # (280px, hugs the cover) and the row-1 right pane carries
    # `pane--game-detail` (640px, mid-size — bigger than the default
    # 452px, smaller than the 904px wide pane — so the cover + details
    # fit on one row at standard workspace width). Rows 2 (sync) and 3
    # (linked videos) still use `pane--wide`. The pane-count assertion
    # below tolerates either modifier by matching `class="pane ..."` or
    # `class="pane"` — both forms are valid `.pane` elements.
    it "renders inside a `.pane-row` of `.pane` children" do
      get game_path(game)
      expect(response.body).to include("pane-row")
      pane_open_tags = response.body.scan(/class="pane(?:\s[^"]*)?"/).size
      expect(pane_open_tags).to be >= 2
    end

    # Layout revamp (2026-05-10) — assert the narrow + game-detail + wide
    # modifiers actually land in the rendered markup so the column
    # proportions don't silently revert. The row-1 right pane uses the
    # new mid-size `pane--game-detail` (640px); the sync and linked
    # videos panes on subsequent rows keep `pane--wide`.
    it "uses the narrow + game-detail + wide pane modifiers" do
      get game_path(game)
      expect(response.body).to include("pane pane--narrow")
      expect(response.body).to include("pane pane--game-detail")
      expect(response.body).to include("pane pane--wide")
    end

    # Layout fix (2026-05-10) — row 1 (cover + details) was observed
    # stacking instead of rendering side-by-side. The page-specific
    # `pane-row--game-show` modifier flips that row to `flex-wrap:
    # nowrap` so the two panes stay on the same horizontal line at
    # workspace widths; narrower viewports get horizontal scroll instead
    # of a stacked column. Assert the modifier is rendered so the fix
    # doesn't silently regress.
    it "marks row 1 with `pane-row--game-show` to prevent wrap" do
      get game_path(game)
      expect(response.body).to include("pane-row pane-row--game-show")
    end

    it "splits the re-sync caveat onto two lines via <br>" do
      get game_path(game)
      expect(response.body).to include("re-syncing overwrites igdb-sourced fields.<br>")
    end

    # Phase 14 §1 polish (2026-05-10) — show / edit split.
    it "exposes [edit] in the breadcrumb action strip" do
      get game_path(game)
      expect(response.body).to include(edit_game_path(game))
    end

    it "does NOT carry the inline form (moved to /edit)" do
      get game_path(game)
      # The form's submit was `[update]` and the textarea was for notes.
      expect(response.body).not_to include('name="game[notes]"')
    end

    it "does NOT show [open on igdb] (retired)" do
      get game_path(game)
      expect(response.body).not_to include("open on igdb")
    end

    context "when resync is in flight" do
      before { game.update_column(:resyncing, true) }

      it "renders the sync-indicator instead of the [resync] button" do
        get game_path(game)
        expect(response.body).to include('data-controller="sync-indicator"')
        expect(response.body).to include('data-sync-indicator-frames-value=')
        # The [resync] button goes away while the indicator is mounted.
        expect(response.body).not_to match(/<span class="bl">resync<\/span>/)
      end

      it "stamps an auto-refresh polling controller while resyncing" do
        get game_path(game)
        expect(response.body).to include('data-controller="auto-refresh"')
      end
    end

    context "when resync is NOT in flight" do
      it "renders the [resync] button (igdb_id present)" do
        get game_path(game)
        expect(response.body).to include('<span class="bl">resync</span>')
      end

      it "does NOT stamp the auto-refresh controller" do
        get game_path(game)
        expect(response.body).not_to include('data-controller="auto-refresh"')
      end
    end

    # Phase 27 v2 spec 01 — single main genre per Game.
    describe "Phase 27 v2 spec 01 — single-genre rendering" do
      it "renders `genre:` (singular) label and the primary genre's name" do
        genre = create(:genre, name: "Adventure", igdb_id: 6_201)
        game.genres << genre
        game.update_column(:primary_genre_id, genre.id)
        get game_path(game)
        expect(response.body).to include(">genre:</span>")
        expect(response.body).to include("Adventure")
      end

      it "renders `—` when the game has no primary genre" do
        game.update_column(:primary_genre_id, nil)
        get game_path(game)
        # The dash is rendered in the same `<p>` block as the label.
        expect(response.body).to match(%r{>genre:</span>\s*—})
      end

      it "does NOT render the legacy comma-joined `genres:` label" do
        get game_path(game)
        expect(response.body).not_to match(%r{>genres:</span>})
      end

      it "does NOT render every linked genre — only the primary" do
        primary   = create(:genre, name: "Adventure",       igdb_id: 6_211)
        secondary = create(:genre, name: "Hidden Genre Z",  igdb_id: 6_212)
        game.genres << [ primary, secondary ]
        game.update_column(:primary_genre_id, primary.id)
        get game_path(game)
        expect(response.body).to include("Adventure")
        expect(response.body).not_to include("Hidden Genre Z")
      end
    end
  end

  # Phase 27 v2 spec 01 — JSON shape contract for `GET /games/:id.json`.
  describe "GET /games/:id.json (Phase 27 v2 spec 01 — single genre)" do
    let!(:game) { create(:game, :synced, title: "Zelda BotW JSON") }

    it "returns `genre` as a singular string when the primary is set" do
      genre = create(:genre, name: "Adventure", igdb_id: 6_301)
      game.genres << genre
      game.update_column(:primary_genre_id, genre.id)
      get game_path(game, format: :json)
      payload = JSON.parse(response.body)
      expect(payload["game"]["genre"]).to eq("Adventure")
    end

    it "returns `genre: null` when the primary is nil" do
      game.update_column(:primary_genre_id, nil)
      get game_path(game, format: :json)
      payload = JSON.parse(response.body)
      expect(payload["game"]).to have_key("genre")
      expect(payload["game"]["genre"]).to be_nil
    end

    it "does NOT include the legacy multi-genre `genres` key" do
      get game_path(game, format: :json)
      payload = JSON.parse(response.body)
      expect(payload["game"]).not_to have_key("genres")
    end

    it "404s on a garbage id (sad path)" do
      # `Game.friendly.find` raises `ActiveRecord::RecordNotFound`
      # which Rails translates to 404 in request specs unless a
      # custom rescue is registered. Match either response: 404 or
      # the raise — both prove the controller refuses to serve a
      # JSON detail for an unknown slug.
      begin
        get game_path("no-such-game-12345", format: :json)
        expect(response).to have_http_status(:not_found)
      rescue ActiveRecord::RecordNotFound
        # Acceptable — the request spec layer surfaces the raise.
        expect(true).to be(true)
      end
    end
  end

  describe "GET /games/:id/edit" do
    let!(:game) { create(:game, :synced, title: "Zelda BotW") }

    it "renders 200" do
      get edit_game_path(game)
      expect(response).to have_http_status(:ok)
    end

    it "carries the local-fields form" do
      get edit_game_path(game)
      expect(response.body).to include('name="game[notes]"')
      expect(response.body).to include('name="game[played_at]"')
      expect(response.body).to include('name="game[hours_of_footage_manual]"')
    end

    # Phase 27 §1a — per-platform ownership moves out of the edit form
    # into its own dedicated editor (lands in `01f`). The edit page
    # must NOT carry a `platform_owned_id` input.
    it "does NOT render a platform_owned_id input" do
      get edit_game_path(game)
      expect(response.body).not_to include('name="game[platform_owned_id]"')
    end

    it "renders [update] and [cancel] actions" do
      get edit_game_path(game)
      expect(response.body).to include("update")
      expect(response.body).to include("cancel")
    end

    it "does NOT render the sync pane" do
      get edit_game_path(game)
      expect(response.body).not_to include(">sync<")
    end

    it "does NOT render the linked videos pane" do
      get edit_game_path(game)
      # Heading-only check; the form hint copy ("…compute from linked
      # videos.") legitimately mentions the phrase.
      expect(response.body).not_to include(">linked videos<")
    end

    it "uses the narrow + wide pane layout" do
      get edit_game_path(game)
      expect(response.body).to include("pane pane--narrow")
      expect(response.body).to include("pane pane--wide")
    end
  end

  describe "POST /games with igdb_id" do
    before do
      GameIgdbSync.clear
    end

    it "creates a Game and enqueues GameIgdbSync" do
      expect {
        post games_path, params: { game: { igdb_id: 7346 } }
      }.to change(Game, :count).by(1)
      game = Game.last
      expect(game.igdb_id).to eq(7346)
      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to include("metadata loading")
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(game.id)
    end

    it "rejects a duplicate igdb_id (no enqueue, no duplicate row)" do
      existing = create(:game, igdb_id: 7346)
      expect {
        post games_path, params: { game: { igdb_id: 7346 } }
      }.not_to change(Game, :count)
      expect(response).to redirect_to(game_path(existing))
      expect(flash[:alert]).to include("already in your library")
      expect(GameIgdbSync.jobs).to be_empty
    end

    it "rejects negative igdb_id" do
      expect {
        post games_path, params: { game: { igdb_id: -1 } }
      }.not_to change(Game, :count)
    end

    # Phase 27 spec 04 (2026-05-17) — eager title pre-seed. The IGDB
    # search-result row's `name` is forwarded as a hidden form param
    # so the new Game's `title` lands at create time instead of
    # falling through to the model's `"Untitled game"` attribute
    # default. Bridges the in-flight window before `GameIgdbSync`
    # overwrites with the canonical IGDB record.
    it "seeds title from the params when provided" do
      expect {
        post games_path, params: { game: { igdb_id: 7346, title: "Pragmata" } }
      }.to change(Game, :count).by(1)
      game = Game.last
      expect(game.title).to eq("Pragmata")
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(game.id)
    end

    it "falls back to the attribute default when title is omitted" do
      post games_path, params: { game: { igdb_id: 7346 } }
      expect(Game.last.title).to eq("Untitled game")
    end

    it "falls back to the attribute default when title is blank" do
      post games_path, params: { game: { igdb_id: 7346, title: "   " } }
      expect(Game.last.title).to eq("Untitled game")
    end

    it "trims a seeded title to 255 chars" do
      long_title = "x" * 400
      post games_path, params: { game: { igdb_id: 7346, title: long_title } }
      expect(Game.last.title.length).to eq(255)
    end

    # Phase 27 spec 04 — permit list narrows to `:igdb_id, :title`.
    # Anything else smuggled into `params[:game]` is silently dropped.
    it "silently drops smuggled `notes` on create (not in permit list)" do
      post games_path, params: {
        game: { igdb_id: 7346, title: "Pragmata", notes: "evil" }
      }
      expect(Game.last.notes).to be_blank
    end

    it "silently drops smuggled `played_at` on create" do
      post games_path, params: {
        game: { igdb_id: 7346, title: "Pragmata", played_at: "2024-01-15" }
      }
      expect(Game.last.played_at).to be_nil
    end
  end

  # Phase 27 spec 04 (2026-05-17) — legacy "default create empty game"
  # surface is REMOVED. `POST /games` without `igdb_id` returns 422
  # (HTML branch redirects to /games with the same flash), no row is
  # persisted, and the JSON branch carries an `igdb_id_required`
  # error code.
  describe "POST /games WITHOUT igdb_id (legacy default-create removed)" do
    before { GameIgdbSync.clear }

    it "does not persist a row" do
      expect {
        post games_path
      }.not_to change(Game, :count)
    end

    it "redirects with the IGDB-only flash on the HTML branch" do
      post games_path
      expect(response).to redirect_to(games_path)
      expect(flash[:alert]).to eq(
        "games can only be added via the IGDB search modal."
      )
    end

    it "rejects a payload with title smuggled but no igdb_id" do
      expect {
        post games_path, params: { game: { title: "Foo" } }
      }.not_to change(Game, :count)
      expect(Game.where(title: "Foo")).to be_empty
    end

    it "rejects a payload with notes smuggled but no igdb_id" do
      expect {
        post games_path, params: { game: { notes: "evil" } }
      }.not_to change(Game, :count)
    end

    it "rejects with blank string igdb_id" do
      expect {
        post games_path, params: { game: { igdb_id: "" } }
      }.not_to change(Game, :count)
      expect(flash[:alert]).to include("IGDB search modal")
    end

    it "does NOT enqueue GameIgdbSync" do
      post games_path
      expect(GameIgdbSync.jobs).to be_empty
    end

    it "returns 422 + igdb_id_required on the JSON branch" do
      post games_path, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("igdb_id_required")
    end
  end

  describe "POST /games/:id/resync" do
    let!(:game) { create(:game, :synced) }

    before { GameIgdbSync.clear }

    it "enqueues GameIgdbSync and redirects with flash" do
      post resync_game_path(game)
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(game.id)
      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to include("refreshing from igdb")
    end

    it "404s when the game does not exist" do
      post "/games/999999/resync"
      expect(response).to have_http_status(:not_found)
    end

    # Phase 14 §1 polish (2026-05-10) — resync mutex.
    it "no-ops with a flash when a resync is already in flight" do
      game.update_column(:resyncing, true)
      expect {
        post resync_game_path(game)
      }.not_to change { GameIgdbSync.jobs.size }
      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to include("already resyncing")
    end

    # Phase 27 v2 spec 03 — JSON variant: 202 Accepted with the
    # Sidekiq jid on the happy path; 409 Conflict with
    # `already_resyncing` when the mutex is already held.
    describe "JSON variant" do
      it "returns 202 Accepted with the enqueued Sidekiq jid on accept" do
        post resync_game_path(game), headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:accepted)
        body = JSON.parse(response.body)
        expect(body["game_id"]).to eq(game.id)
        expect(body["resyncing"]).to eq("yes")
        expect(body["enqueued_jid"]).to be_present
      end

      it "returns 409 Conflict + already_resyncing when mutex is held" do
        game.update_column(:resyncing, true)
        expect {
          post resync_game_path(game), headers: { "Accept" => "application/json" }
        }.not_to change { GameIgdbSync.jobs.size }
        expect(response).to have_http_status(:conflict)
        body = JSON.parse(response.body)
        expect(body["game_id"]).to eq(game.id)
        expect(body["resyncing"]).to eq("yes")
        expect(body["error"]).to eq("already_resyncing")
      end
    end
  end

  describe "PATCH /games/:id" do
    let!(:platform) { create(:platform) }
    let!(:game) { create(:game, :synced, title: "IGDB Title", igdb_id: 12345) }

    # Phase 27 §1a — singular `platform_owned_id` is gone. The
    # local-only allowlist no longer permits it, so smuggled values
    # silently drop. Per-platform ownership lives in the
    # `game_platform_ownerships` join (the editor for it lands in
    # `01f`).
    it "silently drops smuggled platform_owned_id" do
      expect {
        patch game_path(game), params: { game: { platform_owned_id: platform.id } }
      }.not_to(change { game.reload.attributes.except("updated_at") })
    end

    it "permits played_at" do
      patch game_path(game), params: { game: { played_at: "2024-01-15" } }
      expect(game.reload.played_at).to eq(Date.new(2024, 1, 15))
    end

    it "permits notes" do
      patch game_path(game), params: { game: { notes: "loved it" } }
      expect(game.reload.notes).to eq("loved it")
    end

    it "permits hours_of_footage_manual" do
      patch game_path(game), params: { game: { hours_of_footage_manual: 7 } }
      expect(game.reload.hours_of_footage_manual).to eq(7)
    end

    it "silently drops smuggled igdb_id" do
      expect {
        patch game_path(game), params: { game: { igdb_id: 99999 } }
      }.not_to change { game.reload.igdb_id }
    end

    it "silently drops smuggled cover_image_id" do
      expect {
        patch game_path(game), params: { game: { cover_image_id: "evil" } }
      }.not_to change { game.reload.cover_image_id }
    end

    it "silently drops smuggled summary" do
      expect {
        patch game_path(game), params: { game: { summary: "hijacked" } }
      }.not_to change { game.reload.summary }
    end

    it "silently drops smuggled igdb_rating" do
      expect {
        patch game_path(game), params: { game: { igdb_rating: 5.0 } }
      }.not_to change { game.reload.igdb_rating }
    end

    it "silently drops smuggled title" do
      expect {
        patch game_path(game), params: { game: { title: "user override" } }
      }.not_to change { game.reload.title }
    end
  end

  describe "DELETE /games/:id" do
    it "destroys the game and cascades joins" do
      g = create(:game, :synced)
      genre = create(:genre)
      g.game_genres.create!(genre: genre)
      expect {
        delete game_path(g)
      }.to change(Game, :count).by(-1)
       .and change(GameGenre, :count).by(-1)
    end
  end

  # Phase 27 §01b — Filter row request integration. The controller
  # composes the filter AFTER `?genre=` / `?collection=` narrowing
  # (01c) and BEFORE per-mode partitioning (01d). Chip hrefs preserve
  # those overrides; unknown tokens are dropped silently.
  describe "GET /games with ?filters= (Phase 27 §01b)" do
    let!(:platform_ps5)     { create(:platform, name: "ps5",     slug: "ps5") }
    let!(:platform_switch2) { create(:platform, name: "switch2", slug: "switch2") }
    let!(:platform_steam)   { create(:platform, name: "steam",   slug: "steam") }
    let!(:owned_ps5_game) do
      g = create(:game, title: "Owned PS5 Game", release_date: 1.year.ago)
      g.game_platforms.create!(platform: platform_ps5)
      g.game_platform_ownerships.create!(platform: platform_ps5)
      g
    end
    let!(:not_owned_steam_game) do
      g = create(:game, title: "Steam Only Unowned", release_date: 1.year.ago)
      g.game_platforms.create!(platform: platform_steam)
      g
    end

    it "GET /games (no filters) returns 200" do
      get games_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /games?filters=ps5 returns 200 and applies the filter" do
      get games_path(filters: "ps5")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
      expect(response.body).not_to include("Steam Only Unowned")
    end

    it "GET /games?filters=ps5 renders [clear all]" do
      get games_path(filters: "ps5")
      expect(response.body).to include("clear all")
    end

    it "GET /games?filters=ps5,owned returns 200 and narrows to owned PS5" do
      get games_path(filters: "ps5,owned")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
      expect(response.body).not_to include("Steam Only Unowned")
    end

    it "marks active chips with the chip--active class" do
      get games_path(filters: "ps5")
      # The active chip carries chip--active in its class list.
      expect(response.body).to match(/class="[^"]*chip--active[^"]*"[^>]*data-filter-token="ps5"/)
    end

    it "GET /games?filters= (empty) treats as no filter, no [clear all]" do
      get games_path(filters: "")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("clear all")
    end

    it "GET /games?filters=garbage drops the unknown token (no [clear all])" do
      get games_path(filters: "garbage")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("clear all")
      expect(response.body).not_to include("garbage")
    end

    it "GET /games?filters=garbage,ps5 keeps ps5 active and excludes garbage from chip hrefs" do
      get games_path(filters: "garbage,ps5")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("clear all")
      # The garbage token must NOT echo into any chip-link href.
      # Filter-row hrefs all start with `/games?filters=`; assert none
      # contain "garbage".
      hrefs = response.body.scan(/href="(\/games[^"]*)"/).flatten
      filter_hrefs = hrefs.select { |h| h.include?("filters=") }
      expect(filter_hrefs).to all(satisfy { |h| !h.include?("garbage") })
    end

    it "GET /games?filters=owned,not_owned renders the contradiction notice" do
      get games_path(filters: "owned,not_owned")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("owned and not owned together")
      # Phase 27 v2 spec 05 — display-mode partition retired. The
      # contradiction filter zeroes `@all_games`, so the letter
      # shelves block doesn't render at all (the index view only
      # mounts it when `@letter_buckets.any?`). Confirm the listing
      # is empty by asserting the offending game's tile is absent.
      expect(response.body).not_to include("Owned PS5 Game")
    end

    it "GET /games?filters=ps5&genre=action preserves genre in chip hrefs" do
      get games_path(filters: "ps5", genre: "action")
      expect(response).to have_http_status(:ok)
      # The clear-all link preserves the genre override.
      expect(response.body).to match(/href="\/games\?genre=action"/)
    end

    it "GET /games?filters=ps5,ps5,owned de-duplicates" do
      get games_path(filters: "ps5,ps5,owned")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
    end

    it "GET /games?filters=PS5 (uppercase) normalises to ps5" do
      get games_path(filters: "PS5")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
    end

    it "GET /games with 100-token CSV does not 500" do
      tokens = Array.new(100) { |i| "bogus-#{i}" }.join(",")
      get games_path(filters: tokens)
      expect(response).to have_http_status(:ok)
    end

    it "SQL-injection payload as a token is dropped; games table intact" do
      before_count = Game.count
      payload = "ps5'; DROP TABLE games; --"
      get games_path(filters: payload)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(payload)
      expect(Game.count).to eq(before_count)
    end

    it "filter row HTML carries no data-turbo-confirm" do
      get games_path(filters: "ps5")
      # Scope the assertion to the filter-row section.
      filter_row = response.body.match(%r{<section class="games-filter-row".*?</section>}m)
      expect(filter_row).not_to be_nil
      expect(filter_row[0]).not_to include("data-turbo-confirm")
    end
  end

  # Phase 27 v2 spec 05 — display-mode switcher retired. `/games`
  # collapses to a single shelves-by-letter layout. Any `?display=`
  # value is silently ignored (the controller dropped the resolver and
  # the `User#preferred_games_display_mode` enum is gone).
  describe "GET /games (Phase 27 v2 spec 05 — shelves-only layout)" do
    let!(:alpha_game) { create(:game, :synced, title: "Alpha Game", igdb_id: 4_900_001, igdb_slug: "alpha-display") }
    let!(:mango_game) { create(:game, :synced, title: "Mango Quest", igdb_id: 4_900_002, igdb_slug: "mango-quest") }
    let!(:zinc_game)  { create(:game, :synced, title: "Zinc",        igdb_id: 4_900_003, igdb_slug: "zinc") }
    let!(:digit_game) { create(:game, :synced, title: "7 Days to Die", igdb_id: 4_900_004, igdb_slug: "seven-days") }

    it "renders one `<section class=\"shelf shelf--letter\">` per non-empty letter bucket" do
      get games_path
      expect(response).to have_http_status(:ok)
      # 4 buckets — A, M, Z, # — one section each.
      expect(response.body.scan('data-shelf="letter"').length).to eq(4)
    end

    it "hides letters that have no games (no `<h3>` for a missing letter)" do
      get games_path
      expect(response.body).not_to match(%r{<h3[^>]*>\s*B\s*</h3>})
      expect(response.body).not_to match(%r{<h3[^>]*>\s*Q\s*</h3>})
    end

    it "renders the digit-titled game's bucket as `#` and pins it to the END" do
      get games_path
      # The `#` heading comes after `Z` in document order.
      z_pos    = response.body.index('data-letter="Z"')
      hash_pos = response.body.index('data-letter="#"')
      expect(z_pos).not_to be_nil
      expect(hash_pos).not_to be_nil
      expect(z_pos).to be < hash_pos
    end

    it "ignores `?display=list` (the param is dropped from the resolver)" do
      get games_path(display: "list")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-display-mode=')
      # Layout is unchanged — still 4 letter shelves.
      expect(response.body.scan('data-shelf="letter"').length).to eq(4)
    end

    it "ignores `?display=grid` for the same reason" do
      get games_path(display: "grid")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-display-mode=')
    end

    it "ignores `?display=shelves_by_letter`" do
      get games_path(display: "shelves_by_letter")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-display-mode=')
    end

    it "does NOT render any `data-display-mode=` attribute anywhere" do
      get games_path
      expect(response.body).not_to include('data-display-mode=')
    end

    it "does NOT render the display-mode switcher" do
      get games_path
      expect(response.body).not_to include('class="display-mode-switcher"')
      expect(response.body).not_to include('action="/users/games_preferences"')
    end
  end

  # Phase 28 §01a — Multi-version game grouping.
  describe "GET /games (Phase 28 §01a primaries-only listing)" do
    let!(:primary)  { create(:game, title: "Pragmata") }
    let!(:edition)  { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }
    let!(:standalone) { create(:game, title: "Halo 3") }

    it "renders primaries only by default" do
      get games_path
      expect(response.body).to include("Pragmata")
      expect(response.body).to include("Halo 3")
      expect(response.body).not_to include("Pragmata Deluxe")
    end

    it "?include_editions=no is equivalent to no param" do
      get games_path, params: { include_editions: "no" }
      expect(response.body).not_to include("Pragmata Deluxe")
    end

    it "?include_editions=yes renders the flat list" do
      get games_path, params: { include_editions: "yes" }
      expect(response.body).to include("Pragmata Deluxe")
    end

    it "?include_editions=true (non-yes/no) falls back to primaries-only" do
      get games_path, params: { include_editions: "true" }
      expect(response.body).not_to include("Pragmata Deluxe")
    end

    it "does NOT render the [+N editions] badge on letter shelves (Phase 27 v2 spec 05)" do
      # Phase 27 v2 spec 05 — the all-games tile-grid partition retired
      # with the display-mode switcher. Letter-shelf tiles render via
      # `Games::CoverComponent` (cover-only); the `+N editions` badge
      # lives on `_tile.html.erb` which now only renders in the
      # bundles + recently-played shelves. A primaries-only listing
      # game with no `played_at` doesn't reach either, so the badge
      # is absent from the index. The badge still renders on the
      # game show page (its canonical surface).
      get games_path
      expect(response.body).not_to include("+1 edition")
    end

    it "does not render the muted parent pointer in primaries-only mode" do
      get games_path
      expect(response.body).not_to include("↳ Pragmata")
    end
  end

  describe "GET /games/version_parent_search" do
    let!(:pragmata) { create(:game, title: "Pragmata") }
    let!(:halo)     { create(:game, title: "Halo 3") }
    let!(:edition)  { create(:game, title: "Pragmata Deluxe", version_parent: pragmata) }

    it "returns 200 with empty results when q is blank" do
      get version_parent_search_games_path, params: { q: "" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["results"]).to eq([])
    end

    it "returns matching primaries by case-insensitive title ILIKE" do
      get version_parent_search_games_path, params: { q: "prag" }
      rows = JSON.parse(response.body)["results"]
      expect(rows.map { |r| r["title"] }).to include("Pragmata")
      expect(rows.map { |r| r["title"] }).not_to include("Pragmata Deluxe")
    end

    it "excludes the row referenced by ?exclude_id" do
      get version_parent_search_games_path, params: { q: "prag", exclude_id: pragmata.id }
      rows = JSON.parse(response.body)["results"]
      expect(rows.map { |r| r["id"] }).not_to include(pragmata.id)
    end

    it "caps results at 20" do
      30.times { |i| create(:game, title: "Pragmata #{i.to_s.rjust(3, '0')}") }
      get version_parent_search_games_path, params: { q: "prag" }
      rows = JSON.parse(response.body)["results"]
      expect(rows.size).to eq(20)
    end

    it "returns id + title for each row" do
      get version_parent_search_games_path, params: { q: "prag" }
      rows = JSON.parse(response.body)["results"]
      row = rows.find { |r| r["title"] == "Pragmata" }
      expect(row).to include("id" => pragmata.id, "title" => "Pragmata")
    end
  end

  describe "GET /games/:id (Phase 28 §01a show page)" do
    let!(:primary) { create(:game, title: "Pragmata") }

    context "for a primary with editions" do
      let!(:deluxe) { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }

      it "renders the editions section" do
        get game_path(primary)
        expect(response.body).to include('id="editions"')
        expect(response.body).to include("editions (1)")
        expect(response.body).to include("Pragmata Deluxe")
      end

      it "does not render an edition parent pointer" do
        get game_path(primary)
        expect(response.body).not_to include("edition-parent-pointer")
      end
    end

    context "for an edition" do
      let!(:deluxe) { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }

      it "renders the parent pointer link" do
        get game_path(deluxe)
        expect(response.body).to include("edition-parent-pointer")
        expect(response.body).to include("Pragmata")
      end

      it "does not render the editions section" do
        get game_path(deluxe)
        expect(response.body).not_to include('id="editions"')
      end
    end

    context "for a primary with no editions" do
      it "does not render the editions section" do
        get game_path(primary)
        expect(response.body).not_to include('id="editions"')
      end
    end
  end

  describe "GET /games/:id/edit (Phase 28 §01a edit page)" do
    let!(:primary) { create(:game, title: "Pragmata") }

    it "renders the version-parent picker" do
      get edit_game_path(primary)
      expect(response.body).to include('data-controller="version-parent-picker"')
    end

    it "renders the version_title text input" do
      get edit_game_path(primary)
      expect(response.body).to match(/name="game\[version_title\]"/)
    end

    context "for an edition pre-filled with its parent" do
      let!(:deluxe) { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }

      it "pre-fills the input with the parent's title" do
        get edit_game_path(deluxe)
        expect(response.body).to include('value="Pragmata"')
      end

      it "renders the [detach] link" do
        get edit_game_path(deluxe)
        expect(response.body).to include("detach")
      end
    end

    context "for a primary with editions of its own" do
      let!(:deluxe) { create(:game, title: "Pragmata Deluxe", version_parent: primary) }

      it "disables the picker input" do
        get edit_game_path(primary)
        expect(response.body).to match(/version-parent-picker-input[^>]*disabled/)
      end
    end
  end

  describe "PATCH /games/:id (Phase 28 §01a version fields)" do
    let!(:primary) { create(:game, title: "Pragmata") }
    let!(:other)   { create(:game, title: "Other Title") }

    it "attaches the row as an edition when version_parent_id is set" do
      patch game_path(other), params: { game: { version_parent_id: primary.id, version_title: "Deluxe" } }
      other.reload
      expect(other.version_parent_id).to eq(primary.id)
      expect(other.version_title).to eq("Deluxe")
    end

    it "detaches the row when version_parent_id is blank string" do
      edition = create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe")
      patch game_path(edition), params: { game: { version_parent_id: "" } }
      edition.reload
      expect(edition.version_parent_id).to be_nil
    end

    it "rejects pointing version_parent at an edition" do
      deluxe = create(:game, title: "Pragmata Deluxe", version_parent: primary)
      patch game_path(other), params: { game: { version_parent_id: deluxe.id } }
      expect(response).to have_http_status(:unprocessable_content)
      other.reload
      expect(other.version_parent_id).to be_nil
    end

    it "rejects self-reference" do
      patch game_path(other), params: { game: { version_parent_id: other.id } }
      expect(response).to have_http_status(:unprocessable_content)
      other.reload
      expect(other.version_parent_id).to be_nil
    end

    it "rejects setting version_parent_id on a row that has editions" do
      create(:game, version_parent: primary)
      patch game_path(primary), params: { game: { version_parent_id: other.id } }
      expect(response).to have_http_status(:unprocessable_content)
      primary.reload
      expect(primary.version_parent_id).to be_nil
    end

    it "trims version_title to 100 chars" do
      patch game_path(other), params: { game: { version_title: ("D" * 200) } }
      other.reload
      expect(other.version_title.length).to eq(100)
    end

    it "blanks version_title to nil" do
      other.update_column(:version_title, "Pre-existing")
      patch game_path(other), params: { game: { version_title: "  " } }
      other.reload
      expect(other.version_title).to be_nil
    end
  end

  describe "filter row integration (Phase 28 owned_rollup)" do
    let!(:primary)  { create(:game, title: "Pragmata") }
    let!(:deluxe)   { create(:game, title: "Pragmata Deluxe", version_parent: primary) }
    let!(:platform) { create(:platform, slug: "rollup-filter-platform") }

    before { create(:game_platform_ownership, game: deluxe, platform: platform) }

    it "primaries-only listing includes the primary when only its edition is owned (owned_rollup)" do
      get games_path, params: { filters: "owned" }
      expect(response.body).to include("Pragmata")
    end
  end
end
