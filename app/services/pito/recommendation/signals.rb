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

      # ── v2 facet signals ────────────────────────────────────────────────────

      SMILE_BASE = 0.4 # similarity floor for equal-but-mid (non-extreme) values

      # Score "smile": closeness amplified by SAME-SIDE extremity. Two >90 games
      # (or two <60 games) count far more than two ~75s, even when equally close.
      # The middle 60–90 band is the "smudge" (floor only). Either nil → 0.
      def score_smile(a, b)
        return 0.0 if a.nil? || b.nil?

        closeness = (1.0 - (a.to_f - b.to_f).abs / 100.0).clamp(0.0, 1.0)
        smile(closeness, same_side(signed_score_extremity(a.to_f), signed_score_extremity(b.to_f)))
      end

      # >90 → positive (elite), <60 → negative (bad), 60–90 → 0 (mid smudge).
      def signed_score_extremity(s)
        return ((s - 90.0) / 10.0).clamp(0.0, 1.0)   if s > 90.0
        return -((60.0 - s) / 20.0).clamp(0.0, 1.0)  if s < 60.0

        0.0
      end

      TTB_LOG_RANGE = Math.log(10.0) # a 10× hours gap → closeness 0
      TTB_SHORT_H   = 15.0           # ≤ this ramps into the short tail …
      TTB_SHORT_FULL_H = 3.0         # … full short extreme at ≤3h
      TTB_LONG_H    = 100.0          # ≥ this ramps into the long tail …
      TTB_LONG_FULL_H  = 150.0       # … full long extreme at ≥150h

      # TTB "smile" on log-hours: very short and very long (≥150h) games are
      # distinctive identities; ~30–40h is generic. Same-side amplified. Nil /
      # non-positive seconds → 0.
      def ttb_smile(a_seconds, b_seconds)
        return 0.0 if a_seconds.nil? || b_seconds.nil? || a_seconds.to_f <= 0 || b_seconds.to_f <= 0

        ha = a_seconds.to_f / 3600.0
        hb = b_seconds.to_f / 3600.0
        closeness = (1.0 - (Math.log(ha) - Math.log(hb)).abs / TTB_LOG_RANGE).clamp(0.0, 1.0)
        smile(closeness, same_side(signed_ttb_extremity(ha), signed_ttb_extremity(hb)))
      end

      # ≥100h → positive (epic, full at ≥150h); ≤15h → negative (short, full at
      # ≤3h); 15–100h → 0 (generic).
      def signed_ttb_extremity(hours)
        return ((hours - TTB_LONG_H) / (TTB_LONG_FULL_H - TTB_LONG_H)).clamp(0.0, 1.0)    if hours >= TTB_LONG_H
        return -((TTB_SHORT_H - hours) / (TTB_SHORT_H - TTB_SHORT_FULL_H)).clamp(0.0, 1.0) if hours <= TTB_SHORT_H

        0.0
      end

      ERA_DECAY = 7.0 # points lost per release-year apart (~14yr → 0)

      # Release-year proximity → 0–100. Either nil → 0.
      def era(year_a, year_b)
        return 0.0 if year_a.nil? || year_b.nil?

        (100.0 - (year_a.to_i - year_b.to_i).abs * ERA_DECAY).clamp(0.0, 100.0)
      end

      # Platform overlap → 0–100 (Jaccard of the platform name arrays).
      def platform_overlap(a, b)
        jaccard(a, b)
      end

      # ── helpers ─────────────────────────────────────────────────────────────

      # Combine closeness with a same-side extremity magnitude into the final
      # smile score: floor SMILE_BASE in the mid band, ramping to full closeness
      # at the extremes.
      def smile(closeness, extremity_mag)
        (closeness * (SMILE_BASE + (1.0 - SMILE_BASE) * extremity_mag) * 100.0).clamp(0.0, 100.0)
      end

      # Magnitude of shared extremity ONLY when both signed extremities point the
      # same way (both elite / both bad / both long / both short). Otherwise 0.
      def same_side(ext_a, ext_b)
        return 0.0 if ext_a.zero? || ext_b.zero? || (ext_a.positive? != ext_b.positive?)

        [ ext_a.abs, ext_b.abs ].min
      end
    end
  end
end
