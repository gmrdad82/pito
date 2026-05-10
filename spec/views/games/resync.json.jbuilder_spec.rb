require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "games/resync.json.jbuilder", type: :view do
  let(:game) { create(:game) }

  before do
    assign(:game, game)
    assign(:enqueued_jid, "abc123def456")
  end

  let(:json) { JSON.parse(render) }

  it "carries the expected key set" do
    expect(json.keys).to match_array(%w[game_id resyncing enqueued_jid message])
  end

  it "surfaces the Sidekiq jid" do
    expect(json["enqueued_jid"]).to eq("abc123def456")
  end

  it "renders resyncing as the yes string" do
    expect(json["resyncing"]).to eq("yes")
  end
end
