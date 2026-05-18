require "rails_helper"

# Phase 34 (2026-05-18) — `Bundles::SuggestedFor` returns the BUNDLES
# whose `summary_embedding` (precomputed centroid) sits closest
# (cosine) to a given game's `summary_embedding`.
#
# These specs persist real pgvector values via `update_column` and
# exercise the `neighbor` gem's `nearest_neighbors(distance: "cosine")`
# query against the actual schema (HNSW index on
# `bundles.summary_embedding`).
RSpec.describe Bundles::SuggestedFor do
  EMBEDDING_DIMS = 1024 unless defined?(EMBEDDING_DIMS)

  def vector(*leading)
    leading.map(&:to_f) + Array.new(EMBEDDING_DIMS - leading.size, 0.0)
  end

  def embed_game(game, vec)
    game.update_column(:summary_embedding, vec)
    game
  end

  def embed_bundle(bundle, vec)
    bundle.update_column(:summary_embedding, vec)
    bundle
  end

  describe ".call" do
    it "returns Bundle.none when the game is nil" do
      result = described_class.call(nil)
      expect(result).to eq(Bundle.none)
      expect(result.to_a).to eq([])
    end

    it "returns Bundle.none when the game has no summary_embedding" do
      game = create(:game)
      expect(game.summary_embedding).to be_nil

      expect(described_class.call(game).to_a).to eq([])
    end

    it "returns nearest bundles by cosine distance (closest first)" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))

      twin  = embed_bundle(create(:bundle, name: "Twin"),  vector(1.0, 0.0, 0.0)) # cosine distance 0
      near  = embed_bundle(create(:bundle, name: "Near"),  vector(1.0, 0.1, 0.0))
      far   = embed_bundle(create(:bundle, name: "Far"),   vector(0.0, 1.0, 0.0))

      ordering = described_class.call(game).to_a.map(&:name)
      expect(ordering.first).to eq("Twin")
      expect(ordering.index("Near")).to be < ordering.index("Far")
    end

    it "excludes bundles the game is already a member of" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))

      already_in = embed_bundle(create(:bundle, name: "Already"), vector(1.0, 0.0, 0.0))
      candidate  = embed_bundle(create(:bundle, name: "Candidate"), vector(1.0, 0.0, 0.0))
      already_in.bundle_members.create!(game: game)

      result = described_class.call(game).to_a
      expect(result).not_to include(already_in)
      expect(result).to include(candidate)
    end

    it "honors the `limit:` kwarg" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))
      5.times { |i| embed_bundle(create(:bundle, name: "B#{i}"), vector(1.0, i * 0.01, 0.0)) }

      expect(described_class.call(game, limit: 2).to_a.size).to eq(2)
    end

    it "defaults `limit:` to DEFAULT_LIMIT (3)" do
      expect(described_class::DEFAULT_LIMIT).to eq(3)

      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))
      6.times { |i| embed_bundle(create(:bundle, name: "B#{i}"), vector(1.0, i * 0.01, 0.0)) }

      expect(described_class.call(game).to_a.size).to eq(3)
    end

    it "skips bundles without an embedding" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))

      bare      = create(:bundle, name: "Bare")           # nil embedding
      embedded  = embed_bundle(create(:bundle, name: "Embedded"), vector(1.0, 0.0, 0.0))

      result = described_class.call(game).to_a
      expect(result).to include(embedded)
      expect(result).not_to include(bare)
    end

    it "uses cosine distance (NOT L2) — direction beats magnitude" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))

      # `co_dir` shares direction with the game but a tiny magnitude;
      # `big_off` has a much larger magnitude but is orthogonal.
      # Cosine distance ignores magnitude → `co_dir` wins. (L2 would
      # rank `big_off` arbitrarily based on raw distance.)
      co_dir  = embed_bundle(create(:bundle, name: "CoDir"),   vector(0.01, 0.0, 0.0))
      big_off = embed_bundle(create(:bundle, name: "BigOff"),  vector(0.0, 100.0, 0.0))

      ordering = described_class.call(game).to_a.map(&:name)
      expect(ordering.index("CoDir")).to be < ordering.index("BigOff")
    end

    it "returns an ActiveRecord::Relation" do
      game = embed_game(create(:game), vector(1.0, 0.0, 0.0))
      embed_bundle(create(:bundle), vector(1.0, 0.0, 0.0))

      expect(described_class.call(game)).to be_a(ActiveRecord::Relation)
    end
  end
end
