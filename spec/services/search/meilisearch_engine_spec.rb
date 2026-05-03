require "rails_helper"

RSpec.describe Search::MeilisearchEngine, skip: ENV["CI"].present? && "requires Meilisearch" do
  let(:engine) { described_class.new }
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel, title: "rails deep dive", description: "learning rails", tags: %w[ruby rails]) }

  before do
    # Clean test indexes
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
    it "indexes a video" do
      engine.index(video)
      wait_for_tasks

      result = engine.search(Video, "rails deep dive")
      expect(result[:hits].size).to eq(1)
      expect(result[:hits].first[:id]).to eq(video.id)
    end

    it "skips records without searchable_fields" do
      record = double("non-searchable", class: Class.new)
      expect { engine.index(record) }.not_to raise_error
    end
  end

  describe "#remove" do
    it "removes a video from the index" do
      engine.index(video)
      wait_for_tasks

      engine.remove(video)
      wait_for_tasks

      result = engine.search(Video, "rails deep dive")
      expect(result[:hits]).to be_empty
    end

    it "does not raise for missing records" do
      expect { engine.remove(video) }.not_to raise_error
    end
  end

  describe "#reindex_all" do
    it "indexes all videos" do
      create(:video, channel: channel, title: "another video", description: "test")
      engine.reindex_all(Video)
      wait_for_tasks

      result = engine.search(Video, "")
      expect(result[:total]).to eq(Video.count)
    end

    it "replaces existing documents" do
      engine.reindex_all(Video)
      wait_for_tasks
      count_before = engine.search(Video, "")[:total]

      engine.reindex_all(Video)
      wait_for_tasks
      count_after = engine.search(Video, "")[:total]

      expect(count_after).to eq(count_before)
    end
  end

  describe "#search" do
    before do
      # Force lazy lets to create records before reindexing
      channel
      video
      engine.reindex_all(Video)
      wait_for_tasks
    end

    it "returns hits with highlights" do
      result = engine.search(Video, "rails")
      expect(result[:hits]).to be_an(Array)
      expect(result).to have_key(:total)
      expect(result).to have_key(:took_ms)
    end

    it "returns record objects" do
      result = engine.search(Video, video.title)
      hit = result[:hits].find { |h| h[:id] == video.id }
      expect(hit).not_to be_nil
      expect(hit[:record]).to eq(video)
    end

    it "supports pagination" do
      result = engine.search(Video, "", page: 1, per_page: 1)
      expect(result[:hits].size).to be <= 1
    end

    it "supports filters on videos" do
      result = engine.search(Video, "", filters: { channel_id: channel.id })
      ids = result[:hits].map { |h| h[:id] }
      expect(ids).to include(video.id)
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
    # Wait for all tasks to complete
    loop do
      tasks = client.tasks["results"]
      pending = tasks.select { |t| %w[enqueued processing].include?(t["status"]) }
      break if pending.empty?
      sleep 0.1
    end
  end
end
