module Pito
  module Recommendation
    # Top-K selection with optional score threshold.
    class TopK
      # @param items [Array<Hash>] [{ id:, score: }, ...]
      # @param k [Integer] max items to return
      # @param threshold [Float, nil] minimum score (nil = no floor)
      # @return [Array<Hash>] top K items sorted desc by score
      def self.call(items:, k:, threshold: nil)
        filtered = threshold ? items.select { |i| i[:score] >= threshold } : items
        filtered.sort_by { |i| -i[:score] }.first(k)
      end
    end
  end
end
