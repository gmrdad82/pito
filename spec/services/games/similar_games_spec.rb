require "rails_helper"

# Phase 34 (2026-05-18) — `Games::SimilarGames` returns the cosine
# nearest neighbours of a game on the `summary_embedding` column.
#
# These specs persist real pgvector values via `update_column` and
# exercise the `neighbor` gem's `nearest_neighbors(distance: "cosine")`
# query against the actual schema (HNSW index on
# `games.summary_embedding`). Vectors are 1024-dim per the column
# definition; only the first few coordinates vary, the rest are zeroed.
RSpec.describe Games::SimilarGames do
  EMBEDDING_DIMS = 1024

  # Build a 1024-dim vector with the supplied leading coordinates and
  # zeros for the remainder. Keeps tests readable while satisfying the
  # column's `limit: 1024`.
  def vector(*leading)
    leading.map(&:to_f) + Array.new(EMBEDDING_DIMS - leading.size, 0.0)
  end

  def assign_embedding(game, vec)
    game.update_column(:summary_embedding, vec)
    game
  end

  describe ".call" do
    it "returns Game.none when the input game is nil" do
      result = described_class.call(nil)
      expect(result).to eq(Game.none)
      expect(result.to_a).to eq([])
    end

    it "returns Game.none when the input game has no summary_embedding" do
      game = create(:game)
      expect(game.summary_embedding).to be_nil

      result = described_class.call(game)
      expect(result.to_a).to eq([])
    end

    it "excludes the input game from the result set" do
      anchor = assign_embedding(create(:game, title: "Anchor"), vector(1.0, 0.0, 0.0))
      other  = assign_embedding(create(:game, title: "Other"),  vector(1.0, 0.0, 0.0))

      result = described_class.call(anchor).to_a
      expect(result).not_to include(anchor)
      expect(result).to include(other)
    end

    it "orders neighbours by cosine distance (nearest first)" do
      # Anchor points along +x. Closer = smaller angle to +x.
      anchor    = assign_embedding(create(:game, title: "Anchor"),  vector(1.0, 0.0, 0.0))
      twin      = assign_embedding(create(:game, title: "Twin"),    vector(1.0, 0.0, 0.0))   # cosine distance 0
      near      = assign_embedding(create(:game, title: "Near"),    vector(1.0, 0.1, 0.0))   # slightly off-axis
      mid       = assign_embedding(create(:game, title: "Mid"),     vector(1.0, 1.0, 0.0))   # 45 degrees
      orthogonal = assign_embedding(create(:game, title: "Ortho"),  vector(0.0, 1.0, 0.0))   # 90 degrees

      result = described_class.call(anchor).to_a
      ordering = result.map(&:title)
      expect(ordering.first).to eq("Twin")
      expect(ordering.index("Near")).to be < ordering.index("Mid")
      expect(ordering.index("Mid")).to be < ordering.index("Ortho")
    end

    it "honors the `limit:` kwarg" do
      anchor = assign_embedding(create(:game, title: "Anchor"), vector(1.0, 0.0, 0.0))
      5.times do |i|
        assign_embedding(create(:game, title: "Neighbor #{i}"), vector(1.0, i * 0.01, 0.0))
      end

      result = described_class.call(anchor, limit: 2).to_a
      expect(result.size).to eq(2)
    end

    it "defaults `limit:` to DEFAULT_LIMIT (10)" do
      expect(described_class::DEFAULT_LIMIT).to eq(10)

      anchor = assign_embedding(create(:game, title: "Anchor"), vector(1.0, 0.0, 0.0))
      12.times do |i|
        assign_embedding(create(:game, title: "Neighbor #{i}"), vector(1.0, i * 0.01, 0.0))
      end

      result = described_class.call(anchor).to_a
      expect(result.size).to eq(10)
    end

    it "skips games without an embedding (they cannot be cosine-compared)" do
      anchor   = assign_embedding(create(:game, title: "Anchor"), vector(1.0, 0.0, 0.0))
      embedded = assign_embedding(create(:game, title: "Embedded"), vector(1.0, 0.1, 0.0))
      bare     = create(:game, title: "Bare") # no embedding

      result = described_class.call(anchor).to_a
      expect(result).to include(embedded)
      expect(result).not_to include(bare)
    end

    it "returns an ActiveRecord::Relation (composable + lazy)" do
      anchor = assign_embedding(create(:game, title: "Anchor"), vector(1.0, 0.0, 0.0))
      assign_embedding(create(:game, title: "Twin"), vector(1.0, 0.0, 0.0))

      result = described_class.call(anchor)
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end
end
