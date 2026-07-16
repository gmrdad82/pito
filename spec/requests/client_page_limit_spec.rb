# frozen_string_literal: true

require "rails_helper"

# ApplicationController#client_page_limit is the ONE mechanism behind every
# pito-tui viewport-driven `limit` param (owner 2026-07-15). It is called from
# exactly three places — NotificationsController#index (tool: :notifications),
# ConversationsController#resume (tool: :resume), and
# Games::SearchController#create (tool: :games) — and nowhere else
# (`grep -rn max_page_size app lib` confirms `Pito::Dispatch::Config.max_page_size`
# has no other caller). This spec pins the SAME clamp matrix — absent, zero,
# negative, over-cap, in-range, invalid `limit`, plus cursor continuity across
# a limit change where the endpoint exposes a cursor — across all three.
#
# POST /games/search is a one-shot IGDB lookup with no cursor (`hits:` only,
# no `next_cursor:`), so the cursor-continuity case is skipped there.
#
# The chat: :search tool (config/pito/tools.yml `search:` block, "search
# games like <title>") is a DIFFERENT thing — a free-chat similarity search
# with its own pager — and never calls client_page_limit; it is out of scope
# here.
#
# notifications_json_spec.rb and resume_json_spec.rb already cover response
# SHAPE (row keys, ai flags, unread counts, turbo_stream branches); this file
# only pins the `limit` clamp mechanics, reusing their auth helper/factories.

RSpec.describe "client_page_limit clamp matrix", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  # ── GET /notifications.json (tool: :notifications) ─────────────────────────
  describe "GET /notifications.json" do
    def notifications_page(params = {})
      get "/notifications", params: params, headers: { "Accept" => "application/json" }
      response.parsed_body
    end

    it "uses Notification::PAGE_SIZE when limit is absent" do
      stub_const("Notification::PAGE_SIZE", 3)
      login!
      create_list(:notification, 5)

      expect(notifications_page["rows"].size).to eq(3)
    end

    it "clamps limit=0 up to 1" do
      login!
      create_list(:notification, 3)

      expect(notifications_page(limit: 0)["rows"].size).to eq(1)
    end

    it "clamps a negative limit up to 1" do
      login!
      create_list(:notification, 3)

      expect(notifications_page(limit: -7)["rows"].size).to eq(1)
    end

    it "clamps an over-cap limit down to the :notifications tool's configured max_page_size" do
      allow(Pito::Dispatch::Config).to receive(:max_page_size).with(tool: :notifications).and_return(4)
      login!
      create_list(:notification, 6)

      expect(notifications_page(limit: 999_999)["rows"].size).to eq(4)
    end

    it "honors a valid in-range limit verbatim" do
      login!
      create_list(:notification, 5)

      expect(notifications_page(limit: 3)["rows"].size).to eq(3)
    end

    it "falls back to Notification::PAGE_SIZE when limit is non-integer" do
      stub_const("Notification::PAGE_SIZE", 2)
      login!
      create_list(:notification, 4)

      expect(notifications_page(limit: "abc")["rows"].size).to eq(2)
    end

    it "advances the cursor correctly across a limit change with no dropped or duplicated rows" do
      login!
      create_list(:notification, 5)

      first = notifications_page(limit: 2)
      expect(first["rows"].size).to eq(2)
      expect(first["next_cursor"]).to be_present

      second = notifications_page(after: first["next_cursor"], limit: 3)
      expect(second["rows"].size).to eq(3)
      expect(second["next_cursor"]).to be_nil

      first_ids  = first["rows"].map { |r| r["id"] }
      second_ids = second["rows"].map { |r| r["id"] }
      expect(first_ids & second_ids).to be_empty
      expect((first_ids + second_ids).uniq.size).to eq(5)
    end
  end

  # ── GET /resume.json (tool: :resume) ────────────────────────────────────────
  describe "GET /resume.json" do
    def resume_page(params = {})
      get "/resume", params: params, headers: { "Accept" => "application/json" }
      response.parsed_body
    end

    # Page 1 answers { recent:, older:, ... }; a follow-up (?after=) answers a
    # flat { rows:, ... } — see ConversationsController#resume.
    def row_uuids(body)
      if body.key?("rows")
        body["rows"].map { |r| r["uuid"] }
      else
        (body["recent"] + body["older"]).map { |r| r["uuid"] }
      end
    end

    it "uses Conversation::SIDEBAR_PAGE_SIZE when limit is absent" do
      stub_const("Conversation::SIDEBAR_PAGE_SIZE", 3)
      login! # one baseline conversation
      create_list(:conversation, 5)

      expect(row_uuids(resume_page).size).to eq(3)
    end

    it "clamps limit=0 up to 1" do
      login!
      create_list(:conversation, 3)

      expect(row_uuids(resume_page(limit: 0)).size).to eq(1)
    end

    it "clamps a negative limit up to 1" do
      login!
      create_list(:conversation, 3)

      expect(row_uuids(resume_page(limit: -9)).size).to eq(1)
    end

    it "clamps an over-cap limit down to the :resume tool's configured max_page_size" do
      allow(Pito::Dispatch::Config).to receive(:max_page_size).with(tool: :resume).and_return(4)
      login!
      create_list(:conversation, 6)

      expect(row_uuids(resume_page(limit: 999_999)).size).to eq(4)
    end

    it "honors a valid in-range limit verbatim" do
      login!
      create_list(:conversation, 5)

      expect(row_uuids(resume_page(limit: 4)).size).to eq(4)
    end

    it "falls back to Conversation::SIDEBAR_PAGE_SIZE when limit is non-integer" do
      stub_const("Conversation::SIDEBAR_PAGE_SIZE", 2)
      login!
      create_list(:conversation, 4)

      expect(row_uuids(resume_page(limit: "abc")).size).to eq(2)
    end

    it "advances the cursor correctly across limit changes with no dropped or duplicated rows" do
      login! # + 5 created below = 6 conversations total
      create_list(:conversation, 5)
      expect(Conversation.count).to eq(6)

      page1 = resume_page(limit: 2)
      expect(row_uuids(page1).size).to eq(2)
      expect(page1["next_cursor"]).to be_present

      page2 = resume_page(after: page1["next_cursor"], limit: 3)
      expect(row_uuids(page2).size).to eq(3)
      expect(page2["next_cursor"]).to be_present

      page3 = resume_page(after: page2["next_cursor"], limit: 10)
      expect(row_uuids(page3).size).to eq(1)
      expect(page3["next_cursor"]).to be_nil

      all_uuids = row_uuids(page1) + row_uuids(page2) + row_uuids(page3)
      expect(all_uuids.uniq.size).to eq(6)
    end
  end

  # ── POST /games/search (tool: :games) ───────────────────────────────────────
  # A one-shot IGDB lookup (`hits:` only, no cursor) — cursor continuity does
  # not apply here, unlike the two keyset-paged endpoints above. Clamp
  # behavior is observed via the `limit:` handed to Game::Igdb::Client
  # (stubbed, per games_search_spec.rb's own pattern), never real network.
  #
  # Distinct wire shape from the two GET endpoints above: this controller's
  # doc comment documents the contract as a JSON body `{ "query": ...,
  # "limit": 25 }` — a bare JSON number, which Rails parses into a real Ruby
  # Integer (confirmed: `JSON.parse({limit: 0}.to_json)["limit"].class
  # #=> Integer`), NOT the String a query-string param always is. This spec
  # pins that a JSON-NUMBER `limit` clamps identically to a String one:
  # `client_page_limit` normalizes with `.to_s` before `Integer(_, 10)`
  # (application_controller.rb) precisely so this endpoint's documented
  # numeric wire shape reaches the clamp. (A prior `Integer(raw, 10)` on the
  # raw Integer raised "base specified for non string value" and silently
  # dropped every numeric limit to the default — the last example proves the
  # String shape still works too.)
  describe "POST /games/search" do
    def search!(query:, limit: nil)
      params = { query: query }
      params[:limit] = limit unless limit.nil?
      post "/games/search", params: params, as: :json
    end

    def expect_search_limit(value)
      expect_any_instance_of(Game::Igdb::Client)
        .to receive(:search_games)
        .with(anything, limit: value)
        .and_return([])
    end

    it "uses IgdbGames::DEFAULT_LIMIT when limit is absent" do
      login!
      expect_search_limit(Pito::Search::Modules::IgdbGames::DEFAULT_LIMIT)

      search!(query: "clamp-matrix-absent")

      expect(response).to have_http_status(:ok)
    end

    it "clamps limit=0 up to 1 (sent as a JSON number)" do
      login!
      expect_search_limit(1)

      search!(query: "clamp-matrix-zero", limit: 0)

      expect(response).to have_http_status(:ok)
    end

    it "clamps a negative limit up to 1 (sent as a JSON number)" do
      login!
      expect_search_limit(1)

      search!(query: "clamp-matrix-negative", limit: -3)

      expect(response).to have_http_status(:ok)
    end

    it "clamps an over-cap limit down to the :games tool's max_page_size" do
      allow(Pito::Dispatch::Config).to receive(:max_page_size).with(tool: :games).and_return(5)
      login!
      expect_search_limit(5)

      search!(query: "clamp-matrix-over-cap", limit: 999_999)

      expect(response).to have_http_status(:ok)
    end

    it "honors a valid in-range limit verbatim (sent as a JSON number)" do
      login!
      expect_search_limit(7)

      search!(query: "clamp-matrix-in-range", limit: 7)

      expect(response).to have_http_status(:ok)
    end

    it "falls back to the default when limit is a non-integer string" do
      login!
      expect_search_limit(Pito::Search::Modules::IgdbGames::DEFAULT_LIMIT)

      search!(query: "clamp-matrix-invalid", limit: "abc")

      expect(response).to have_http_status(:ok)
    end

    it "clamps the same way when limit arrives as a String query param on the POST" do
      login!
      expect_search_limit(7)

      post "/games/search?limit=7", params: { query: "clamp-matrix-string-limit" }, as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
