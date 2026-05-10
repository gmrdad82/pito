require "rails_helper"
require_relative "../../../app/mcp/tools/game_resync"

RSpec.describe Mcp::Tools::GameResync do
  let!(:game) { create(:game, :synced) }

  it "preview when confirm: no" do
    GameIgdbSync.clear
    described_class.call(id: game.id, confirm: "no")
    expect(GameIgdbSync.jobs).to be_empty
  end

  it "enqueues GameIgdbSync with confirm: yes" do
    GameIgdbSync.clear
    described_class.call(id: game.id, confirm: "yes")
    expect(GameIgdbSync.jobs.last["args"]).to eq([ game.id ])
  end

  it "rejects when game has no igdb_id" do
    g = create(:game)
    g.update_column(:igdb_id, nil)
    result = described_class.call(id: g.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("igdb_id")
  end

  it "404s on missing game" do
    result = described_class.call(id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: game.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: game.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
