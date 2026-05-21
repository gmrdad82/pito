module Pito
  module Recommendation
    # Weighted blend of multiple ranking signals into a single score.
    class WeightedBlend
      # @param signals [Hash{id => Hash{signal_name => Float}}]
      #   id → { signal_a: score_a, signal_b: score_b, ... }
      # @param weights [Hash{signal_name => Float}]
      #   signal_name → weight (weights should sum to 1.0)
      # @return [Array<Hash>] [{ id:, score: }, ...] blended scores
      def self.blend(signals:, weights:)
        signals.map do |id, signal_scores|
          blended = signal_scores.sum { |name, score| score * (weights[name] || 0) }
          { id: id, score: blended }
        end
      end
    end
  end
end
