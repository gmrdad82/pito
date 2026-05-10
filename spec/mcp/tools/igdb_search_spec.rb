require "rails_helper"
require_relative "../../../app/mcp/tools/igdb_search"

RSpec.describe Mcp::Tools::IgdbSearch do
  let(:fake_client) { instance_double(Igdb::Client) }

  before do
    allow(Igdb::Client).to receive(:new).and_return(fake_client)
  end

  it "proxies to Igdb::Client#search_games and returns IGDB hits" do
    allow(fake_client).to receive(:search_games)
      .with("zelda", limit: 10)
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
      .with("zelda", limit: 5)
      .and_return([])
    described_class.call(q: "zelda", limit: 5)
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
