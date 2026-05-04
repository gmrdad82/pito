require "rails_helper"

RSpec.describe "Games", type: :request do
  describe "GET /games" do
    it "returns 200" do
      get games_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /games" do
    it "default-creates a game" do
      expect {
        post games_path
      }.to change(Game, :count).by(1)
      expect(Game.last.title).to eq("Untitled game")
    end
  end

  describe "PATCH /games/:id" do
    let!(:game) { create(:game) }

    it "renames the title" do
      patch game_path(game), params: { game: { title: "Halo Infinite" } }
      expect(game.reload.title).to eq("Halo Infinite")
    end

    it "accepts a JSON platforms_json string" do
      payload = [ { "platform" => "PC", "owned" => true, "recorded_on" => true } ].to_json
      patch game_path(game), params: { game: { platforms_json: payload } }
      expect(game.reload.platforms.first["platform"]).to eq("PC")
    end
  end
end
