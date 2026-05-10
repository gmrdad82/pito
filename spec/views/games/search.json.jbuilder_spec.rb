require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. The IGDB type-ahead
# endpoint returns HTTP 200 even on upstream failure; the caller
# distinguishes via the `search_error` field (locked decision #8).
RSpec.describe "games/search.json.jbuilder", type: :view do
  let(:json) { JSON.parse(render) }

  context "with results" do
    before do
      assign(:query, "witness")
      assign(:results, [
        {
          "id" => 18811,
          "name" => "The Witness",
          "slug" => "the-witness",
          "first_release_date" => 1453766400,
          "cover" => { "image_id" => "co1abc" },
          "summary" => "A puzzle game."
        }
      ])
      assign(:took_ms, 142.0)
      assign(:search_error, nil)
    end

    it "carries the expected top-level keys" do
      expect(json.keys).to match_array(%w[query results took_ms search_error])
    end

    it "echoes the query" do
      expect(json["query"]).to eq("witness")
    end

    it "renders each result with the trimmed key set" do
      expect(json["results"].first.keys).to match_array(
        %w[igdb_id title release_year cover_image_id summary]
      )
    end

    it "derives release_year from first_release_date" do
      expect(json["results"].first["release_year"]).to eq(2016)
    end

    it "renders search_error as null when nil" do
      expect(json["search_error"]).to be_nil
    end
  end

  context "with an upstream error" do
    before do
      assign(:query, "anything")
      assign(:results, [])
      assign(:took_ms, 0.0)
      assign(:search_error, { kind: "upstream_unavailable", message: "boom" })
    end

    it "carries the error envelope" do
      expect(json["search_error"]).to eq(
        "kind" => "upstream_unavailable",
        "message" => "boom"
      )
    end

    it "renders results as an empty array" do
      expect(json["results"]).to eq([])
    end
  end
end
