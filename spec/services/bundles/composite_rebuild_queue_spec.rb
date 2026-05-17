require "rails_helper"

# Phase 27 follow-up (2026-05-17) — `Bundles::CompositeRebuildQueue`
# orchestrator spec. Replaces the Phase 27 v2 spec 02
# `Collections::CompositeRebuildQueue` spec (Collection model was
# removed). The orchestrator deduplicates the input set, sorts by
# `LOWER(name)`, and enqueues a sequential `BundleCoverBuild` chain.
RSpec.describe Bundles::CompositeRebuildQueue do
  describe "#enqueue_for_bundles" do
    it "returns an empty id list when input is empty" do
      BundleCoverBuild.clear
      ids = described_class.new.enqueue_for_bundles([])
      expect(ids).to eq([])
      expect(BundleCoverBuild.jobs).to be_empty
    end

    it "tolerates a nil input" do
      BundleCoverBuild.clear
      ids = described_class.new.enqueue_for_bundles(nil)
      expect(ids).to eq([])
      expect(BundleCoverBuild.jobs).to be_empty
    end

    it "enqueues a single head job carrying the alphabetical tail" do
      gamma = create(:bundle, name: "Gamma")
      alpha = create(:bundle, name: "Alpha")
      beta  = create(:bundle, name: "Beta")
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_bundles([ gamma, alpha, beta ])

      expect(ids).to eq([ alpha.id, beta.id, gamma.id ])
      enqueued = BundleCoverBuild.jobs.map { |j| j["args"] }
      expect(enqueued).to eq([ [ alpha.id, [ beta.id, gamma.id ] ] ])
    end

    it "is case-insensitive on the sort key" do
      lower = create(:bundle, name: "alpha")
      upper = create(:bundle, name: "Beta")
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_bundles([ upper, lower ])
      expect(ids).to eq([ lower.id, upper.id ])
    end

    it "dedupes the input by id" do
      a = create(:bundle, name: "A")
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_bundles([ a, a ])
      expect(ids).to eq([ a.id ])
      expect(BundleCoverBuild.jobs.size).to eq(1)
    end

    it "tolerates an ActiveRecord::Relation as input" do
      a = create(:bundle, name: "A")
      b = create(:bundle, name: "B")
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_bundles(Bundle.where(id: [ a.id, b.id ]))
      expect(ids).to contain_exactly(a.id, b.id)
    end
  end

  describe "#enqueue_for_game_resync" do
    it "enqueues a chain for the bundles the game currently belongs to" do
      game = create(:game, :synced)
      b1 = create(:bundle, name: "Aa")
      b2 = create(:bundle, name: "Bb")
      b1.bundle_members.create!(game: game)
      b2.bundle_members.create!(game: game)
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_game_resync(game.reload)
      expect(ids).to eq([ b1.id, b2.id ])
    end

    it "is a no-op when the game belongs to zero bundles" do
      game = create(:game, :synced)
      BundleCoverBuild.clear
      ids = described_class.new.enqueue_for_game_resync(game)
      expect(ids).to eq([])
      expect(BundleCoverBuild.jobs).to be_empty
    end

    it "tolerates a nil game" do
      BundleCoverBuild.clear
      ids = described_class.new.enqueue_for_game_resync(nil)
      expect(ids).to eq([])
    end
  end

  describe "#enqueue_for_game_destroy" do
    it "enqueues a chain for the explicit was_in set (alphabetical)" do
      game = create(:game, :synced)
      b1 = create(:bundle, name: "Zeta")
      b2 = create(:bundle, name: "Alpha")
      BundleCoverBuild.clear

      ids = described_class.new.enqueue_for_game_destroy(game, was_in: [ b1, b2 ])
      expect(ids).to eq([ b2.id, b1.id ])
    end

    it "is a no-op when was_in is empty" do
      game = create(:game, :synced)
      BundleCoverBuild.clear
      ids = described_class.new.enqueue_for_game_destroy(game, was_in: [])
      expect(ids).to eq([])
    end
  end
end
