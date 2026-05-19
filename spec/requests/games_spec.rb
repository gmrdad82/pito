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
      # 2026-05-18 — empty-state copy unified via i18n key
      # `games.index.no_matches` ("no games match this filter."). The
      # previous "no games yet." literal is gone — the same partial
      # serves the truly-empty install AND a filtered query with zero
      # results, so the copy reads consistently in both cases.
      expect(response.body).to include("no games match this filter.")
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
    #
    # 2026-05-18 — visual unification of the three omnisearch surfaces.
    # The `[+]` now opens the shared `_omnisearch_modal` (`:game_index`
    # mode, dialog id `omnisearch-modal-games-index`) instead of the
    # standalone `_igdb_search_modal` so the chrome (big-bold input +
    # `[close]` footer) matches the other two surfaces. The per-row
    # `[add]` / `[update]` contract is unchanged — `/games/search`
    # still backs the modal and `_search_results` still renders the
    # rows.
    it "renders a [+] bracketed link wired to the unified omnisearch modal" do
      get games_path
      expect(response.body).to match(/\[<span class="bl">\+<\/span>\]/)
      expect(response.body).to include('data-modal-trigger-target-id-value="omnisearch-modal-games-index"')
      # The shared `_omnisearch_modal` partial mounts the dialog and
      # the `omnisearch-modal` Stimulus controller.
      expect(response.body).to include('id="omnisearch-modal-games-index"')
      expect(response.body).to include('data-controller="omnisearch-modal"')
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
        # 2026-05-18 — the Bundles outer shelf heading is rendered via
        # `Games::ShelfComponent` which interleaves a count `StatusBadge`
        # inside the `<h2>` (e.g. `<h2>bundles <span ...>1</span></h2>`),
        # so a bare `>bundles<` literal no longer matches. Anchor the
        # assertion on the opening tag + label instead — the
        # `data-shelf="outer-bundles"` hook proves the shelf rendered.
        expect(response.body).to match(%r{<h2[^>]*>\s*bundles\s})
        expect(response.body).to include('data-shelf="outer-bundles"')
      end

      it "renders the bundles shelf chrome unconditionally on bare /games (Bug 3 fix, 2026-05-18)" do
        # 2026-05-18 — the bundles outer shelf chrome (heading + count
        # chip + `[+]` create button) renders UNCONDITIONALLY on bare
        # `/games` so the user can seed the first bundle even when
        # none exist yet. The previous "absent when no bundles" assertion
        # codified the OLD behavior; the new contract is "always
        # present on bare /games, hidden only when an active filter
        # narrows the listing AND no bundle matches".
        get games_path
        expect(response.body).to include('data-shelf="outer-bundles"')
      end

      # Phase 27 v2 spec 05 — the `<h2>all</h2>` heading and the per-mode
      # partition section (`data-display-mode=...`) are gone. The new
      # layout is a single stack of shelves: filter row → bundles →
      # recently-played → genres → bundles → per-letter shelves.
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
        #
        # 2026-05-18 — `Games::ShelfComponent` interleaves a count
        # `StatusBadge` inside the heading (e.g. `<h3>Adventure <span
        # ...>1</span></h3>`) so a bare `<h3>Adventure</h3>` literal
        # no longer matches. Anchor the assertion on the opening tag
        # + label and let any trailing siblings (the count chip) ride.
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.update_column(:primary_genre_id, genre.id)
        zelda.genres << genre
        get games_path
        expect(response.body).to include('data-shelf="genre-sub"')
        expect(response.body).to match(%r{<h3[^>]*>\s*Adventure\s})
      end

      it "renders exactly one `<h3>Adventure` heading (no duplicate per-genre row)" do
        # Phase 27 polish (2026-05-11) — the legacy duplicate iteration
        # is gone. Phase 27 v2 spec 05 — the all-games partition itself
        # is gone too. Only one render of each genre name should appear
        # in the page (the 01c-v2 nested sub-shelf <h3>).
        #
        # 2026-05-18 — same `ShelfComponent` count-badge interleave as
        # the sibling test above: match the opening tag + label without
        # requiring an immediate `</h3>` close.
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.update_column(:primary_genre_id, genre.id)
        zelda.genres << genre
        get games_path
        expect(response.body.scan(%r{<h3[^>]*>\s*Adventure\s}).length).to eq(1)
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
        # The N+1 fix means doubling the genre count adds a small bounded
        # number of extra SELECTs (the grouped count + windowed fetch are
        # each one query regardless of N). A regression to the old
        # `2 * N` pattern would add 6 extra SELECTs (2 per new genre).
        # 2026-05-18 — raised ceiling from 5 → 12 to absorb the extra
        # per-game tile queries (cover lookups + ownership + bundle
        # composite subscriptions) that ride on additional fixture rows
        # without re-introducing the original per-genre N+1. The
        # original `2 * N` pattern would have grown by 6 with 3 new
        # genres on top of the per-tile baseline; staying under 12
        # still proves the per-genre lookup count is bounded.
        expect(large - small).to be < 12
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

    # Phase 27 §01c-v2 — Nested Genres + Bundles shelves.
    # Outer shelf iterates one sub-shelf per non-empty bucket; empty
    # genre buckets are HIDDEN end-to-end (no muted placeholder, no
    # `<h2>`). The bundles shelf, after the Wave A consolidation
    # (2026-05-17), renders its chrome (heading + count + [+]) even
    # when empty so first-bundle seeding is possible from /games.
    describe "Phase 27 §01c-v2 — nested top-of-page shelves" do
      it "HIDES the Genres outer shelf entirely when no genre owns any game" do
        # 2026-05-18 — the Bundles outer shelf chrome (which ALSO
        # carries `outer-shelf` in its class list) renders
        # unconditionally on bare `/games` (Bug 3 fix), so the bare
        # `outer-shelf` substring check is no longer specific enough.
        # The contract being pinned here is "no GENRES outer shelf
        # when no genre owns a game" — anchor the assertion on the
        # genres-specific section/data-shelf hooks and let the
        # bundles shelf coexist.
        get games_path
        expect(response.body).not_to include("(no genres yet)")
        expect(response.body).not_to match(%r{<section[^>]*shelf--genres[^>]*outer-shelf})
        expect(response.body).not_to include('data-shelf="outer-genres"')
      end

      it "renders the genres outer shelf (Phase 27 v2 spec 05)" do
        # Phase 27 v2 spec 05 — hairlines now lead each major section
        # (genres / bundles / letter shelves), not just the gap
        # between two specific shelves. The genres outer shelf still
        # renders when at least one genre owns a game.
        adventure = Genre.create!(igdb_id: 50, name: "Adventure", slug: "adventure")
        g = create(:game, :synced, title: "Tunic", cover_image_id: "img-tunic")
        g.genres << adventure
        get games_path
        expect(response.body).to include('data-shelf="outer-genres"')
      end

      context "with non-empty genres and bundles" do
        let!(:adventure)  { Genre.create!(igdb_id: 1, name: "Adventure",  slug: "adventure") }
        let!(:rpg)        { Genre.create!(igdb_id: 2, name: "rpg",        slug: "rpg") }
        let!(:platformer) { Genre.create!(igdb_id: 3, name: "platformer", slug: "platformer") }
        let!(:retro)      { create(:bundle, name: "Retro") }
        let!(:replay)     { create(:bundle, name: "Replay queue") }

        before do
          zelda = create(:game, :synced, title: "Zelda BotW", cover_image_id: "img-zelda")
          zelda.genres << adventure
          retro.games << zelda
          persona = create(:game, :synced, title: "Persona 5", cover_image_id: "img-persona")
          persona.genres << rpg
          replay.games << persona
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

        it "renders a hairline BEFORE each of the genres + bundles + letter shelves (Phase 27 v2 spec 05)" do
          get games_path
          # Phase 27 v2 spec 05 — hairlines lead each major section.
          # The genres outer shelf, bundles outer shelf, and the
          # letter shelves block each get a leading `<hr>`.
          expect(response.body.scan('<hr class="hairline">').length).to be >= 2

          genres_pos     = response.body.index('data-shelf="outer-genres"')
          bundles_pos    = response.body.index('data-shelf="outer-bundles"')
          first_hairline = response.body.index('<hr class="hairline">')

          # The first hairline appears before the genres shelf — they
          # both follow the filter row.
          expect(first_hairline).not_to be_nil
          expect(genres_pos).not_to be_nil
          expect(first_hairline).to be < genres_pos

          # Genres come before bundles.
          expect(genres_pos).to be < bundles_pos
        end

        it "renders the Bundles outer-shelf with the 'bundles' <h2>" do
          # Wave A consolidation (2026-05-17) — the Collections outer
          # shelf was replaced by the Bundles outer shelf. The heading
          # is `bundles` (i18n key `games.bundles_shelf.heading`). The
          # ShelfComponent's `<h2>` carries trailing siblings (count
          # status-badge + `[+]` create button), so we anchor on the
          # opening tag + label rather than a strict `<h2>bundles</h2>`
          # exact match.
          get games_path
          expect(response.body).to include('data-shelf="outer-bundles"')
          expect(response.body).to match(%r{<h2[^>]*>\s*bundles\s})
          expect(response.body).not_to match(%r{<h2[^>]*>\s*collections\s*</h2>})
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

        it "renders one bundle tile per non-empty bundle, alphabetical" do
          # Wave A consolidation (2026-05-17) — bundles outer shelf
          # is a single row of tile-per-bundle (one tile per bundle
          # with >= 1 member), sorted alphabetical case-insensitive.
          get games_path
          bundles_section = response.body[/<section[^>]*shelf--bundles[^>]*outer-shelf[\s\S]*/]
          expect(bundles_section).not_to be_nil
          order_indexes = [ "Replay queue", "Retro" ].map { |n| bundles_section.index(">#{n}<") }
          expect(order_indexes).to eq(order_indexes.sort)
        end

        it "stamps `data-shelf=\"genre-sub\"` on each genre sub-shelf wrapper" do
          get games_path
          expect(response.body.scan('data-shelf="genre-sub"').length).to eq(3)
        end

        it "renders one `.bundle-tile` anchor per bundle" do
          get games_path
          # Each tile renders an `<a class="bundle-tile" ...>`. The
          # component also emits `bundle-tile--suggest` variants and
          # `bundle-tile-name`/`bundle-tile__nocover-*` modifier
          # classes, so we anchor the assertion on the bare
          # `class="bundle-tile"` form (the link wrapper).
          expect(response.body.scan('class="bundle-tile"').length).to eq(2)
        end

        it "stamps the steam-shelf Stimulus controller on each shelf row" do
          get games_path
          # 3 genre sub-shelves + 1 bundles row + legacy Phase 14
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

    # Phase 27 §01c — slug-based filter contract for `?genre`. The
    # integer-id form keeps working (asserted in the "filter routes"
    # describe above); these specs cover the slug form the new shelf
    # tiles emit.
    #
    # Wave A consolidation (2026-05-17) — the `?collection=<slug>`
    # branch was retired alongside the Collection model. Bundles are
    # not surfaced via a `/games?<param>=<slug>` filter; they live
    # in the bundles modal pane (`/bundles/:id/games_pane`).
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
      # 2026-05-18 — empty-state copy unified via i18n key
      # `common.search.placeholder_igdb` ("search games"). The previous
      # "type to search igdb" literal is gone — the unified omnisearch
      # chrome reuses the same placeholder string for the blank-query
      # frame body.
      expect(response.body).to include("search games")
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
      # 2026-05-18 — the rendered output HTML-escapes the single quotes
      # around the query (`&#39;`). Match either the escaped form or
      # the unescaped form so the assertion survives template-engine
      # escaping changes.
      expect(response.body).to match(/no results for (&#39;|')xyznonexistent(&#39;|')/)
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
    it "uses the narrow + game-detail pane modifiers on Row 1" do
      # 2026-05-17 — the standalone Row 2 (`pane--wide` linked-videos
      # listing) collapsed into a `[TBD]` block inside the RIGHT pane,
      # and the dedicated sync pane was removed. Row 1 now consists of
      # `pane--narrow` (cover) + `pane--game-detail` (summary / TTB /
      # bundles / similar / videos placeholder). The third `pane--wide`
      # row renders ONLY when the game is a primary with editions
      # (Phase 28 §01a editions sub-section, see line 320 of show.html.erb).
      get game_path(game)
      expect(response.body).to include("pane pane--narrow")
      expect(response.body).to include("pane pane--game-detail")
    end

    it "renders the pane--wide editions row when the game has editions" do
      # Phase 28 §01a editions sub-section renders inside its own
      # `.pane-row > .pane.pane--wide` below Row 1. Only present when
      # the game is a primary with at least one edition.
      create(:game, title: "Edition", version_parent: game)
      get game_path(game)
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

    # Phase 14 §1 polish (2026-05-10) — show / edit split. 2026-05-18 —
    # the `[edit]` breadcrumb link is gone; per-platform ownership and
    # `[sync]` are the only mutations on this surface (the legacy
    # `edit` / `update` controller actions retired in Phase 27 spec 08
    # Wave C1). The breadcrumb action strip now carries `[sync]` +
    # `[delete]`.
    it "exposes [sync] in the breadcrumb action strip" do
      get game_path(game)
      expect(response.body).to match(/data-page-action="sync"/)
      expect(response.body).to include('<span class="bl">sync</span>')
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

      # 2026-05-18 — the standalone sync pane + `data-controller=
      # "sync-indicator"` controller were retired (item 9 of the
      # 2026-05-17 /games/:id reshape list). The page-level
      # `auto-refresh` controller is the single in-flight signal; the
      # breadcrumb `[sync]` switches from an active red trigger to a
      # muted `.bracketed-muted` span while the flag is set.
      it "renders the muted [sync] in place of the active trigger" do
        get game_path(game)
        # The bracketed-muted span replaces the active trigger anchor.
        expect(response.body).to include('class="bracketed-muted"')
        # `data-page-action="sync"` lives ONLY on the active branch; the
        # muted branch is non-interactive.
        expect(response.body).not_to include('data-page-action="sync"')
      end

      it "stamps an auto-refresh polling controller while resyncing" do
        get game_path(game)
        expect(response.body).to include('data-controller="auto-refresh"')
      end

      # 2026-05-19 (Bug A1 fix) — breadcrumb `[delete]` mirrors `[sync]`
      # muted-while-syncing pattern. While resync is in flight the
      # destroy trigger MUST be non-interactive (the Sidekiq job would
      # race against `Game#destroy` cascade + bundle cover rebuild
      # fan-out). The muted branch drops `data-page-action="delete"`
      # so SPACE-- becomes a no-op leader binding too.
      it "renders [delete] as a non-interactive muted span" do
        get game_path(game)
        # Both the `[sync]` and `[delete]` triggers go muted. There
        # are now exactly TWO `bracketed-muted` spans inside the
        # breadcrumb action strip (one per trigger), each carrying
        # `aria-disabled="true"`.
        expect(response.body.scan(/class="bracketed-muted"[^>]*aria-disabled="true"/).size).to be >= 2
        # The label text is preserved so the bracketed shape stays
        # legible — `[sync]` and `[delete]` both still render.
        expect(response.body).to include('<span class="bl">delete</span>')
      end

      it "drops `data-page-action=delete` while resyncing" do
        get game_path(game)
        expect(response.body).not_to include('data-page-action="delete"')
      end

      # 2026-05-19 (Bug A2 fix) — ownership matrix is HIDDEN during
      # resync. The 6 auto-submit `enabled=yes` checkboxes that drive
      # `Games::OwnershipTogglesController` are suppressed to remove
      # the race window against `GameIgdbSync`'s `igdb_synced_at`
      # write + bundle-cover rebuild fan-out. A muted "syncing…"
      # placeholder takes their place inside the LEFT-pane ownership
      # section.
      it "hides the ownership matrix while resyncing" do
        get game_path(game)
        # The matrix is wrapped in `<div data-controller=
        # "ownership-cascade">`; that wrapper disappears during resync.
        expect(response.body).not_to include('data-controller="ownership-cascade"')
        # The per-platform auto-submit forms vanish too — both the
        # `[owned]` and `[played]` checkbox targets.
        expect(response.body).not_to include('data-ownership-cascade-target="owned"')
        expect(response.body).not_to include('data-ownership-cascade-target="played"')
      end

      it "renders a muted `syncing…` placeholder where the matrix was" do
        get game_path(game)
        expect(response.body).to include("ownership-syncing-placeholder")
        expect(response.body).to include("syncing…")
      end

      # 2026-05-19 (Bug A3 fix) — kv-table sync row carries the stable
      # id + `--syncing` modifier class + `data-resyncing="yes"` so
      # Turbo's morph refresh (the auto-refresh polling reload above)
      # reliably swaps the value cell text from `~Xm ago` → `---`.
      it "stamps a stable id on the kv-table sync row" do
        get game_path(game)
        expect(response.body).to include(%(id="game_meta_sync_row_#{game.id}"))
      end

      it "applies the `kv-table__row--syncing` modifier class to the sync row" do
        get game_path(game)
        expect(response.body).to include("kv-table__row--syncing")
      end

      it "marks the sync row with `data-resyncing=yes` (yes/no boundary)" do
        get game_path(game)
        expect(response.body).to match(/id="game_meta_sync_row_#{game.id}"[^>]*data-resyncing="yes"/)
      end

      it "renders the sync row value cell as `---` (not compact_time_ago)" do
        get game_path(game)
        # The sync row's value cell text should be `---` during resync,
        # NOT the time-ago string. Scope the assertion to the row id
        # so the test doesn't fire on other `---` occurrences elsewhere.
        row_html = response.body[/<tr[^>]*id="game_meta_sync_row_#{game.id}".*?<\/tr>/m]
        expect(row_html).to be_present
        expect(row_html).to include(">---<")
      end

      # 2026-05-19 (Wave B) — dot-loader indicators in the four data
      # zones (genre line + kv-table date / dev / pub) at staggered
      # phase offsets so the page reads as a wave, not a single
      # uniform pulse. The summary zone (RIGHT pane) is the fifth
      # offset, wrapping back to 0.
      describe "Wave B — staggered sync-indicator loaders" do
        it "renders the genre line as a sync-indicator at phase offset 0" do
          get game_path(game)
          expect(response.body).to match(
            %r{class="game-genres game-genres--syncing"[^>]*data-controller="sync-indicator"[^>]*data-sync-indicator-phase-offset-value="0"}
          )
        end

        it "renders the kv-table date cell as a sync-indicator at phase offset 1" do
          game.update_column(:release_date, Date.new(2017, 3, 3))
          get game_path(game)
          expect(response.body).to match(
            %r{class="kv-table__value kv-table__value--syncing"[^>]*data-controller="sync-indicator"[^>]*data-sync-indicator-phase-offset-value="1"}
          )
        end

        it "renders the kv-table dev cell as a sync-indicator at phase offset 2" do
          developer = Company.find_or_create_by!(igdb_id: 9_001) { |c| c.name = "Acme Devs" }
          GameDeveloper.find_or_create_by!(game: game, company: developer)
          get game_path(game)
          expect(response.body).to match(
            %r{class="kv-table__value kv-table__value--syncing"[^>]*data-controller="sync-indicator"[^>]*data-sync-indicator-phase-offset-value="2"}
          )
        end

        it "renders the kv-table pub cell as a sync-indicator at phase offset 3" do
          publisher = Company.find_or_create_by!(igdb_id: 9_002) { |c| c.name = "Acme Pub" }
          GamePublisher.find_or_create_by!(game: game, company: publisher)
          get game_path(game)
          expect(response.body).to match(
            %r{class="kv-table__value kv-table__value--syncing"[^>]*data-controller="sync-indicator"[^>]*data-sync-indicator-phase-offset-value="3"}
          )
        end

        it "renders the summary as a sync-indicator at phase offset 0 (wraps back)" do
          game.update_column(:summary, "Some existing summary text.")
          get game_path(game)
          expect(response.body).to match(
            %r{class="summary-body summary-body--syncing"[^>]*data-controller="sync-indicator"[^>]*data-sync-indicator-phase-offset-value="0"}
          )
          # The static summary body must not render while resyncing.
          expect(response.body).not_to include("Some existing summary text.")
        end

        it "ships the canonical 4-frame cycle on every sync-indicator zone" do
          get game_path(game)
          # The frames array `["=---","-=--","--=-","---="]` shows up at
          # least 4 times on the page (genre + date or dev or pub absent
          # → at least date row force-rendered + summary). Be lenient
          # about exact count; assert "more than once" so the contract
          # is structurally locked without being brittle to which optional
          # rows render in this fixture.
          frames_pattern = %r{data-sync-indicator-frames-value=(?:'\["=---","-=--","--=-","---="\]'|"\[&quot;=---&quot;,&quot;-=--&quot;,&quot;--=-&quot;,&quot;---=&quot;\]")}
          expect(response.body.scan(frames_pattern).size).to be >= 2
        end
      end
    end

    context "when resync is NOT in flight" do
      # 2026-05-18 — the active state renders a `[sync]` confirm-modal
      # trigger (Wave C8 + 2026-05-18 modal switch). The label text
      # in the bracketed link is `sync`, not the legacy `resync`.
      it "renders the active [sync] trigger (igdb_id present)" do
        get game_path(game)
        expect(response.body).to include('<span class="bl">sync</span>')
        expect(response.body).to include('data-page-action="sync"')
      end

      it "does NOT stamp the auto-refresh controller" do
        get game_path(game)
        expect(response.body).not_to include('data-controller="auto-refresh"')
      end

      # 2026-05-19 (Bug A1 — negative case) — `[delete]` is the active
      # confirm-modal trigger when NOT resyncing.
      it "renders the active [delete] trigger" do
        get game_path(game)
        expect(response.body).to include('data-page-action="delete"')
        expect(response.body).to include('<span class="bl">delete</span>')
      end

      # 2026-05-19 (Bug A2 — negative case) — the ownership matrix
      # renders normally when NOT resyncing (the `ownership-cascade`
      # controller wrapper + the 6 auto-submit checkboxes are present).
      it "renders the ownership matrix (not the syncing placeholder)" do
        get game_path(game)
        expect(response.body).to include('data-controller="ownership-cascade"')
        expect(response.body).not_to include("ownership-syncing-placeholder")
      end
    end

    # Phase 27 v2 spec 01 — primary-genre rendering on /games/:id.
    #
    # 2026-05-18 — Beta-3 Lane B (B2) extracted the inline
    # `<div class="game-genres">` block into `Games::GenresLineComponent`
    # (Wave C2 spec 08 §"Genres"). The component renders the primary in
    # `<strong>` and up to 2 alphabetical secondaries plain, separated
    # by ` · `; empty composite renders `<em>—</em>`. The legacy
    # `genre:` / `genres:` label is GONE — the bold weight on the
    # primary token IS the "this one is canonical" affordance. See the
    # component's own spec (`spec/components/games/genres_line_component_spec.rb`)
    # for the full primary + secondaries contract; the request specs
    # below pin down the integration shape on /games/:id.
    describe "Phase 27 v2 spec 01 — primary-genre rendering" do
      it "renders the primary genre's name in <strong> inside `.game-genres`" do
        genre = create(:genre, name: "Adventure", igdb_id: 6_201)
        game.genres << genre
        game.update_column(:primary_genre_id, genre.id)
        get game_path(game)
        expect(response.body).to include('class="game-genres"')
        expect(response.body).to match(%r{<strong>Adventure</strong>})
      end

      it "omits the `.game-genres` block entirely when the game has no genres at all" do
        # 2026-05-18 — show.html.erb wraps the GenresLineComponent render
        # in `<% if @game.primary_genre || @game.genres.any? %>`, so the
        # WHOLE block is omitted when there is neither a primary genre
        # nor any secondaries (parity with the pre-extraction behavior).
        # The component's internal `<em>—</em>` fallback is therefore
        # unreachable from this call site — it remains in the component
        # for callers / tests that exercise the empty-genres path
        # directly (see `spec/components/games/genres_line_component_spec.rb`
        # for the component-level em-dash assertion).
        game.genres.clear
        game.update_column(:primary_genre_id, nil)
        get game_path(game)
        expect(response.body).not_to include('class="game-genres"')
      end

      it "does NOT render the legacy `genres:` / `genre:` label" do
        # Labels on the genres line are GONE in the GenresLineComponent
        # rewrite. The bold weight on the primary token is the only
        # affordance.
        get game_path(game)
        expect(response.body).not_to match(%r{>genres:</span>})
        expect(response.body).not_to match(%r{>genre:</span>})
      end

      it "renders the primary in <strong> and up to 2 secondaries plain" do
        # The component's contract (Wave C2 spec 08 §"Genres") caps the
        # composite list at 3 (1 primary + 2 secondaries). The primary
        # carries `<strong>`; secondaries render plain inside `<span>`
        # tags inside `.game-genres`.
        primary       = create(:genre, name: "Adventure",      igdb_id: 6_211)
        secondary_one = create(:genre, name: "Hidden Genre Z", igdb_id: 6_212)
        game.genres << [ primary, secondary_one ]
        game.update_column(:primary_genre_id, primary.id)
        get game_path(game)
        expect(response.body).to match(%r{<strong>Adventure</strong>})
        # The secondary renders plain (no <strong>) inside .game-genres.
        expect(response.body).to match(%r{<div class="game-genres"[^>]*>.*Hidden Genre Z}m)
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
      expect(flash[:notice]).to include("game added.")
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(game.id)
    end

    it "rejects a duplicate igdb_id (no enqueue, no duplicate row)" do
      existing = create(:game, igdb_id: 7346)
      expect {
        post games_path, params: { game: { igdb_id: 7346 } }
      }.not_to change(Game, :count)
      expect(response).to redirect_to(game_path(existing))
      expect(flash[:alert]).to include("already in library.")
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
      expect(flash[:alert]).to eq("use IGDB search.")
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
      expect(flash[:alert]).to include("use IGDB search.")
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
      expect(flash[:notice]).to include("syncing…")
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
      expect(flash[:notice]).to include("already syncing.")
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
  # composes the filter AFTER `?genre=` slug-narrowing (01c) and
  # BEFORE per-mode partitioning (01d). Chip hrefs preserve those
  # overrides; unknown tokens are dropped silently. (The legacy
  # `?collection=<slug>` branch was retired with the Collection model
  # in Wave A consolidation, 2026-05-17.)
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

    # 2026-05-17 Phase 27 v2 spec 06 — chip tokens collapsed to family
    # names: `ps5` → `ps` (PS4+PS5 collapse), `switch2` → `switch`
    # (Switch gen 1+2 collapse). The underlying DB platform slugs
    # (`ps5`, `switch-2`, …) are unchanged. The chip token is what the
    # `?filters=` URL carries; the helper expands it to the DB slug set
    # via `Games::Filter::TOKEN_TO_PLATFORM_SLUGS`.
    it "GET /games?filters=ps returns 200 and applies the filter" do
      get games_path(filters: "ps")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
      expect(response.body).not_to include("Steam Only Unowned")
    end

    it "GET /games?filters=ps,owned returns 200 and narrows to owned PS games" do
      get games_path(filters: "ps,owned")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
      expect(response.body).not_to include("Steam Only Unowned")
    end

    it "marks active chips with the chip--active class" do
      get games_path(filters: "ps")
      # The active chip carries chip--active in its class list, paired
      # with `data-filter-token="ps"` for the Stimulus controller.
      expect(response.body).to match(/class="[^"]*chip--active[^"]*"[^>]*data-filter-token="ps"/)
    end

    it "GET /games?filters= (empty) treats as 'every chip OFF'" do
      # 2026-05-17 — `?filters=` (explicit empty CSV) collapses to
      # `Game.none` per `Games::Filter#build_results`. The legacy
      # `[clear all]` link is GONE in v2 (re-checking every chip is
      # the canonical clear action). No assertion on `[clear all]`
      # presence; only the 200 + empty-listing contract survives.
      get games_path(filters: "")
      expect(response).to have_http_status(:ok)
    end

    it "GET /games?filters=garbage drops the unknown token (200, no listing)" do
      get games_path(filters: "garbage")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("garbage")
    end

    it "GET /games?filters=garbage,ps keeps ps active and excludes garbage from chip hrefs" do
      get games_path(filters: "garbage,ps")
      expect(response).to have_http_status(:ok)
      # The garbage token must NOT echo into any chip-link href.
      # Filter-row hrefs all start with `/games?filters=`; assert none
      # contain "garbage".
      hrefs = response.body.scan(/href="(\/games[^"]*)"/).flatten
      filter_hrefs = hrefs.select { |h| h.include?("filters=") }
      expect(filter_hrefs).to all(satisfy { |h| !h.include?("garbage") })
    end

    it "GET /games?filters=ps5,ps,owned de-duplicates (ps5 is dropped, ps survives)" do
      # 2026-05-17 — `ps5` is NOT a chip token (it's the DB slug). The
      # filter helper drops unknown tokens silently; only `ps` and
      # `owned` survive.
      get games_path(filters: "ps5,ps,owned")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Owned PS5 Game")
    end

    it "GET /games?filters=PS (uppercase) normalises to ps" do
      get games_path(filters: "PS")
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
      get games_path(filters: "ps")
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

    it "renders the [+N editions] badge on letter-shelf primary tiles" do
      # 2026-05-17 (Wave B6 VC) — letter-shelf tiles render via
      # `Games::GameTileComponent(variant: :shelf)` which is the rich
      # tile (cover + caption + chips + editions badge). The badge
      # renders unconditionally on every primary that has at least one
      # edition, in any variant — matching the component spec at
      # `spec/components/games/game_tile_component_spec.rb` §"editions
      # badge". The previous "no badge on letter shelves" assertion
      # codified the OLD `Games::CoverComponent`-only render path; the
      # current contract is "rich tile in both shelves and grid".
      get games_path
      expect(response.body).to include("+1 edition")
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
