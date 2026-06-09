# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Games search endpoint", type: :request do
  # ── Helpers ─────────────────────────────────────────────────────────────────

  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  def igdb_hit(id: 1020, name: "Lies of P")
    { "id" => id, "name" => name, "cover" => { "url" => "//images.igdb.com/igdb/image/upload/t_thumb/abc.jpg" } }
  end

  let(:json) { JSON.parse(response.body) }

  # ── Auth guard ───────────────────────────────────────────────────────────────
  # The app's standard Sessions::AuthConcern redirects unauthenticated requests
  # to the root path rather than returning 401 (no JSON-API style rejection).
  # The search + import controllers do not declare `allow_anonymous`, so an
  # unauthenticated POST is redirected.

  describe "POST /games/search — unauthenticated" do
    it "redirects to root (unauthenticated)" do
      post "/games/search", params: { query: "test" }, as: :json
      expect(response).to redirect_to(root_path)
    end
  end

  # ── Authenticated searches ───────────────────────────────────────────────────

  context "when authenticated" do
    before { login! }

    describe "POST /games/search — successful IGDB call" do
      before do
        allow_any_instance_of(Game::Igdb::Client)
          .to receive(:search_games)
          .and_return([ igdb_hit ])
      end

      it "returns 200" do
        post "/games/search", params: { query: "Lies" }, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "returns hits in the body" do
        post "/games/search", params: { query: "Lies" }, as: :json
        expect(json["hits"].size).to eq(1)
        expect(json["hits"].first["name"]).to eq("Lies of P")
      end

      it "returns null error" do
        post "/games/search", params: { query: "Lies" }, as: :json
        expect(json["error"]).to be_nil
      end
    end

    describe "POST /games/search — re-release type notes" do
      before do
        allow_any_instance_of(Game::Igdb::Client)
          .to receive(:search_games)
          .and_return([
            { "id" => 1, "name" => "Demon's Souls",        "game_type" => 0 },
            { "id" => 2, "name" => "Demon's Souls",        "game_type" => 8 },
            { "id" => 3, "name" => "Dark Souls Remastered", "game_type" => 9 }
          ])
      end

      it "stamps a (remake)/(remaster) note on re-releases, none on main games" do
        post "/games/search", params: { query: "souls" }, as: :json
        hits = json["hits"].index_by { |h| h["id"] }

        expect(hits[1]).not_to have_key("type_note")
        expect(I18n.t("pito.copy.search.remake")).to include(hits[2]["type_note"])
        expect(I18n.t("pito.copy.search.remaster")).to include(hits[3]["type_note"])
      end
    end

    describe "POST /games/search — in-library marker" do
      let!(:existing_game) { create(:game, igdb_id: 1020) }

      before do
        allow_any_instance_of(Game::Igdb::Client)
          .to receive(:search_games)
          .and_return([ igdb_hit(id: 1020, name: "Lies of P"), igdb_hit(id: 9999, name: "Celeste") ])
      end

      it "includes the in-library igdb_id in library_ids" do
        post "/games/search", params: { query: "li" }, as: :json
        expect(json["library_ids"]).to include(1020)
      end

      it "does not include the not-in-library igdb_id" do
        post "/games/search", params: { query: "li" }, as: :json
        expect(json["library_ids"]).not_to include(9999)
      end
    end

    describe "POST /games/search — IGDB upstream error" do
      before do
        allow_any_instance_of(Game::Igdb::Client)
          .to receive(:search_games)
          .and_raise(Game::Igdb::Client::Error, "IGDB unavailable")
      end

      it "returns 200 with an error envelope" do
        post "/games/search", params: { query: "test" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(json["error"]["kind"]).to eq("upstream_unavailable")
        expect(json["hits"]).to eq([])
      end
    end

    describe "POST /games/search — main-titles-only (the module already filters)" do
      before do
        allow_any_instance_of(Game::Igdb::Client)
          .to receive(:search_games)
          .and_return([])  # module already filters; we just assert hits is empty
      end

      it "returns empty hits for an empty module result" do
        post "/games/search", params: { query: "xyz" }, as: :json
        expect(json["hits"]).to eq([])
        expect(json["error"]).to be_nil
      end
    end
  end
end
