module Pito
  module Recommendation
    # Cosine similarity over Voyage embeddings.
    # Given a target embedding and a candidate set, returns each
    # candidate with its similarity score.
    class VectorSimilarity
      # @param target [Array<Float>] target embedding vector
      # @param candidates [Hash{id => Array<Float>}] candidate id → embedding
      # @return [Array<Hash>] [{ id:, score: }, ...] sorted desc by score
      def self.score(target:, candidates:)
        # Skeleton: delegate to pgvector cosine_distance once it's wired,
        # or implement Ruby cosine for in-memory mode.
        raise NotImplementedError,
              "Pito::Recommendation::VectorSimilarity pending pgvector wiring"
      end
    end
  end
end
