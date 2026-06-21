# frozen_string_literal: true

require "rails_helper"

# POST /games/search-local — local DB search returning HTML rows for the
# games picker sidebar.

RSpec.describe "POST /games/search-local", type: :request do
  let!(:lies_of_p)    { create(:game, title: "Lies of P") }
  let!(:hollow_knight) { create(:game, title: "Hollow Knight") }
  let!(:celeste)       { create(:game, title: "Celeste") }

  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  # ── Auth guard ────────────────────────────────────────────────────────────────

  describe "unauthenticated" do
    it "redirects to root" do
      post "/games/search-local", params: { q: "Lies" }
      expect(response).to redirect_to(root_path)
    end
  end

  # ── Authenticated ─────────────────────────────────────────────────────────────

  context "when authenticated" do
    before { login! }

    it "returns 200 with HTML content" do
      post "/games/search-local", params: { q: "Lies" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "returns matching .pito-game-row elements" do
      post "/games/search-local", params: { q: "Lies" }
      expect(response.body).to include("pito-game-row")
      expect(response.body).to include("Lies of P")
    end

    it "excludes non-matching games" do
      post "/games/search-local", params: { q: "Lies" }
      expect(response.body).not_to include("Hollow Knight")
    end

    it "is case-insensitive" do
      post "/games/search-local", params: { q: "lies of p" }
      expect(response.body).to include("Lies of P")
    end

    it "returns all games (up to 50) when q is blank" do
      post "/games/search-local", params: { q: "" }
      expect(response.body).to include("Lies of P")
      expect(response.body).to include("Hollow Knight")
      expect(response.body).to include("Celeste")
    end

    it "embeds data-game-id on each row" do
      post "/games/search-local", params: { q: "Celeste" }
      expect(response.body).to include("data-game-id=\"#{celeste.id}\"")
    end

    it "returns no rows when nothing matches" do
      post "/games/search-local", params: { q: "NoMatchXYZ" }
      expect(response.body).not_to include("pito-game-row")
    end
  end
end
