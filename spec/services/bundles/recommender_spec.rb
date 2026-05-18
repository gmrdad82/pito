require "rails_helper"

# Phase 34 (2026-05-18) — `Bundles::Recommender` returns the GAMES
# whose `summary_embedding` sits closest (cosine) to the centroid of a
# bundle's current members' embeddings.
#
# These specs persist real pgvector values via `update_column` and
# exercise the `neighbor` gem's `nearest_neighbors(distance: "cosine")`
# query against the actual schema (HNSW index on
# `games.summary_embedding`).
RSpec.describe Bundles::Recommender do
  EMBEDDING_DIMS = 1024 unless defined?(EMBEDDING_DIMS)

  def vector(*leading)
    leading.map(&:to_f) + Array.new(EMBEDDING_DIMS - leading.size, 0.0)
  end

  def assign_embedding(game, vec)
    game.update_column(:summary_embedding, vec)
    game
  end

  def add_member(bundle, game)
    bundle.bundle_members.create!(game: game)
  end

  describe ".call" do
    it "returns Game.none when the bundle is nil" do
      expect(described_class.call(nil).to_a).to eq([])
    end

    it "returns Game.none when the bundle is empty" do
      bundle = create(:bundle)
      expect(described_class.call(bundle).to_a).to eq([])
    end

    it "returns Game.none when no member has an embedding" do
      bundle = create(:bundle)
      add_member(bundle, create(:game)) # no embedding
      add_member(bundle, create(:game))

      expect(described_class.call(bundle).to_a).to eq([])
    end

    it "recommends games close to the centroid of the bundle's member embeddings" do
      bundle = create(:bundle)
      # Members anchored along +x (centroid ~= (1, 0, 0) direction).
      m1 = assign_embedding(create(:game, title: "Member 1"), vector(1.0, 0.0, 0.0))
      m2 = assign_embedding(create(:game, title: "Member 2"), vector(1.0, 0.1, 0.0))
      add_member(bundle, m1)
      add_member(bundle, m2)

      near = assign_embedding(create(:game, title: "Near"), vector(1.0, 0.05, 0.0))
      far  = assign_embedding(create(:game, title: "Far"),  vector(0.0, 1.0, 0.0))

      titles = described_class.call(bundle).to_a.map(&:title)
      expect(titles.index("Near")).to be < titles.index("Far")
    end

    it "excludes games already in the bundle from recommendations" do
      bundle = create(:bundle)
      member = assign_embedding(create(:game, title: "Member"), vector(1.0, 0.0, 0.0))
      add_member(bundle, member)
      twin = assign_embedding(create(:game, title: "Twin"), vector(1.0, 0.0, 0.0))

      result = described_class.call(bundle).to_a
      expect(result).not_to include(member)
      expect(result).to include(twin)
    end

    it "honors the `limit:` kwarg" do
      bundle = create(:bundle)
      add_member(bundle, assign_embedding(create(:game), vector(1.0, 0.0, 0.0)))
      5.times do |i|
        assign_embedding(create(:game, title: "Cand #{i}"), vector(1.0, i * 0.01, 0.0))
      end

      expect(described_class.call(bundle, limit: 2).to_a.size).to eq(2)
    end

    it "defaults limit to DEFAULT_LIMIT (3)" do
      expect(described_class::DEFAULT_LIMIT).to eq(3)

      bundle = create(:bundle)
      add_member(bundle, assign_embedding(create(:game), vector(1.0, 0.0, 0.0)))
      6.times do |i|
        assign_embedding(create(:game, title: "Cand #{i}"), vector(1.0, i * 0.01, 0.0))
      end

      expect(described_class.call(bundle).to_a.size).to eq(3)
    end

    it "ignores members without an embedding when building the centroid" do
      bundle = create(:bundle)
      add_member(bundle, assign_embedding(create(:game, title: "Embedded member"), vector(1.0, 0.0, 0.0)))
      add_member(bundle, create(:game, title: "Bare member")) # nil embedding — skipped

      twin = assign_embedding(create(:game, title: "Twin"), vector(1.0, 0.0, 0.0))
      result = described_class.call(bundle).to_a
      expect(result).to include(twin)
    end

    it "returns an ActiveRecord::Relation" do
      bundle = create(:bundle)
      add_member(bundle, assign_embedding(create(:game), vector(1.0, 0.0, 0.0)))
      assign_embedding(create(:game), vector(1.0, 0.0, 0.0))

      expect(described_class.call(bundle)).to be_a(ActiveRecord::Relation)
    end
  end
end
