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

      it "renders the all-games section heading" do
        get games_path
        expect(response.body).to include(">all games<")
      end

      it "stamps a steam-shelf Stimulus controller on each shelf" do
        get games_path
        expect(response.body).to include('data-controller="steam-shelf"')
      end

      it "renders [see all] links on per-genre shelves" do
        genre = Genre.create!(igdb_id: 999, name: "Adventure")
        zelda.genres << genre
        get games_path
        expect(response.body).to include("?genre=#{genre.id}")
        expect(response.body).to include(">see all<")
      end

      it "renders [see all] links on per-platform shelves" do
        platform = Platform.create!(igdb_id: 998, name: "Switch")
        zelda.update!(platform_owned: platform)
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
      expect(response.body).to include('name="game[platform_owned_id]"')
      expect(response.body).to include('name="game[played_at]"')
      expect(response.body).to include('name="game[hours_of_footage_manual]"')
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

    it "permits platform_owned_id" do
      patch game_path(game), params: { game: { platform_owned_id: platform.id } }
      expect(game.reload.platform_owned_id).to eq(platform.id)
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
end
