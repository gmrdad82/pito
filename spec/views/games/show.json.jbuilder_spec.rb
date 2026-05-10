require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Pin the shape of
# `show.json.jbuilder`.
RSpec.describe "games/show.json.jbuilder", type: :view do
  let(:game) { create(:game, :synced, title: "Show Game") }

  before { assign(:game, game) }

  let(:json) { JSON.parse(render) }

  it "wraps the detail under :game" do
    expect(json.keys).to eq([ "game" ])
  end

  it "carries the detail key set" do
    expect(json["game"]).to include(
      "id", "slug", "title", "summary", "release_date",
      "release_year", "igdb_rating", "igdb_id",
      "manual_date_override", "resyncing",
      "genres", "platforms_owning", "updated_at"
    )
  end

  it "serializes boolean fields as yes/no" do
    expect(json["game"]["resyncing"]).to be_in(%w[yes no])
    expect(json["game"]["manual_date_override"]).to be_in(%w[yes no])
  end
end
