# frozen_string_literal: true

require "rails_helper"

# GET /resume.json — the conversation picker for non-browser clients
# (pito-tui): the same keyset-paged rows the sidebar renders, as data.

RSpec.describe "GET /resume.json", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  # An :ai event on `conversation` — with its own turn scoped to the SAME
  # conversation (the turn factory otherwise mints a stray conversation of
  # its own, which would silently throw off the row counts below).
  def add_ai_event!(conversation)
    create(:event, conversation: conversation, turn: create(:turn, conversation: conversation), kind: "ai")
  end

  it "returns page 1 with recent/older groups, ai flags, and a next_cursor" do
    stub_const("Conversation::SIDEBAR_PAGE_SIZE", 2)
    login! # creates the oldest conversation of the three below
    ai_conv = Conversation.create!(title: "with-ai")
    add_ai_event!(ai_conv)
    named = Conversation.create!(title: "android") # newest — guaranteed on page 1

    get "/resume", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[recent older notifications next_cursor])

    # G125: identity + unread ride beside the groups.
    expect(body["notifications"]["unread"]).to eq(Notification.unread.count)

    rows = body["recent"] + body["older"]
    expect(rows.size).to eq(2) # capped at the stubbed SIDEBAR_PAGE_SIZE — the
    # oldest (login) conversation is left off page 1, which is what makes
    # next_cursor present below.

    row = rows.find { |r| r["uuid"] == named.uuid }
    expect(row["title"]).to eq("android")
    expect(row["display_name"]).to eq("android")
    expect(row.keys).to match_array(%w[uuid title display_name last_activity_at ai])
    expect(row["ai"]).to eq(false)

    ai_row = rows.find { |r| r["uuid"] == ai_conv.uuid }
    expect(ai_row["ai"]).to eq(true)

    expect(body["next_cursor"]).to be_present
  end

  it "does not error on a stray limit param" do
    login!
    Conversation.create!

    get "/resume", params: { limit: 10 }, headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
  end

  describe "pagination (?after=)" do
    it "returns a flat rows array with ai flags and a terminal null cursor" do
      stub_const("Conversation::SIDEBAR_PAGE_SIZE", 2)
      login! # oldest of the four conversations below
      older_ai = Conversation.create!(title: "older-ai")
      add_ai_event!(older_ai)
      Conversation.create! # newer than older_ai
      Conversation.create! # newest — page 1's top row

      get "/resume", headers: { "Accept" => "application/json" }
      cursor = response.parsed_body["next_cursor"]
      expect(cursor).to be_present

      get "/resume", params: { after: cursor }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to match_array(%w[rows next_cursor])

      # The remaining two (older_ai + the login conversation) fill this page
      # exactly, so it is the last one.
      row = body["rows"].find { |r| r["uuid"] == older_ai.uuid }
      expect(row).to be_present
      expect(row.keys).to match_array(%w[uuid title display_name last_activity_at ai])
      expect(row["ai"]).to eq(true)

      expect(body["next_cursor"]).to be_nil
    end
  end

  it "rejects anonymous with 401" do
    get "/resume", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("unauthenticated")
  end
end
