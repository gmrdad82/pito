# Phase 37 Wave A (demographics A-slice, 2026-05-19) — age × gender
# demographics mock for `/channels`.
#
# Sibling module to `Channel::MockData`. Lives in its own file because
# `mock_data.rb` is actively co-edited by parallel A-slice agents (this
# slice ran alongside the geography / device-types / heatmap / window-
# summaries slices); a separate file removes the per-channel-hash edit
# collision risk without changing the public lookup shape.
#
# Public surface:
#
#   Channel::DemographicsMock::AGE_BUCKETS
#     => %w[13-17 18-24 25-34 35-44 45-54 55-64 65+]
#
#   Channel::DemographicsMock.for(channel_id)
#     => { male:   { "13-17" => Int, ..., "65+" => Int },
#          female: { "13-17" => Int, ..., "65+" => Int } }
#
#   Channel::DemographicsMock.aggregate(channels, weighted: false)
#     => same shape as `.for`, averaged across the given channel hashes.
#        When `weighted: true`, each channel's profile is weighted by
#        `channel[:view_count]` (falls back to equal weights if all
#        view_counts are zero/nil — defensive but unlikely in mock data).
#
# All values are PERCENTAGES OF VIEWERSHIP per channel and sum to 100
# across the 14 cells (2 genders × 7 buckets). The aggregator preserves
# the percent-of-100 invariant because percentages-of-percentages stay
# percentages (within rounding); the components do not need to re-
# normalize.
#
# Shapes are intentionally diverse across the 6 channels so the
# aggregate render varies meaningfully with channel selection:
#
#   1 Studio Aurora  — balanced-general; small 25-34 skew
#   2 Pixel Forge    — gaming; young-male heavy 18-34
#   3 Long-form Lab  — knowledge; older-skew, slightly male
#   4 Quiet Cinema   — film; mid-age, slight female lead
#   5 Field Notes    — educational; broad 25-44, balanced
#   6 Neon Atlas     — Gen Z; very young 13-24 dominant
#
# Wave B drops this module and reads real YouTube Analytics
# `viewerPercentage` rows grouped by `ageGroup` + `gender`.
class Channel
  module DemographicsMock
    module_function

    AGE_BUCKETS = %w[13-17 18-24 25-34 35-44 45-54 55-64 65+].freeze

    DATA = {
      1 => {
        male:   { "13-17" => 5,  "18-24" => 10, "25-34" => 15, "35-44" => 10, "45-54" => 5,  "55-64" => 3, "65+" => 1 },
        female: { "13-17" => 4,  "18-24" => 12, "25-34" => 18, "35-44" => 10, "45-54" => 4,  "55-64" => 2, "65+" => 1 }
      },
      2 => {
        male:   { "13-17" => 8,  "18-24" => 24, "25-34" => 22, "35-44" => 8,  "45-54" => 3,  "55-64" => 1, "65+" => 0 },
        female: { "13-17" => 3,  "18-24" => 12, "25-34" => 12, "35-44" => 5,  "45-54" => 1,  "55-64" => 1, "65+" => 0 }
      },
      3 => {
        male:   { "13-17" => 2,  "18-24" => 8,  "25-34" => 18, "35-44" => 22, "45-54" => 10, "55-64" => 5, "65+" => 2 },
        female: { "13-17" => 1,  "18-24" => 4,  "25-34" => 8,  "35-44" => 10, "45-54" => 6,  "55-64" => 3, "65+" => 1 }
      },
      4 => {
        male:   { "13-17" => 2,  "18-24" => 5,  "25-34" => 10, "35-44" => 12, "45-54" => 8,  "55-64" => 4, "65+" => 2 },
        female: { "13-17" => 3,  "18-24" => 8,  "25-34" => 15, "35-44" => 15, "45-54" => 10, "55-64" => 4, "65+" => 2 }
      },
      5 => {
        male:   { "13-17" => 3,  "18-24" => 8,  "25-34" => 14, "35-44" => 15, "45-54" => 8,  "55-64" => 4, "65+" => 2 },
        female: { "13-17" => 2,  "18-24" => 6,  "25-34" => 12, "35-44" => 14, "45-54" => 7,  "55-64" => 3, "65+" => 2 }
      },
      6 => {
        male:   { "13-17" => 15, "18-24" => 28, "25-34" => 12, "35-44" => 4,  "45-54" => 1,  "55-64" => 1, "65+" => 0 },
        female: { "13-17" => 10, "18-24" => 18, "25-34" => 8,  "35-44" => 2,  "45-54" => 1,  "55-64" => 0, "65+" => 0 }
      }
    }.freeze

    EMPTY_PROFILE = {
      male:   AGE_BUCKETS.to_h { |b| [ b, 0 ] }.freeze,
      female: AGE_BUCKETS.to_h { |b| [ b, 0 ] }.freeze
    }.freeze

    # Look up a single channel's demographic profile by id. Falls back
    # to a zero profile (all 14 cells = 0) for unknown ids so the
    # rendering surface never explodes on a stale channel reference.
    def for(channel_id)
      DATA.fetch(channel_id.to_i, EMPTY_PROFILE)
    end

    # Aggregate across a collection of channel hashes (the same shape
    # `Channel::MockData.channels` returns). Returns one
    # `{ male: { bucket => pct }, female: { bucket => pct } }` profile.
    #
    # `weighted: false` (default) — simple mean of percentages across
    #   the selected channels. Each channel contributes equally.
    # `weighted: true` — view-count weighted mean. Each channel's
    #   profile is weighted by `channel[:view_count]`. Falls back to
    #   equal weights when all selected view_counts are zero/nil.
    #
    # Returns the EMPTY_PROFILE when the input is empty so the
    # component renders a coherent zero-state without branching.
    def aggregate(channels, weighted: false)
      channels = Array(channels)
      return deep_dup(EMPTY_PROFILE) if channels.empty?

      weights =
        if weighted
          ws = channels.map { |c| (c[:view_count] || 0).to_i }
          ws.sum.zero? ? Array.new(channels.size, 1) : ws
        else
          Array.new(channels.size, 1)
        end
      total_weight = weights.sum.to_f
      return deep_dup(EMPTY_PROFILE) if total_weight.zero?

      out = { male: {}, female: {} }
      %i[male female].each do |gender|
        AGE_BUCKETS.each do |bucket|
          weighted_sum = channels.each_with_index.sum do |c, i|
            profile = c[:demographics] || self.for(c[:id])
            pct = profile.dig(gender, bucket) || 0
            pct * weights[i]
          end
          out[gender][bucket] = (weighted_sum.to_f / total_weight).round(1)
        end
      end
      out
    end

    # Per-cell + per-axis max across a profile — used by the bar
    # renderers so the longest bar maps to `bar_max_px` and shorter
    # bars scale linearly. Returns the max integer or 1 (avoid div-
    # by-zero in the components).
    def max_cell(profile)
      profile.values.flat_map(&:values).map(&:to_f).max || 0
    end

    def deep_dup(profile)
      profile.transform_values { |h| h.dup }
    end
  end
end
