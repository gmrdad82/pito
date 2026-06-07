# frozen_string_literal: true

module Pito
  module Recommendation
    # Pure, side-effect-free signal helpers. Each returns a 0–100 sub-score the
    # blender combines via Weights. Kept tiny and independently unit-tested so
    # every direction shares identical, predictable signal math.
    module Signals
      module_function

      # Embedding similarity from a pgvector cosine distance (0 = identical,
      # 1 = orthogonal, 2 = opposite). nil distance (no embedding) → 0.
      def embedding(distance)
        return 0.0 if distance.nil?

        ((1.0 - distance.to_f) * 100).clamp(0.0, 100.0)
      end

      # Jaccard overlap of two collections of ids → 0–100 (|A∩B| / |A∪B|).
      # Two empty sets (or no union) → 0: absence of data is not a match.
      def jaccard(set_a, set_b)
        a = Array(set_a).to_set
        b = Array(set_b).to_set
        union = (a | b).size
        return 0.0 if union.zero?

        ((a & b).size.to_f / union) * 100
      end

      # Closeness of two 0–100 scores → 0–100 (100 when equal, 0 when 100 apart).
      # Either side missing → 0 (no comparable signal).
      def score_proximity(score_a, score_b)
        return 0.0 if score_a.nil? || score_b.nil?

        (100.0 - (score_a.to_f - score_b.to_f).abs).clamp(0.0, 100.0)
      end
    end
  end
end
