require "rails_helper"

# 2026-05-19 — Games::SearchService omnisearch dispatcher.
#
# This spec locks the "always-search-both" contract introduced when
# IGDB stopped being lazy: every `:bundle_add` and `:games_search`
# dispatch ALWAYS calls IGDB (independent of local hit count) so the
# user can compare local hits against the live IGDB index. The Rule 1
# dedup-by-igdb_id post-filter is what keeps the IGDB pane from
# re-listing rows the user already imported locally.
#
# `:game_index` mode stays IGDB-only and is not affected by this
# contract (no local corpus is queried).
#
# Stubbing strategy:
#   - `Search::Omnisearch.call` is stubbed at the dispatcher boundary
#     to control the local-half result envelope without booting
#     Meilisearch.
#   - `Igdb::Client.new` returns an instance double whose
#     `#search_games` we drive directly (mirrors `requests/games_json_spec`).
RSpec.describe Games::SearchService do
  let(:igdb_client) { instance_double(Igdb::Client) }

  before { allow(Igdb::Client).to receive(:new).and_return(igdb_client) }

  def igdb_row(id:, name: "X")
    { "id" => id, "name" => name }
  end

  describe ".call validation" do
    it "raises ArgumentError on an unknown mode" do
      expect { described_class.call(query: "x", mode: :nope) }
        .to raise_error(ArgumentError, /unknown mode/)
    end
  end

  describe "mode: :game_index (IGDB-only, no local corpus)" do
    it "calls IGDB and returns the rows without consulting Search::Omnisearch" do
      expect(Search::Omnisearch).not_to receive(:call)
      allow(igdb_client).to receive(:search_games).with("zelda", limit: 10)
        .and_return([ igdb_row(id: 7346, name: "BotW") ])

      result = described_class.call(query: "zelda", mode: :game_index)
      expect(result.mode).to eq(:game_index)
      expect(result.local_games).to eq([])
      expect(result.local_bundles).to eq([])
      expect(result.igdb.map { |r| r["id"] }).to eq([ 7346 ])
      expect(result.igdb_error).to be_nil
    end
  end

  describe "mode: :bundle_add (always-search-both contract)" do
    let(:bundle) { build_stubbed(:bundle) }

    it "returns BOTH local hits and IGDB hits when both are non-empty (always-search-both)" do
      local_game = build_stubbed(:game, id: 41, title: "Local Game", igdb_id: 999_001)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", exclude_bundle: bundle)
        .and_return(games: [ local_game ], bundles: [])
      allow(igdb_client).to receive(:search_games).with("any", limit: 10)
        .and_return([ igdb_row(id: 12_345, name: "IGDB Hit") ])

      result = described_class.call(query: "any", mode: :bundle_add, bundle: bundle)
      expect(result.local_games.map(&:id)).to eq([ 41 ])
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
      expect(result.local_bundles).to eq([])
    end

    it "returns local hits only when IGDB returns zero rows (still calls IGDB)" do
      local_game = build_stubbed(:game, id: 41, title: "Local Game", igdb_id: nil)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", exclude_bundle: bundle)
        .and_return(games: [ local_game ], bundles: [])
      expect(igdb_client).to receive(:search_games).with("any", limit: 10).and_return([])

      result = described_class.call(query: "any", mode: :bundle_add, bundle: bundle)
      expect(result.local_games.map(&:id)).to eq([ 41 ])
      expect(result.igdb).to eq([])
    end

    it "still calls IGDB even when local returns zero hits (the contract is unconditional)" do
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", exclude_bundle: bundle)
        .and_return(games: [], bundles: [])
      expect(igdb_client).to receive(:search_games).with("any", limit: 10)
        .and_return([ igdb_row(id: 12_345, name: "IGDB Hit") ])

      result = described_class.call(query: "any", mode: :bundle_add, bundle: bundle)
      expect(result.local_games).to eq([])
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
    end

    it "dedups: IGDB row whose id matches a local game's igdb_id is filtered out" do
      # Regression guard for Rule 1 dedup. Local game already has
      # igdb_id 999_001 — the IGDB hit with id 999_001 must NOT appear
      # in the result; the unrelated id 12_345 survives.
      local_game = build_stubbed(:game, id: 41, title: "Local Game", igdb_id: 999_001)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", exclude_bundle: bundle)
        .and_return(games: [ local_game ], bundles: [])
      allow(igdb_client).to receive(:search_games).with("any", limit: 10).and_return([
        igdb_row(id: 999_001, name: "Already Local"),
        igdb_row(id: 12_345,  name: "Fresh IGDB Hit")
      ])

      result = described_class.call(query: "any", mode: :bundle_add, bundle: bundle)
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
    end
  end

  describe "mode: :games_search (local games + bundles + IGDB, always-search-both)" do
    it "returns both local hits AND IGDB hits when both are non-empty" do
      local_game   = build_stubbed(:game, id: 51, title: "Local", igdb_id: 888_001)
      local_bundle = build_stubbed(:bundle, id: 61, name: "Local Bundle")
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", include_bundles: true)
        .and_return(games: [ local_game ], bundles: [ local_bundle ])
      allow(igdb_client).to receive(:search_games).with("any", limit: 10)
        .and_return([ igdb_row(id: 12_345, name: "IGDB Hit") ])

      result = described_class.call(query: "any", mode: :games_search)
      expect(result.local_games.map(&:id)).to eq([ 51 ])
      expect(result.local_bundles.map(&:id)).to eq([ 61 ])
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
    end

    it "returns local hits only when IGDB is empty (still calls IGDB)" do
      local_game = build_stubbed(:game, id: 51, title: "Local", igdb_id: nil)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", include_bundles: true)
        .and_return(games: [ local_game ], bundles: [])
      expect(igdb_client).to receive(:search_games).with("any", limit: 10).and_return([])

      result = described_class.call(query: "any", mode: :games_search)
      expect(result.local_games.map(&:id)).to eq([ 51 ])
      expect(result.igdb).to eq([])
    end

    it "still calls IGDB even when local returns zero hits (the contract is unconditional)" do
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", include_bundles: true)
        .and_return(games: [], bundles: [])
      expect(igdb_client).to receive(:search_games).with("any", limit: 10)
        .and_return([ igdb_row(id: 12_345, name: "IGDB Hit") ])

      result = described_class.call(query: "any", mode: :games_search)
      expect(result.local_games).to eq([])
      expect(result.local_bundles).to eq([])
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
    end

    it "dedups: IGDB row whose id matches a local game's igdb_id is filtered out" do
      local_game = build_stubbed(:game, id: 51, title: "Local", igdb_id: 888_001)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", include_bundles: true)
        .and_return(games: [ local_game ], bundles: [])
      allow(igdb_client).to receive(:search_games).with("any", limit: 10).and_return([
        igdb_row(id: 888_001, name: "Already Local"),
        igdb_row(id: 12_345,  name: "Fresh IGDB Hit")
      ])

      result = described_class.call(query: "any", mode: :games_search)
      expect(result.igdb.map { |r| r["id"] }).to eq([ 12_345 ])
    end
  end

  describe "IGDB error envelope" do
    let(:bundle) { build_stubbed(:bundle) }

    it "swallows an Igdb::Client::Error and returns the upstream_unavailable envelope (:bundle_add)" do
      local_game = build_stubbed(:game, id: 41, title: "Local", igdb_id: nil)
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", exclude_bundle: bundle)
        .and_return(games: [ local_game ], bundles: [])
      allow(igdb_client).to receive(:search_games)
        .and_raise(Igdb::Client::Error, "boom")

      result = described_class.call(query: "any", mode: :bundle_add, bundle: bundle)
      expect(result.local_games.map(&:id)).to eq([ 41 ])
      expect(result.igdb).to eq([])
      expect(result.igdb_error).to eq(kind: "upstream_unavailable", message: "boom")
    end

    it "swallows an Igdb::Client::Error and returns the upstream_unavailable envelope (:games_search)" do
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "any", include_bundles: true)
        .and_return(games: [], bundles: [])
      allow(igdb_client).to receive(:search_games)
        .and_raise(Igdb::Client::Error, "boom")

      result = described_class.call(query: "any", mode: :games_search)
      expect(result.igdb).to eq([])
      expect(result.igdb_error).to eq(kind: "upstream_unavailable", message: "boom")
    end
  end

  describe "blank-query short-circuit" do
    let(:bundle) { build_stubbed(:bundle) }

    it "does NOT call IGDB when the query is blank (:bundle_add)" do
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "", exclude_bundle: bundle)
        .and_return(games: [], bundles: [])
      expect(igdb_client).not_to receive(:search_games)

      result = described_class.call(query: "   ", mode: :bundle_add, bundle: bundle)
      expect(result.igdb).to eq([])
      expect(result.igdb_error).to be_nil
    end

    it "does NOT call IGDB when the query is blank (:games_search)" do
      allow(Search::Omnisearch).to receive(:call)
        .with(area: :games, query: "", include_bundles: true)
        .and_return(games: [], bundles: [])
      expect(igdb_client).not_to receive(:search_games)

      result = described_class.call(query: "", mode: :games_search)
      expect(result.igdb).to eq([])
      expect(result.igdb_error).to be_nil
    end
  end
end
