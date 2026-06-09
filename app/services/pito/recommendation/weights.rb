# frozen_string_literal: true

module Pito
  module Recommendation
    # Single source of truth for recommendation signal weights, shared by every
    # direction (game→game, game→channel, channel→game). Tunable in one place.
    #
    # v2 — ten signals, blended over the ones that are actually PRESENT for a
    # given pair (see `.blend`). Weights are RELATIVE — the blend normalizes by
    # the present-weight sum, so they need not total 1.0 and missing facets never
    # count as dissimilarity (absence of data is not a mismatch).
    #
    #   PP — player_perspective overlap (third-person vs side-view vs first-person)
    #   G  — genre overlap
    #   T  — theme overlap (Action / Sci-fi / Horror / Survival …)
    #   S  — score "smile": two >90 (elite) or two <60 (bad) games count far more
    #        than two ~75s; the 60–90 mid is the smudge.
    #   TTB— time-to-beat "smile": very short and very long (≥150h) games are
    #        distinctive; ~30–40h is generic.
    #   ERA / PLATFORM — release-year proximity + platform overlap. A small shared
    #        slice (≈half each): matching both fills it, neither overshoots.
    #   D  — developer overlap (≈2× publisher).
    #   P  — publisher overlap (the smallest structured signal).
    #   E  — embedding / semantic similarity. Deliberately minor: descriptions are
    #        noisy. Its RELATIVE influence rises only as structured facets go
    #        missing (the present-signal normalization below is the "dynamic
    #        fallback"), and it can never outrank the heavy structured weights
    #        while they are present.
    #
    # An explicit video→game link is definitive on the channel directions and
    # bypasses the blend (LINK_SCORE — or its graded form on genre-channels).
    # Below FLOOR is dropped (kept low so weak-but-real matches still surface).
    module Weights
      PP       = 0.20
      G        = 0.22
      T        = 0.14
      S        = 0.14
      TTB      = 0.12
      ERA      = 0.04
      PLATFORM = 0.04
      D        = 0.06
      P        = 0.03
      E        = 0.03

      BLEND = { e: E, g: G, t: T, pp: PP, s: S, ttb: TTB, era: ERA, platform: PLATFORM, d: D, p: P }.freeze

      LINK_SCORE = 100 # explicit link → definitive match (legacy whole-link)
      FLOOR      = 5   # drop blended scores below this (near-noise only)

      # Graded link bonus for genre-channels (D-rec-2). A channel is a
      # personality, not a game's home, so one video must NOT pin it to 100:
      #
      #   K = 100 · d / (d + α + β·o)
      #     d = PUBLISHED videos on the channel linked to THIS game (depth)
      #     o = PUBLISHED videos on the channel linked to OTHER games (breadth)
      #
      # α=5 keeps a lone video small (~17 on a focused channel, ~6 on a busy
      # one); β=1 dilutes hard as the channel broadens. Added as a small bonus on
      # top of the profile-fit, never the whole score.
      DEPTH_ALPHA   = 5.0
      DILUTION_BETA = 1.0

      def self.graded_link(depth, other)
        d = depth.to_f
        return 0.0 if d <= 0

        100.0 * d / (d + DEPTH_ALPHA + DILUTION_BETA * other.to_f)
      end

      # Normalized weighted blend over ONLY the signals the caller put in
      # `breakdown` (each 0–100). Absent facets are omitted upstream — NOT scored
      # as 0 — so they neither help nor penalise. Dividing by the present-weight
      # sum is also what makes embedding a dynamic fallback: as structured facets
      # drop out the denominator shrinks and E's relative share grows, but the
      # heavy structured weights still dominate whenever they are present.
      def self.blend(breakdown)
        keys = breakdown.keys.select { |k| BLEND.key?(k) }
        return 0 if keys.empty?

        total = keys.sum { |k| BLEND[k] }
        (keys.sum { |k| BLEND[k] * breakdown[k].to_f } / total).round
      end
    end
  end
end
