# frozen_string_literal: true

require "rails_helper"

# GET /games/picker — the picker's keyset pager (turbo append + sentinel
# replace) and the TUI's JSON picker feed. Mirrors resume_json_spec's auth
# convention.
RSpec.describe "GET /games/picker", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
  end

  describe "authenticated" do
    before do
      stub_const("Game::PICKER_PAGE_SIZE", 2)
      3.times { |i| create(:game, title: "Game #{i}") }
      authenticate_via_totp
    end

    it "JSON: pages rows with a terminal null cursor and exact keys" do
      get "/games/picker", headers: { "Accept" => "application/json" }
      body = response.parsed_body
      expect(body["rows"].size).to eq(2)
      expect(body["rows"].first.keys).to match_array(%w[id title])
      expect(body["next_cursor"]).to be_present

      get "/games/picker", params: { after: body["next_cursor"] },
                          headers: { "Accept" => "application/json" }
      last = response.parsed_body
      expect(last["rows"].size).to eq(1)
      expect(last["next_cursor"]).to be_nil
      expect((body["rows"] + last["rows"]).map { |r| r["id"] }.uniq.size).to eq(3)
    end

    it "JSON: q= filters by title (search-local ILIKE) and still pages the keyset" do
      get "/games/picker", params: { q: "game" },
                         headers: { "Accept" => "application/json" }
      body = response.parsed_body
      expect(body["rows"].size).to eq(2)
      expect(body["next_cursor"]).to be_present

      get "/games/picker", params: { q: "game", after: body["next_cursor"] },
                         headers: { "Accept" => "application/json" }
      expect(response.parsed_body["rows"].size).to eq(1)
      expect(response.parsed_body["next_cursor"]).to be_nil

      get "/games/picker", params: { q: "no-such-title" },
                         headers: { "Accept" => "application/json" }
      expect(response.parsed_body["rows"]).to eq([])
      expect(response.parsed_body["next_cursor"]).to be_nil
    end

    it "turbo: appends into the rows container and replaces the sentinel" do
      get "/games/picker", headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include('action="append" target="pito-games-picker-rows"')
      expect(response.body).to include(Pito::ListPager::SentinelComponent::SENTINEL_ID)
    end
  end

  it "anonymous JSON → 401" do
    get "/games/picker", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
