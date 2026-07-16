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

    # The reply-verb position must come back as a verb PALETTE (stage:"tool") with
    # the target's FULL action set — so the client surfaces every verb, not just
    # the first as an inline ghost.
    it "tags the reply-tool stage stage:'tool' with the target's full action set" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(input_kind: :slash, input_text: "list videos", position: 1)
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "vlist-3030", "reply_target" => "video_list", "body" => "videos" }
      )

      post "/suggestions", params: { input: "#vlist-3030 ", cursor: 12, uuid: conversation.uuid }
      body   = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      expect(body["stage"]).to eq("tool")
      expect(labels).to include("with", "without", "schedule", "shinies", "show")
    end

    # `/config ` arg stage returns the provider GROUPS as a drill-down palette
    # (stage:"tool"): three namespace rows whose children are the provider rows.
    it "returns the config provider groups as a drill-down palette for '/config '" do
      post "/suggestions", params: { input: "/config ", cursor: 8 }
      body   = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      expect(body["stage"]).to eq("tool")
      expect(labels).to include("ai", "sources", "profile")
      sources = body["menu_items"].find { |i| i["label"] == "sources" }
      expect(sources["children"].map { |c| c["label"] }).to include("google", "igdb")
    end

    # `/config google ` arg stage returns the per-provider credential keys as a
    # palette (masked secrets stay masked).
    it "returns the per-provider key names as a palette for '/config google '" do
      post "/suggestions", params: { input: "/config google ", cursor: 15 }
      body   = response.parsed_body
      labels = body["menu_items"].map { |i| i["label"] }
      masked = body["menu_items"].select { |i| i["masked"] }.map { |i| i["label"] }
      expect(body["stage"]).to eq("tool")
      expect(labels).to include("client_id", "client_secret", "api_key")
      expect(masked).to include("client_id", "client_secret", "api_key")
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

  describe "non-config slash arg stage returns empty menu_items" do
    let!(:channel) { create(:channel, handle: "@testchan") }

    # Non-config slash args (e.g. /disconnect) return no menu_items — only
    # /config offers a browsable palette.
    context "when authenticated" do
      before { sign_in! }

      it "returns empty menu_items for /disconnect arg stage" do
        post "/suggestions", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        expect(body["menu_items"]).to be_empty
      end
    end

    context "when unauthenticated" do
      it "returns empty menu_items for /disconnect arg stage" do
        post "/suggestions", params: { input: "/disconnect @", cursor: 13 }
        body = response.parsed_body
        expect(body["menu_items"]).to be_empty
      end
    end
  end

  describe "free-mode always returns empty ghost" do
    before { sign_in! }

    it "returns ghost.complete_current == '' for free-mode input 'find upc'" do
      post "/suggestions", params: { input: "find upc", cursor: 8 }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("")
    end

    it "returns ghost.complete_current == '' when partial matches nothing" do
      post "/suggestions", params: { input: "show game zzz", cursor: 13 }
      body = response.parsed_body
      expect(body["ghost"]["complete_current"]).to eq("")
    end
  end
end
