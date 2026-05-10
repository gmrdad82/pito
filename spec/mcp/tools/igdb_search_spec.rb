require "rails_helper"
require_relative "../../../app/mcp/tools/igdb_search"

RSpec.describe Mcp::Tools::IgdbSearch do
  let(:fake_client) { instance_double(Igdb::Client) }

  before do
    allow(Igdb::Client).to receive(:new).and_return(fake_client)
  end

  it "proxies to Igdb::Client#search_games and returns IGDB hits" do
    allow(fake_client).to receive(:search_games)
      .with("zelda", limit: 10, include_editions: false)
      .and_return([
        { "id" => 7346, "name" => "Zelda BotW", "slug" => "zelda-botw",
          "first_release_date" => 1488499200 }
      ])

    result = described_class.call(q: "zelda")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed.first["igdb_id"]).to eq(7346)
    expect(parsed.first["name"]).to eq("Zelda BotW")
  end

  it "respects the limit param (clamped 1..25)" do
    allow(fake_client).to receive(:search_games)
      .with("zelda", limit: 5, include_editions: false)
      .and_return([])
    described_class.call(q: "zelda", limit: 5)
  end

  # Phase 14 §1 polish (2026-05-10) — `include_editions: yes/no` opt-in
  # disables the default "main entries" category filter so power users
  # can ask for every IGDB hit (deluxe / ultimate / definitive editions
  # included). MCP I/O sticks to "yes"/"no" strings per CLAUDE.md.
  it "passes include_editions: true when the caller opts in with 'yes'" do
    allow(fake_client).to receive(:search_games)
      .with("pragmata", limit: 10, include_editions: true)
      .and_return([])
    described_class.call(q: "pragmata", include_editions: "yes")
  end

  it "defaults to include_editions: false (filtered) when omitted" do
    allow(fake_client).to receive(:search_games)
      .with("pragmata", limit: 10, include_editions: false)
      .and_return([])
    described_class.call(q: "pragmata")
  end

  it "rejects a non-yes/no include_editions value" do
    result = described_class.call(q: "pragmata", include_editions: "true")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("yes")
  end

  it "rejects empty q" do
    result = described_class.call(q: "")
    expect(result.to_h[:isError]).to be(true)
  end

  it "surfaces Igdb::Client::Error as a clean error response" do
    allow(fake_client).to receive(:search_games).and_raise(Igdb::Client::Error.new("rate limited"))
    result = described_class.call(q: "x")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("rate limited")
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(q: "anything")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
