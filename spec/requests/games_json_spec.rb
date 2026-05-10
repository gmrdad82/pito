require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Exhaustive matrix
# for the games JSON surface: happy / sad / edge / flaw per endpoint.
RSpec.describe "Games JSON", type: :request do
  let(:game) { create(:game, :synced, title: "Witness", igdb_slug: "the-witness") }
  let(:json) { JSON.parse(response.body) }

  describe "GET /games.json" do
    before { game } # ensure persistence

    it "returns 200 with the expected envelope (happy)" do
      get "/games.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[games filter sort])
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/games.json"
      expect(response).to redirect_to(login_path)
    end

    it "echoes the requested sort (edge: descending release_year)" do
      get "/games.json?sort=release_year&dir=desc"
      expect(json["sort"]).to eq("key" => "release_year", "dir" => "desc")
    end

    it "echoes the requested filter (edge: genre)" do
      genre = create(:genre, name: "Puzzle")
      game.genres << genre
      get "/games.json?genre=#{genre.id}"
      expect(json["filter"]["genre_id"]).to eq(genre.id)
    end

    it "falls back to the default sort when given an unknown key (flaw)" do
      get "/games.json?sort=__nope__&dir=evil"
      expect(json["sort"]).to eq("key" => "created_at", "dir" => "desc")
    end

    it "returns an empty games list when no rows exist (edge)" do
      Game.delete_all
      get "/games.json"
      expect(json["games"]).to eq([])
    end

    it "renders boolean fields as yes/no strings" do
      get "/games.json"
      expect(json["games"].first["resyncing"]).to be_in(%w[yes no])
    end
  end

  describe "GET /games/:id.json" do
    it "resolves a canonical slug (happy)" do
      get "/games/#{game.igdb_slug}.json"
      expect(response).to have_http_status(:ok)
      expect(json["game"]["id"]).to eq(game.id)
    end

    it "301-redirects integer-id to the canonical slug (edge)" do
      get "/games/#{game.id}.json"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers["Location"]).to include("/games/#{game.igdb_slug}")
    end

    it "following the redirect returns 200 with the detail shape" do
      get "/games/#{game.id}.json"
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(json["game"]["slug"]).to eq(game.igdb_slug)
    end

    it "rejects an unknown slug with 404 + JSON envelope (sad)" do
      get "/games/__nope__.json"
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "Not found")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/games/#{game.igdb_slug}.json"
      expect(response).to redirect_to(login_path)
    end

    it "pins the detail key set (wire-shape snapshot)" do
      get "/games/#{game.igdb_slug}.json"
      expect(json["game"].keys).to include(
        "id", "slug", "title", "summary", "release_date", "release_year",
        "igdb_rating", "manual_date_override", "resyncing", "genres",
        "platforms_owning"
      )
    end
  end

  describe "POST /games/:id/resync.json" do
    it "returns 202 + jid when not already resyncing (happy)" do
      allow(GameIgdbSync).to receive(:perform_async).and_return("abc123")
      post "/games/#{game.igdb_slug}/resync.json"
      expect(response).to have_http_status(:accepted)
      expect(json).to include(
        "game_id" => game.id,
        "resyncing" => "yes",
        "enqueued_jid" => "abc123"
      )
    end

    it "returns 409 when already resyncing (flaw: race)" do
      game.update!(resyncing: true)
      post "/games/#{game.igdb_slug}/resync.json"
      expect(response).to have_http_status(:conflict)
      expect(json).to eq(
        "game_id" => game.id,
        "resyncing" => "yes",
        "error" => "already_resyncing"
      )
    end

    it "rejects unknown id with 404 (sad)" do
      post "/games/__nope__/resync.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /games/search.json" do
    let(:client) { instance_double(Igdb::Client) }

    before { allow(Igdb::Client).to receive(:new).and_return(client) }

    it "returns 200 with results (happy)" do
      allow(client).to receive(:search_games).and_return([
        {
          "id" => 18811, "name" => "The Witness",
          "first_release_date" => 1453766400,
          "cover" => { "image_id" => "co1abc" },
          "summary" => "puzzle"
        }
      ])
      get "/games/search.json?q=witness"
      expect(response).to have_http_status(:ok)
      expect(json["query"]).to eq("witness")
      expect(json["results"].first["title"]).to eq("The Witness")
      expect(json["search_error"]).to be_nil
    end

    it "returns 200 with empty results when q is empty (edge)" do
      get "/games/search.json?q="
      expect(response).to have_http_status(:ok)
      expect(json["results"]).to eq([])
      expect(json["took_ms"]).to eq(0.0)
    end

    it "truncates q to MAX_QUERY_LENGTH (flaw: oversized)" do
      allow(client).to receive(:search_games).and_return([])
      oversize = "x" * 200
      get "/games/search.json?q=#{oversize}"
      expect(response).to have_http_status(:ok)
      expect(json["query"].length).to eq(GamesController::MAX_QUERY_LENGTH)
    end

    it "returns 200 with search_error on upstream failure (locked #8)" do
      allow(client).to receive(:search_games).and_raise(Igdb::Client::Error, "boom")
      get "/games/search.json?q=witness"
      expect(response).to have_http_status(:ok)
      expect(json["results"]).to eq([])
      expect(json["search_error"]).to eq(
        "kind" => "upstream_unavailable",
        "message" => "boom"
      )
    end

    it "carries the took_ms field (happy)" do
      allow(client).to receive(:search_games).and_return([])
      get "/games/search.json?q=witness"
      expect(json).to have_key("took_ms")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/games/search.json?q=witness"
      expect(response).to redirect_to(login_path)
    end
  end
end
