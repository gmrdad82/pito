# frozen_string_literal: true

require "rails_helper"

# GET /notifications — returns a Turbo Stream updating #pito-sidebar with the
# notifications list wrapped in the Sidebar shell.

RSpec.describe "GET /notifications", type: :request do
  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.create!.uuid }
  end

  # ── Authenticated path ──────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "returns 200 OK" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end

    it "responds with turbo-stream content type" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
    end

    it "targets pito-sidebar in the turbo stream" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "renders the aside sidebar shell" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("<aside")
    end

    it "includes notification messages when notifications exist" do
      create(:notification, message: "Hello from test")
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("Hello from test")
    end

    it "renders the empty state when there are no notifications" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("No notifications")
    end

    it "renders the Notifications title" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("Notifications")
    end
  end

  # ── Unauthenticated path ────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root (auth gate)" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to redirect_to(root_path)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).not_to include('target="pito-sidebar"')
    end
  end
end
