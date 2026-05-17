require "rails_helper"

RSpec.describe BundleCoverInvalidate, type: :job do
  describe "Sidekiq options" do
    it "is enqueued on the :default queue" do
      described_class.clear
      described_class.perform_async(1, "old")
      expect(described_class.jobs.last["queue"]).to eq("default")
    end
  end

  describe "#perform" do
    let(:game) { create(:game, :synced, cover_image_id: "new123") }

    it "evicts the previous tile from the cache" do
      cache = instance_double(Composite::TileCache, evict: nil)
      allow(Composite::TileCache).to receive(:new).and_return(cache)

      described_class.new.perform(game.id, "old456")
      expect(cache).to have_received(:evict).with("old456")
    end

    it "does NOT evict when previous_cover_image_id is blank" do
      cache = instance_double(Composite::TileCache, evict: nil)
      allow(Composite::TileCache).to receive(:new).and_return(cache)

      described_class.new.perform(game.id, nil)
      expect(cache).not_to have_received(:evict)
    end

    it "enqueues BundleCoverBuild once per bundle the game belongs to" do
      bundle1 = create(:bundle)
      bundle2 = create(:bundle)
      bundle1.bundle_members.create!(game: game)
      bundle2.bundle_members.create!(game: game)

      BundleCoverBuild.clear
      described_class.new.perform(game.id, "old456")
      enqueued_ids = BundleCoverBuild.jobs.map { |j| j["args"].first }
      expect(enqueued_ids).to contain_exactly(bundle1.id, bundle2.id)
    end

    it "no-ops on missing game" do
      expect { described_class.new.perform(999_999, "x") }.not_to raise_error
    end

    it "enqueues nothing when the game belongs to no bundles" do
      BundleCoverBuild.clear
      described_class.new.perform(game.id, "old123")
      expect(BundleCoverBuild.jobs).to be_empty
    end
  end
end
