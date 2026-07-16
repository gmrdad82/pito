# frozen_string_literal: true

module Pito
  module Recommendation
    # Rescales a raw cosine similarity into the SAME 0-100 scale every score
    # bar renders — but stretched from a measured "floor" instead of from 0.
    #
    # Games' `like` score is a 10-signal blend (Signals + Weights); embedding
    # similarity is just ONE small weighted input in that blend, and this
    # module has NOTHING to do with it — Pito::Recommendation::Signals.embedding
    # stays exactly as it is, unrescaled, feeding the blend.
    #
    # Vid and conversation `like` scores, by contrast, ARE 100% raw cosine
    # similarity with no blend to dilute it. Measured prod data (2026-07-16)
    # showed both embedding spaces are tight enough that two RANDOM, unrelated
    # items already sit at a high raw cosine — every bar looked like a
    # near-perfect match, discriminating nothing. Rescaling from the measured
    # "everything looks similar" floor for each space restores a bar that
    # actually spreads real matches from background noise.
    module DisplayScore
      module_function

      # Measured 2026-07-16 on 19 prod vids: random-pair median cosine .879,
      # nearest-neighbor median .964, max .993. Tunable as the library grows.
      VID_FLOOR = 0.85

      # Measured 2026-07-16 on 60 prod events: random-pair median cosine .469,
      # nearest median .712. Tunable as the library grows.
      CONVERSATION_FLOOR = 0.50

      # @param similarity [Float] raw cosine similarity (1.0 - distance);
      #   1.0 = identical, 0.0 = orthogonal.
      # @param floor [Float] the measured "everything looks similar" baseline
      #   for this embedding space. Similarity AT floor displays as 0;
      #   similarity of 1.0 always displays as 100, regardless of floor.
      # @return [Float] 0.0..100.0, unrounded — callers round as they already did.
      def display_score(similarity, floor:)
        ((similarity.to_f - floor) / (1.0 - floor) * 100).clamp(0.0, 100.0)
      end
    end
  end
end
