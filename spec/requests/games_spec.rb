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

      it "renders the all-games section heading as 'all' (Fix 8, 2026-05-11)" do
        get games_path
        expect(response.body).to include(">all<")
        expect(response.body).not_to include(">all games<")
      end

      it "stamps a steam-shelf Stimulus controller on each shelf" do
        get games_path
        expect(response.body).to include('data-controller="steam-shelf"')
      end

      it "renders one nested genre sub-shelf per genre that owns a game" do
        # Phase 27 polish (2026-05-11) — the legacy `@genres_shelves`
        # iteration was retired; the 01c-v2 nested Genres outer shelf
        # is the single source of truth for genre-grouped tile rows.
        # `[see all]` no longer renders for small buckets (the nested
        # sub-shelf only shows `[see all]` when count > 30).
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.genres << genre
        get games_path
        expect(response.body).to include('data-shelf="genre-sub"')
        # Phase 27 follow-up (2026-05-11) — lowercase display label.
        expect(response.body).to match(%r{<h3[^>]*>\s*adventure\s*</h3>})
      end

      it "does NOT render a duplicate per-genre shelf below the all-games partition" do
        # Phase 27 polish (2026-05-11) — the legacy duplicate iteration
        # is gone. Only one render of each genre name should appear in
        # the page (the 01c-v2 nested sub-shelf <h3>).
        genre = Genre.create!(igdb_id: 999, name: "Adventure", slug: "adventure")
        zelda.genres << genre
        get games_path
        # Exactly one `<h3>` heading for this genre — the nested sub-shelf.
        expect(response.body.scan(%r{<h3[^>]*>\s*adventure\s*</h3>}).length).to eq(1)
      end

      it "renders [see all] links on per-platform shelves" do
        platform = Platform.create!(igdb_id: 998, name: "Switch", slug: "switch")
        zelda.game_platform_ownerships.create!(platform: platform)
        get games_path
        expect(response.body).to include("?platform_owned=#{platform.id}")
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

      it "does NOT render the hairline between genres and collections when one is empty (Fix 2)" do
        # Only a genre shelf renders here — collections are absent.
        adventure = Genre.create!(igdb_id: 50, name: "Adventure", slug: "adventure")
        g = create(:game, :synced, title: "Tunic", cover_image_id: "img-tunic")
        g.genres << adventure
        get games_path
        expect(response.body).to include('data-shelf="outer-genres"')
        expect(response.body).not_to include('<hr class="hairline">')
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

        it "renders an `<hr class=\"hairline\">` between the genres and collections shelves (Fix 2)" do
          get games_path
          # The hairline lives in `index.html.erb` between the two
          # outer shelves; assert presence and ordering.
          expect(response.body).to include('<hr class="hairline">')
          genres_pos = response.body.index('data-shelf="outer-genres"')
          hairline_pos = response.body.index('<hr class="hairline">')
          colls_pos = response.body.index('data-shelf="outer-collections"')
          expect(genres_pos).to be < hairline_pos
          expect(hairline_pos).to be < colls_pos
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
          # Phase 27 follow-up (2026-05-11) — display labels are
          # lowercase. SQL ordering is `LOWER(genres.name)` so the
          # canonical mixed-case names still sort as expected.
          order_indexes = [ "adventure", "platformer", "rpg" ].map { |n| genres_section.index(">#{n}<") }
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
  end

  describe "POST /games (legacy default-create)" do
    it 'creates an "Untitled game" row' do
      expect {
        post games_path
      }.to change(Game, :count).by(1)
      expect(Game.last.title).to eq("Untitled game")
      expect(flash[:notice]).to include("legacy")
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
      # The all-games grid sees Game.none — assert by scoping to the
      # grid section's empty-state copy (shelves above still render
      # the game; the filter row only narrows `@all_games`).
      # Phase 27 §01d — the grid section now carries the
      # `games-grid-mode` class in addition to the legacy
      # `all-games-grid`; match on the stable `data-display-mode`
      # hook instead of the exact class string.
      grid = response.body.match(%r{<section[^>]*data-display-mode="grid".*?</section>}m)
      expect(grid).not_to be_nil
      expect(grid[0]).to include("no games match this filter.")
      expect(grid[0]).not_to include("Owned PS5 Game")
    end

    it "GET /games?filters=ps5&display=list preserves display in chip hrefs" do
      get games_path(filters: "ps5", display: "list")
      expect(response).to have_http_status(:ok)
      # The clear-all link preserves the display override.
      expect(response.body).to match(/href="\/games\?display=list"/)
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

  # Phase 27 §01d — display mode resolution.
  #
  # `GET /games` reads `params[:display]` (single-request override),
  # falling back to `Current.user.preferred_games_display_mode`, with
  # `:grid` as the defensive final fallback. The display mode picks
  # which "all games" partial renders.
  describe "GET /games with display mode resolution (Phase 27 §01d)" do
    let(:password) { "supersecret123" }
    let(:user) do
      User.first || create(:user, password: password, password_confirmation: password)
    end

    before do
      user.update!(password: password, password_confirmation: password)
      sign_in_as(user)
      # At least one game so the all-games section actually renders.
      create(:game, :synced, title: "Alpha Game",
             igdb_id: 4_900_001, igdb_slug: "alpha-display")
    end

    it "defaults to grid mode when no ?display and no persisted pref deviation" do
      get games_path
      expect(response).to have_http_status(:ok)
      # Scope to the all-games <section> data-display-mode hook so the
      # switcher's own `data-display-mode="list"` button attributes do
      # not contaminate the match.
      expect(response.body).to match(/<section[^>]*data-display-mode="grid"/)
      expect(response.body).not_to match(/<section[^>]*data-display-mode="list"/)
      expect(response.body).not_to match(/<section[^>]*data-display-mode="shelves_by_letter"/)
    end

    it "GET /games?display=list renders the list partial" do
      get games_path(display: "list")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="list"')
      # List partial renders a `<table class="list-table">`.
      expect(response.body).to include('class="list-table"')
    end

    it "GET /games?display=shelves renders the shelves-by-letter partial" do
      get games_path(display: "shelves")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="shelves_by_letter"')
    end

    it "GET /games?display=shelves_by_letter also renders the shelves-by-letter partial" do
      get games_path(display: "shelves_by_letter")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="shelves_by_letter"')
    end

    it "GET /games?display=grid renders the grid partial" do
      get games_path(display: "grid")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="grid"')
    end

    it "uses the persisted preference when ?display is absent" do
      user.update!(preferred_games_display_mode: :list)
      get games_path
      expect(response.body).to include('data-display-mode="list"')
    end

    it "URL ?display= overrides the persisted preference for this request" do
      user.update!(preferred_games_display_mode: :list)
      get games_path(display: "grid")
      expect(response.body).to match(/<section[^>]*data-display-mode="grid"/)
      expect(response.body).not_to match(/<section[^>]*data-display-mode="list"/)
    end

    it "GET /games?display=garbage falls back to the persisted preference" do
      user.update!(preferred_games_display_mode: :list)
      get games_path(display: "garbage")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="list"')
    end

    it "after PATCHing the preference, GET /games renders the chosen mode" do
      patch users_games_preferences_path, params: { mode: "shelves_by_letter" }
      expect(response).to redirect_to(games_path(display: "shelves_by_letter"))
      get games_path
      expect(response.body).to include('data-display-mode="shelves_by_letter"')
    end

    it "renders the display-mode switcher in the page" do
      get games_path
      # The switcher button_to forms PATCH `/users/games_preferences`.
      # 2026-05-11 polish v2 — the three button labels are now
      # `[default][grid][list]` (was `[grid][list][shelves]`).
      expect(response.body).to include('action="/users/games_preferences"')
      expect(response.body).to include("[<span class=\"bl\">default</span>]")
      expect(response.body).to include("[<span class=\"bl\">grid</span>]")
      expect(response.body).to include("[<span class=\"bl\">list</span>]")
    end

    # Phase 27 polish (2026-05-11) — the switcher moved DOWN from the
    # H1 row into the filter row's right slot. The slot wrapper
    # (`.games-filter-row__right`) contains the `.display-mode-switcher`,
    # and the wrapper sits inside `<section class="games-filter-row">`.
    it "renders the switcher INSIDE the filter row (not the H1 row)" do
      get games_path
      filter_row = response.body.match(%r{<section class="games-filter-row".*?</section>}m)
      expect(filter_row).not_to be_nil
      expect(filter_row[0]).to include("games-filter-row__right")
      expect(filter_row[0]).to include('class="display-mode-switcher"')
    end

    it "the H1 row no longer hosts the display-mode switcher" do
      get games_path
      # Pull just the first <h1>...</h1> wrapper region (the H1 row).
      h1_row = response.body.match(%r{<div [^>]*display: flex[^>]*>.*?<h1>games</h1>.*?</div>\s*</div>}m)
      expect(h1_row).not_to be_nil
      expect(h1_row[0]).not_to include("display-mode-switcher")
    end

    it "marks the active mode button with the active class" do
      get games_path(display: "list")
      expect(response.body).to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">list<\/span>\]/m)
    end

    it "preserves the ?filters set across a display mode flip" do
      get games_path(filters: "owned", display: "list")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-display-mode="list"')
      # Clear-all link preserves both filter set departure and display.
      expect(response.body).to include('href="/games?display=list"')
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

    it "renders the [+N editions] badge on a primary with editions" do
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
