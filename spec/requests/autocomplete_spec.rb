# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /autocomplete", type: :request do
  # Helper: enroll TOTP and sign in so subsequent requests carry the session cookie.
  def sign_in!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  describe "authenticated user" do
    before { sign_in! }

    it "returns 200 with JSON" do
      post "/autocomplete", params: { input: "/co", cursor: 3 }
      expect(response).to have_http_status(:ok)
    end

    it "includes /config in menu_items labels for /co prefix" do
      post "/autocomplete", params: { input: "/co", cursor: 3 }
      body = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      expect(labels).to include("/config")
    end
  end

  describe "unauthenticated user (no session)" do
    it "returns 200 — allow_anonymous is applied" do
      post "/autocomplete", params: { input: "/", cursor: 1 }
      expect(response).to have_http_status(:ok)
    end

    it "slash menu contains only /login for unauthenticated users" do
      post "/autocomplete", params: { input: "/", cursor: 1 }
      body = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      expect(labels).to eq([ "/login" ])
    end
  end

  describe "auth-gating for dynamic channel suggestions" do
    let!(:channel) { create(:channel, handle: "@testchan") }

    context "when authenticated" do
      before { sign_in! }

      it "returns the channel in menu_items" do
        post "/autocomplete", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        labels = body["menu_items"].map { |i| i["label"] }
        expect(labels).to include("@testchan")
      end
    end

    context "when unauthenticated" do
      it "does NOT return channels in menu_items" do
        post "/autocomplete", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        labels = body["menu_items"].map { |i| i["label"] }
        expect(labels).not_to include("@testchan")
      end
    end
  end

  describe "free-mode ghost text" do
    before { sign_in! }

    it "returns ghost.complete_current == 'oming' for 'list upc'" do
      post "/autocomplete", params: { input: "list upc", cursor: 8 }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("oming")
    end
  end
end
