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
      #   for this embedding space. Similarity AT floor displays as 0.
      # @param ceiling [Float] the measured practical maximum for this
      #   COMPARISON TYPE — doc-to-doc similarities approach 1.0, but a short
      #   query against a long document structurally cannot (query→game
      #   matches top out ~0.70 in this space), so anchoring 100 at 1.0
      #   renders every honest query hit as a sad sliver. Similarity AT (or
      #   above) ceiling displays as 100. Default 1.0 = the doc-to-doc
      #   behavior every pre-3.1.2 caller had.
      # @return [Float] 0.0..100.0, unrounded — callers round as they already did.
      def display_score(similarity, floor:, ceiling: 1.0)
        ((similarity.to_f - floor) / (ceiling - floor) * 100).clamp(0.0, 100.0)
      end
    end
  end
end
