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
