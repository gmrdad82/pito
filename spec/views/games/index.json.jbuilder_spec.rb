require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Pin the shape of
# `index.json.jbuilder` so future drift fails loudly.
RSpec.describe "games/index.json.jbuilder", type: :view do
  let(:game) { create(:game, :synced, title: "Index Game", igdb_rating: 80.0) }

  before do
    assign(:json_games, [ game ])
    # Phase 27 §1a — the filter object now carries `platform_owned_slug`
    # (string) instead of the legacy integer `platform_owned_id`.
    assign(:filter, { genre_id: nil, platform_owned_slug: "ps5" })
    assign(:json_sort, { key: "release_year", dir: "desc" })
  end

  let(:json) { JSON.parse(render) }

  it "renders games as an array of summary hashes" do
    expect(json["games"]).to be_an(Array)
    expect(json["games"].first.keys).to match_array(
      %w[id slug title release_year igdb_rating platform_owned_ids
         played_at cover_image_id resyncing igdb_synced_at created_at]
    )
  end

  it "echoes the filter the caller asked for" do
    expect(json["filter"]).to eq("genre_id" => nil, "platform_owned_slug" => "ps5")
  end

  it "echoes the sort the caller asked for" do
    expect(json["sort"]).to eq("key" => "release_year", "dir" => "desc")
  end

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(%w[games filter sort])
  end
end
