require "rails_helper"
require_relative "../../../app/mcp/tools/game_add_from_igdb"

RSpec.describe Mcp::Tools::GameAddFromIgdb do
  it "preview when confirm: no — does not create" do
    expect {
      described_class.call(igdb_id: 7346, confirm: "no")
    }.not_to change(Game, :count)
  end

  it "preview when confirm omitted (defaults to no)" do
    result = described_class.call(igdb_id: 7346)
    expect(result.content.first[:text]).to include("preview")
  end

  it "creates a Game and enqueues GameIgdbSync with confirm: yes" do
    GameIgdbSync.clear if defined?(GameIgdbSync)
    expect {
      described_class.call(igdb_id: 7346, confirm: "yes")
    }.to change(Game, :count).by(1)
    expect(GameIgdbSync.jobs.last["args"]).to eq([ Game.last.id ])
  end

  it "no-ops on a duplicate IGDB id with a clean 'already in library' message" do
    create(:game, igdb_id: 7346)
    expect {
      described_class.call(igdb_id: 7346, confirm: "yes")
    }.not_to change(Game, :count)
  end

  it "rejects confirm: true (boolean) with a clear error" do
    result = described_class.call(igdb_id: 7346, confirm: true)
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to match(/confirm.*yes.*no/i)
  end

  it "rejects negative igdb_id" do
    result = described_class.call(igdb_id: -1, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(igdb_id: 7346, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
