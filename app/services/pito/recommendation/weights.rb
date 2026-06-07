# frozen_string_literal: true

module Pito
  module Recommendation
    # Single source of truth for recommendation signal weights, shared by every
    # direction (game→game, game→channel, channel→game). Tunable in one place.
    #
    # Reflects the product ranking: embedding is the primary semantic signal,
    # genre is strong, then score-proximity counts MORE, developer counts for
    # something, publisher counts LESS. The five blend weights sum to 1.0 so a
    # blended score lands in 0–100.
    #
    # An explicit video→game link is definitive and bypasses the blend entirely
    # (LINK_SCORE). Anything below FLOOR is dropped as a "bad" match (mirrors the
    # game-score tiers where 25 is the worst meaningful tier).
    module Weights
      E = 0.45 # embedding / semantic similarity
      G = 0.20 # genre overlap
      S = 0.15 # score proximity        (counts more)
      D = 0.12 # developer overlap      (counts for something)
      P = 0.08 # publisher overlap      (counts less)

      BLEND = { e: E, g: G, s: S, d: D, p: P }.freeze

      LINK_SCORE = 100 # explicit link → definitive match
      FLOOR      = 25  # drop blended scores below this

      # Blend a breakdown hash ({ e:, g:, s:, d:, p: } each 0–100) into a single
      # 0–100 score using the weights above. Missing keys count as 0.
      def self.blend(breakdown)
        BLEND.sum { |key, weight| weight * breakdown[key].to_f }.round
      end
    end
  end
end
