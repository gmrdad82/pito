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
      expect(response.body).to include("no games yet. [search igdb] to add one.")
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
