# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /suggestions", type: :request do
  # Helper: enroll TOTP and sign in so subsequent requests carry the session cookie.
  def sign_in!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  describe "authenticated user" do
    before { sign_in! }

    it "returns 200 with JSON" do
      post "/suggestions", params: { input: "/co", cursor: 3 }
      expect(response).to have_http_status(:ok)
    end

    it "includes /config in menu_items labels for /co prefix" do
      post "/suggestions", params: { input: "/co", cursor: 3 }
      body = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      expect(labels).to include("/config")
    end

    # Smoke #6 root cause: the chatbox posts the conversation as `uuid`. The
    # controller must resolve it so the engine can map a #handle to its
    # follow-up target — otherwise it falls back to the legacy "add" verbs.
    it "suggests the follow-up target's actions (not legacy add) for a live #handle via uuid" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(input_kind: :chat, input_text: "show game x", position: 1)
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "upsilon-7576", "reply_target" => "game_detail", "body" => "x" }
      )

      post "/suggestions", params: { input: "#upsilon-7576 ", cursor: 14, uuid: conversation.uuid }
      labels = response.parsed_body["menu_items"].map { |i| i["label"] }
      expect(labels).to include("rm", "reindex")
      expect(labels).not_to include("add")
    end
  end

  describe "unauthenticated user (no session)" do
    it "returns 200 — allow_anonymous is applied" do
      post "/suggestions", params: { input: "/", cursor: 1 }
      expect(response).to have_http_status(:ok)
    end

    it "slash menu contains only /login for unauthenticated users" do
      post "/suggestions", params: { input: "/", cursor: 1 }
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
        post "/suggestions", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        labels = body["menu_items"].map { |i| i["label"] }
        expect(labels).to include("@testchan")
      end
    end

    context "when unauthenticated" do
      it "does NOT return channels in menu_items" do
        post "/suggestions", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        labels = body["menu_items"].map { |i| i["label"] }
        expect(labels).not_to include("@testchan")
      end
    end
  end

  describe "free-mode ghost text" do
    before { sign_in! }

    it "returns ghost.complete_current == 'oming' for 'find upc'" do
      post "/suggestions", params: { input: "find upc", cursor: 8 }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("oming")
    end
  end

  describe "game-title ghost (T10.5)" do
    before { sign_in! }

    let!(:lies_of_p) { create(:game, title: "Lies of P") }

    it "returns ghost completing 'li' → 'es of P' for 'show game li'" do
      input = "show game li"
      post "/suggestions", params: { input: input, cursor: input.length }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("es of P")
    end

    it "returns ghost completing 'li' → 'es of P' for 'delete game li'" do
      input = "delete game li"
      post "/suggestions", params: { input: input, cursor: input.length }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("es of P")
    end

    it "returns empty ghost when partial matches nothing" do
      input = "show game zzz"
      post "/suggestions", params: { input: input, cursor: input.length }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("")
    end
  end
end
