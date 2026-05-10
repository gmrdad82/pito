require "rails_helper"
require "ostruct"

RSpec.describe "Games", type: :request do
  describe "GET /games" do
    it "returns 200" do
      get games_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the empty-state copy when no rows exist" do
      get games_path
      expect(response.body).to include("no games yet.")
      expect(response.body).to include("type in the search box above")
    end

    # Phase 14 §1 polish (2026-05-10) — the legacy `[search igdb]`
    # sibling button on the add form was dropped. The input submits on
    # Enter; only the placeholder still mentions IGDB. The button-shaped
    # `[search igdb]` chip should NOT be present anywhere on the page.
    it "does not render a [search igdb] chip on the add form" do
      get games_path
      expect(response.body).not_to include("[search igdb]")
    end

    context "with at least one row" do
      let!(:game) do
        create(:game, :synced, title: "Zelda BotW", igdb_id: 7346,
               release_year: 2017, igdb_rating: 95.0)
      end

      it "links the row's title directly to the show page" do
        get games_path
        expect(response.body).to include(%(href="#{game_path(game)}"))
        expect(response.body).to include("Zelda BotW")
      end

      # The `[o]` open-action column was retired in the same polish
      # pass — the title cell IS the link, mirroring channels/videos.
      it "does not render a separate [o] open-action column" do
        get games_path
        expect(response.body).not_to include(">o<")
      end

      it "renders sortable headers (name / release / rating / played / last sync)" do
        get games_path
        expect(response.body).to include("class=\"sortable")
        expect(response.body).to include(">name<")
        expect(response.body).to include(">release<")
        expect(response.body).to include(">rating<")
        expect(response.body).to include(">played<")
        expect(response.body).to include(">last sync<")
      end

      it "renders a [bulk] toggle next to [+]" do
        get games_path
        expect(response.body).to include("bulk-select-target=\"bulkToggle\"")
        expect(response.body).to include(">bulk<")
      end

      it "renders bulk-select checkbox columns (initially hidden)" do
        get games_path
        expect(response.body).to include("bulk-select-target=\"bulkCol\"")
        expect(response.body).to include("bulk-select-target=\"headerCheckbox\"")
        expect(response.body).to include("bulk-select-target=\"checkbox\"")
      end

      # Frame-escape regression guard (2026-05-10). The games table sits
      # inside `<turbo-frame id="games-index-table">` so sortable headers
      # can partial-swap. Without `data-turbo-frame="_top"` cascading on
      # the bulk-toolbar actions container, the controller-injected
      # `[delete N]` link would navigate the click inside that frame —
      # the deletions confirmation page (a full-page surface from
      # `shared/_action_screen.html.erb`) has no matching frame in its
      # response, so Turbo would render "Content missing".
      it "stamps data-turbo-frame=_top on the bulk-toolbar actions container" do
        get games_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container"
        expect(actions["data-turbo-frame"]).to eq("_top"),
          "bulk-toolbar must escape the games-index-table frame so [delete N] navigates full-page"
      end

      it "honors a sort=title param" do
        create(:game, :synced, title: "Aardvark", igdb_id: 1)
        get games_path, params: { sort: "title", dir: "asc" }
        expect(response).to have_http_status(:ok)
        # Aardvark should appear before Zelda BotW.
        expect(response.body.index("Aardvark")).to be < response.body.index("Zelda BotW")
      end

      it "ignores an unknown sort key (falls back to default)" do
        get games_path, params: { sort: "evil_column; DROP TABLE games --" }
        expect(response).to have_http_status(:ok)
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
  end

  describe "GET /games/:id" do
    let!(:game) { create(:game, :synced, title: "Zelda BotW") }

    it "renders 200" do
      get game_path(game)
      expect(response).to have_http_status(:ok)
    end

    # Phase 14 §1 polish (2026-05-10) — show page now uses the canonical
    # `.pane-row > .pane` two-pane layout (mirrors channels/videos).
    it "renders inside a `.pane-row` of `.pane` children" do
      get game_path(game)
      expect(response.body).to include("pane-row")
      expect(response.body.scan('class="pane"').size).to be >= 2
    end

    it "splits the re-sync caveat onto two lines via <br>" do
      get game_path(game)
      expect(response.body).to include("re-syncing overwrites igdb-sourced fields.<br>")
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
