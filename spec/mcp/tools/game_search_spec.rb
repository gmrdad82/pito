require "rails_helper"
require_relative "../../../app/mcp/tools/game_search"

RSpec.describe Mcp::Tools::GameSearch do
  it "returns matching games as JSON" do
    create(:game, title: "Zelda BotW")
    create(:game, title: "Elden Ring")
    create(:game, title: "Doom Eternal")
    result = described_class.call(q: "elden")
    text = result.content.first[:text]
    parsed = JSON.parse(text)
    expect(parsed.map { |r| r["title"] }).to eq([ "Elden Ring" ])
  end

  it "returns an empty array on no match" do
    result = described_class.call(q: "nope nope")
    expect(JSON.parse(result.content.first[:text])).to eq([])
  end

  it "rejects an empty query" do
    result = described_class.call(q: "  ")
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(q: "anything")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "schema declares additionalProperties false" do
    schema = described_class.input_schema.to_h
    expect(schema[:additionalProperties]).to eq(false).or eq("false")
  end
end
