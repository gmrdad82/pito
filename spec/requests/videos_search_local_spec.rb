# frozen_string_literal: true

require "rails_helper"

# POST /videos/search-local — local DB search returning HTML rows for the
# videos picker sidebar.

RSpec.describe "POST /videos/search-local", type: :request do
  let!(:channel)      { create(:channel, handle: "gmrdad82") }
  let!(:lop_vid)      { create(:video, title: "Lies of P Playthrough", channel: channel) }
  let!(:hk_vid)       { create(:video, title: "Hollow Knight 100%", channel: channel) }
  let!(:celeste_vid)  { create(:video, title: "Celeste Any%", channel: channel) }

  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  # ── Auth guard ────────────────────────────────────────────────────────────────

  describe "unauthenticated" do
    it "redirects to root" do
      post "/videos/search-local", params: { q: "Lies" }
      expect(response).to redirect_to(root_path)
    end
  end

  # ── Authenticated ─────────────────────────────────────────────────────────────

  context "when authenticated" do
    before { login! }

    it "returns 200 with HTML content" do
      post "/videos/search-local", params: { q: "Lies" }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "returns matching .pito-video-row elements" do
      post "/videos/search-local", params: { q: "Lies" }
      expect(response.body).to include("pito-video-row")
      expect(response.body).to include("Lies of P Playthrough")
    end

    it "excludes non-matching videos" do
      post "/videos/search-local", params: { q: "Lies" }
      expect(response.body).not_to include("Hollow Knight 100%")
    end

    it "is case-insensitive" do
      post "/videos/search-local", params: { q: "hollow knight" }
      expect(response.body).to include("Hollow Knight 100%")
    end

    it "returns all videos (up to 50) when q is blank" do
      post "/videos/search-local", params: { q: "" }
      expect(response.body).to include("Lies of P Playthrough")
      expect(response.body).to include("Hollow Knight 100%")
      expect(response.body).to include("Celeste Any%")
    end

    it "embeds data-video-id on each row" do
      post "/videos/search-local", params: { q: "Celeste" }
      expect(response.body).to include("data-video-id=\"#{celeste_vid.id}\"")
    end

    it "renders the channel @handle in each row" do
      post "/videos/search-local", params: { q: "Lies" }
      expect(response.body).to include("@gmrdad82")
    end

    it "returns no rows when nothing matches" do
      post "/videos/search-local", params: { q: "NoMatchXYZ" }
      expect(response.body).not_to include("pito-video-row")
    end
  end
end
