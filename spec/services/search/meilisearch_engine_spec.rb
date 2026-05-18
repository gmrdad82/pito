require "rails_helper"

# Phase 7 Path A2 (literal full retract). Video declares no
# `searchable :*` / `filterable :*` lines, so the Meilisearch index
# for videos has no searchable text and queries return no matches.
# These specs assert the engine surface stays functional (healthy?,
# index/remove without raising, reindex_all idempotent, empty
# searches return zero) — the actual match/highlight surface returns
# once Phase 8+ rebuilds metadata caching.
RSpec.describe Search::MeilisearchEngine, skip: ENV["CI"].present? && "requires Meilisearch" do
  let(:engine) { described_class.new }
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }

  before do
    client = engine.instance_variable_get(:@client)
    begin
      client.index("videos_test").delete_all_documents
    rescue Meilisearch::ApiError
      # Index may not exist yet
    end
  end

  describe "#healthy?" do
    it "returns true when Meilisearch is available" do
      expect(engine.healthy?).to be true
    end

    it "returns false when Meilisearch is unavailable" do
      bad_engine = described_class.new(url: "http://127.0.0.1:9999")
      expect(bad_engine.healthy?).to be false
    end
  end

  describe "#index" do
    it "indexes a video without raising (id-only document)" do
      expect { engine.index(video) }.not_to raise_error
    end

    it "skips records without searchable_fields" do
      record = double("non-searchable", class: Class.new)
      expect { engine.index(record) }.not_to raise_error
    end
  end

  describe "#remove" do
    it "removes a video from the index without raising" do
      engine.index(video)
      wait_for_tasks
      expect { engine.remove(video) }.not_to raise_error
    end

    it "does not raise for missing records" do
      expect { engine.remove(video) }.not_to raise_error
    end
  end

  describe "#reindex_all" do
    it "reindexes without raising" do
      create(:video, channel: channel)
      expect { engine.reindex_all(Video) }.not_to raise_error
      wait_for_tasks
    end

    it "is idempotent (re-running does not change row count)" do
      engine.reindex_all(Video)
      wait_for_tasks
      count_before = engine.search(Video, "")[:total]

      engine.reindex_all(Video)
      wait_for_tasks
      count_after = engine.search(Video, "")[:total]

      expect(count_after).to eq(count_before)
    end
  end

  describe "#search (post-A2: returns zero matches by design)" do
    before do
      channel
      video
      engine.reindex_all(Video)
      wait_for_tasks
    end

    it "returns the engine envelope shape" do
      result = engine.search(Video, "anything")
      expect(result).to have_key(:hits)
      expect(result).to have_key(:total)
      expect(result).to have_key(:took_ms)
      expect(result[:hits]).to be_an(Array)
    end

    it "supports pagination without raising" do
      result = engine.search(Video, "", page: 1, per_page: 1)
      expect(result[:hits].size).to be <= 1
    end

    it "returns empty results for non-matching query" do
      result = engine.search(Video, "nonexistent query xyz123")
      expect(result[:hits]).to be_empty
    end
  end

  describe "#index_stats" do
    it "returns document counts per index" do
      engine.reindex_all(Video)
      wait_for_tasks

      stats = engine.index_stats
      expect(stats).to be_a(Hash)
    end
  end

  # 2026-05-11 — `settings/index` stack section surfaces aggregated
  # on-disk index size in muted text. The engine method reads
  # Meilisearch `/stats` and prefers the top-level `databaseSize`
  # when present; otherwise it sums per-index sizes. Defensive
  # rescue returns nil so the view hides the row when the metric
  # isn't exposed.
  describe "#total_index_size_bytes" do
    let(:stub_engine) { described_class.new }

    it "prefers the top-level databaseSize when present (Numeric)" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return(
        "databaseSize" => 7_500_000,
        "indexes" => { "videos_test" => { "databaseSize" => 100 } }
      )
      expect(stub_engine.total_index_size_bytes).to eq(7_500_000)
    end

    it "parses a stringified top-level databaseSize" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return("databaseSize" => "12345")
      expect(stub_engine.total_index_size_bytes).to eq(12_345)
    end

    it "sums per-index databaseSize when the top-level value is absent" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return(
        "indexes" => {
          "videos_test" => { "databaseSize" => 100 },
          "channels_test" => { "databaseSize" => 250 }
        }
      )
      expect(stub_engine.total_index_size_bytes).to eq(350)
    end

    it "returns nil when nothing reports a size" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return("indexes" => {})
      expect(stub_engine.total_index_size_bytes).to be_nil
    end

    it "returns nil on engine errors (defensive rescue)" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_raise(StandardError.new("boom"))
      expect(stub_engine.total_index_size_bytes).to be_nil
    end
  end

  # 2026-05-11 (later 2) — `settings/index` Meilisearch surface
  # was refactored from a flat indexed-documents list + total-size
  # summary into a per-index `index | documents | size` table.
  # The engine exposes `per_index_stats` returning a hash keyed by
  # raw index name with `:documents` + `:size_bytes` values.
  describe "#per_index_stats" do
    let(:stub_engine) { described_class.new }

    it "returns documents + size_bytes per index, preferring databaseSize" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return(
        "indexes" => {
          "channels_test" => { "numberOfDocuments" => 10, "databaseSize" => 4_500_000 },
          "videos_test"   => { "numberOfDocuments" => 42, "databaseSize" => 9_900_000 }
        }
      )
      result = stub_engine.per_index_stats
      expect(result["channels_test"]).to eq(documents: 10, size_bytes: 4_500_000)
      expect(result["videos_test"]).to eq(documents: 42, size_bytes: 9_900_000)
    end

    it "falls back to rawDocumentDbSize when databaseSize is absent" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return(
        "indexes" => {
          "channels_test" => { "numberOfDocuments" => 3, "rawDocumentDbSize" => 200 }
        }
      )
      expect(stub_engine.per_index_stats["channels_test"]).to eq(documents: 3, size_bytes: 200)
    end

    it "reports nil size_bytes when neither key is present" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return(
        "indexes" => { "channels_test" => { "numberOfDocuments" => 5 } }
      )
      expect(stub_engine.per_index_stats["channels_test"]).to eq(documents: 5, size_bytes: nil)
    end

    it "returns {} when the engine response has no indexes block" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_return({})
      expect(stub_engine.per_index_stats).to eq({})
    end

    it "returns {} on engine errors (defensive rescue)" do
      client = stub_engine.instance_variable_get(:@client)
      allow(client).to receive(:stats).and_raise(StandardError.new("boom"))
      expect(stub_engine.per_index_stats).to eq({})
    end
  end

  # 2026-05-18 — `documents_count_for` issues a Meilisearch search with
  # an empty query, a single `<field> = "<value>"` filter and `limit: 0`,
  # returning `estimatedTotalHits` as the integer count. The settings
  # stack pane uses this to split the shared `games_<env>` index into
  # Game vs Bundle rows by the `kind` discriminator.
  describe "#documents_count_for" do
    let(:stub_engine) { described_class.new }
    let(:client) { stub_engine.instance_variable_get(:@client) }
    let(:idx) { double("meili-index") }

    before do
      allow(client).to receive(:index).with("games_test").and_return(idx)
    end

    it "issues a search with `<field> = \"<value>\"` filter and `limit: 0`" do
      expect(idx).to receive(:search).with(
        "",
        filter: 'kind = "game"',
        limit: 0
      ).and_return("estimatedTotalHits" => 5)

      stub_engine.documents_count_for("games_test", field: :kind, value: "game")
    end

    it "returns the estimatedTotalHits count as an integer" do
      allow(idx).to receive(:search).and_return("estimatedTotalHits" => 17)
      expect(stub_engine.documents_count_for("games_test", field: :kind, value: "game")).to eq(17)
    end

    it "falls back to totalHits when estimatedTotalHits is absent" do
      allow(idx).to receive(:search).and_return("totalHits" => 9)
      expect(stub_engine.documents_count_for("games_test", field: :kind, value: "game")).to eq(9)
    end

    it "returns 0 when neither hit-count key is present" do
      allow(idx).to receive(:search).and_return({})
      expect(stub_engine.documents_count_for("games_test", field: :kind, value: "game")).to eq(0)
    end

    it "returns nil on engine failure (defensive rescue)" do
      allow(idx).to receive(:search).and_raise(StandardError.new("boom"))
      expect(stub_engine.documents_count_for("games_test", field: :kind, value: "game")).to be_nil
    end
  end

  private

  def wait_for_tasks
    client = engine.instance_variable_get(:@client)
    loop do
      tasks = client.tasks["results"]
      pending = tasks.select { |t| %w[enqueued processing].include?(t["status"]) }
      break if pending.empty?
      sleep 0.1
    end
  end
end
