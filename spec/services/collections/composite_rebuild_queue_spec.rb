require "rails_helper"

# Phase 27 v2 spec 02 — Collection composite rebuild queue.
#
# The orchestrator sorts inputs alphabetically by `Collection.name`
# (case-insensitive), deduplicates by id, and enqueues a sequential
# chain of `CollectionCoverRebuildJob` runs. The first job carries the
# tail; each job pops the next id off on success.
RSpec.describe Collections::CompositeRebuildQueue do
  subject(:queue) { described_class.new }

  before { CollectionCoverRebuildJob.clear }

  describe "#enqueue_for_collections" do
    let!(:c_a) { create(:collection, name: "alpha") }
    let!(:c_b) { create(:collection, name: "Bravo") }
    let!(:c_c) { create(:collection, name: "charlie") }

    it "enqueues ONE job (the chain head) for a multi-collection batch" do
      queue.enqueue_for_collections([ c_b, c_a, c_c ])
      expect(CollectionCoverRebuildJob.jobs.size).to eq(1)
    end

    it "the chain head carries the alphabetical first id + the rest as tail" do
      queue.enqueue_for_collections([ c_b, c_a, c_c ])
      args = CollectionCoverRebuildJob.jobs.last["args"]
      expect(args).to eq([ c_a.id, [ c_b.id, c_c.id ] ])
    end

    it "returns the ordered id list (alphabetical, case-insensitive)" do
      ids = queue.enqueue_for_collections([ c_b, c_a, c_c ])
      expect(ids).to eq([ c_a.id, c_b.id, c_c.id ])
    end

    it "sorts case-insensitively (alpha < Bravo < charlie)" do
      ids = queue.enqueue_for_collections([ c_c, c_b, c_a ])
      expect(ids).to eq([ c_a.id, c_b.id, c_c.id ])
    end

    it "deduplicates duplicate inputs by collection id" do
      ids = queue.enqueue_for_collections([ c_a, c_a, c_b, c_a ])
      expect(ids).to eq([ c_a.id, c_b.id ])
      args = CollectionCoverRebuildJob.jobs.last["args"]
      expect(args).to eq([ c_a.id, [ c_b.id ] ])
    end

    it "enqueues nothing for an empty input" do
      result = queue.enqueue_for_collections([])
      expect(result).to eq([])
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end

    it "drops nil entries from the input set" do
      ids = queue.enqueue_for_collections([ nil, c_a, nil ])
      expect(ids).to eq([ c_a.id ])
    end

    it "handles a single-collection input (enqueues with empty tail)" do
      ids = queue.enqueue_for_collections([ c_a ])
      expect(ids).to eq([ c_a.id ])
      args = CollectionCoverRebuildJob.jobs.last["args"]
      expect(args).to eq([ c_a.id, [] ])
    end

    it "accepts an ActiveRecord relation, not just an array" do
      relation = Collection.where(id: [ c_a.id, c_b.id ])
      ids = queue.enqueue_for_collections(relation)
      expect(ids.sort).to eq([ c_a.id, c_b.id ].sort)
    end
  end

  describe "#enqueue_for_game_resync" do
    let!(:c_a) { create(:collection, name: "alpha") }

    it "enqueues a chain for the game's current collection" do
      game = create(:game, :synced, collection: c_a, title: "g")
      CollectionCoverRebuildJob.clear

      ids = queue.enqueue_for_game_resync(game)
      expect(ids).to eq([ c_a.id ])
      expect(CollectionCoverRebuildJob.jobs.size).to eq(1)
      expect(CollectionCoverRebuildJob.jobs.last["args"]).to eq([ c_a.id, [] ])
    end

    it "no-ops when the game has no collection" do
      game = create(:game, :synced, collection: nil, title: "loose")
      CollectionCoverRebuildJob.clear

      result = queue.enqueue_for_game_resync(game)
      expect(result).to eq([])
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end

    it "no-ops when game is nil" do
      result = queue.enqueue_for_game_resync(nil)
      expect(result).to eq([])
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end
  end

  describe "#enqueue_for_game_destroy" do
    let!(:c_a) { create(:collection, name: "alpha") }
    let!(:c_b) { create(:collection, name: "bravo") }
    let(:game) { create(:game, :synced) }

    it "enqueues a chain for the passed-in pre-destroy collection set" do
      ids = queue.enqueue_for_game_destroy(game, was_in: [ c_b, c_a ])
      expect(ids).to eq([ c_a.id, c_b.id ])
      args = CollectionCoverRebuildJob.jobs.last["args"]
      expect(args).to eq([ c_a.id, [ c_b.id ] ])
    end

    it "ignores the game's CURRENT collection state — only uses was_in" do
      # Game still attached to a different collection at call time; the
      # destroy contract is "rebuild what it WAS in, captured pre-destroy."
      game.update!(collection: c_a)
      CollectionCoverRebuildJob.clear

      ids = queue.enqueue_for_game_destroy(game, was_in: [ c_b ])
      expect(ids).to eq([ c_b.id ])
    end

    it "no-ops when was_in is empty" do
      result = queue.enqueue_for_game_destroy(game, was_in: [])
      expect(result).to eq([])
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end

    it "drops nils from was_in (game had no collection before destroy)" do
      result = queue.enqueue_for_game_destroy(game, was_in: [ nil ])
      expect(result).to eq([])
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end
  end
end
