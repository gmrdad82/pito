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
    # Phase 27 v2 spec 01 — singular `genre` replaces the list `genres`.
    expect(json["game"]).to include(
      "id", "slug", "title", "summary", "release_date",
      "release_year", "igdb_rating", "igdb_id",
      "manual_date_override", "resyncing",
      "genre", "platforms_owning", "updated_at"
    )
  end

  it "does NOT carry the legacy multi-genre `genres` list (Phase 27 v2 spec 01)" do
    expect(json["game"]).not_to have_key("genres")
  end

  it "serializes `genre` as the primary genre's name when set" do
    genre = create(:genre, name: "Puzzle", igdb_id: 12_345)
    game.genres << genre
    assign(:game, game.reload)
    expect(JSON.parse(render)["game"]["genre"]).to eq("Puzzle")
  end

  it "serializes `genre` as null when the game has no genres" do
    expect(json["game"]["genre"]).to be_nil
  end

  it "serializes boolean fields as yes/no" do
    expect(json["game"]["resyncing"]).to be_in(%w[yes no])
    expect(json["game"]["manual_date_override"]).to be_in(%w[yes no])
  end
end
