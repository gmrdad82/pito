require "rails_helper"

# Phase 27 §01h — Collection composite cover invalidator.
#
# The job name says "rebuild" but the action is eviction only: sweep the
# on-disk composite for the given collection ids so the next page-render
# call to `Collections::CoverComposer` writes through to a fresh
# composite. The composer's fingerprint check is a fallback; eviction
# makes the next render faster.
RSpec.describe CollectionCoverRebuildJob, type: :job do
  describe "Sidekiq options" do
    it "is enqueued on the :default queue" do
      described_class.clear
      described_class.perform_async(1, 2)
      expect(described_class.jobs.last["queue"]).to eq("default")
    end
  end

  describe "#perform" do
    let(:collection_a) { create(:collection, name: "A") }
    let(:collection_b) { create(:collection, name: "B") }
    let(:fixture)      { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

    def seed_file(coll)
      target = Pito::AssetsRoot.path("composites", "collection-#{coll.id}.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture, target)
      target
    end

    def file_path(coll)
      Pito::AssetsRoot.path("composites", "collection-#{coll.id}.jpg")
    end

    after do
      [ collection_a, collection_b ].each do |c|
        path = file_path(c)
        File.delete(path) if File.exist?(path)
      rescue Pito::AssetsRoot::Error
        nil
      end
    end

    it "removes the previous collection's on-disk composite" do
      seed_file(collection_a)
      expect(File.exist?(file_path(collection_a))).to be(true)

      described_class.new.perform(collection_a.id, collection_b.id)

      expect(File.exist?(file_path(collection_a))).to be(false)
    end

    it "removes the new collection's on-disk composite" do
      seed_file(collection_b)
      described_class.new.perform(collection_a.id, collection_b.id)
      expect(File.exist?(file_path(collection_b))).to be(false)
    end

    it "removes both files when both exist" do
      seed_file(collection_a)
      seed_file(collection_b)
      described_class.new.perform(collection_a.id, collection_b.id)
      expect(File.exist?(file_path(collection_a))).to be(false)
      expect(File.exist?(file_path(collection_b))).to be(false)
    end

    it "no-ops gracefully when neither file exists" do
      expect {
        described_class.new.perform(collection_a.id, collection_b.id)
      }.not_to raise_error
    end

    it "handles a nil previous_collection_id (game added with no prior collection)" do
      seed_file(collection_b)
      described_class.new.perform(nil, collection_b.id)
      expect(File.exist?(file_path(collection_b))).to be(false)
    end

    it "handles a nil current_collection_id (game removed from collection)" do
      seed_file(collection_a)
      described_class.new.perform(collection_a.id, nil)
      expect(File.exist?(file_path(collection_a))).to be(false)
    end

    it "handles both ids nil (defensive — never enqueued in practice)" do
      expect { described_class.new.perform(nil, nil) }.not_to raise_error
    end

    it "deduplicates when previous == current (no double-delete cost)" do
      seed_file(collection_a)
      described_class.new.perform(collection_a.id, collection_a.id)
      expect(File.exist?(file_path(collection_a))).to be(false)
    end

    it "survives Errno::ENOENT mid-job (file vanished between check and delete)" do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:delete).and_raise(Errno::ENOENT)
      expect {
        described_class.new.perform(collection_a.id, collection_b.id)
      }.not_to raise_error
    end
  end
end
