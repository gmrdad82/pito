# frozen_string_literal: true

module Pito
  module Analytics
    # Aggregates per-subject dimension primitives into ordered share-percentage
    # arrays for bar-chart rendering. This is the bar-chart analogue of
    # `DailySeries` — it folds `Primitives.fetch` results across subjects into a
    # single ordered `[{key:, pct:}]` array per metric.
    #
    #   Pito::Analytics::Breakdown.for(metric: :subscribed_status, groups:, window:)
    #   # => [{ key: "UNSUBSCRIBED", pct: 72.3 }, { key: "SUBSCRIBED", pct: 27.7 }]
    #
    # Supported metrics:
    #   :subscribed_status — views share per status; UNSUBSCRIBED first, then SUBSCRIBED
    #   :devices           — views share folded into MOBILE / DESKTOP / TV buckets
    #   :geography         — views share by country; top 4 + "Other" rollup (G78)
    #   :gender            — viewer_percentage renormalised to 100 across subjects (≤3 buckets)
    #   :age               — viewer_percentage renormalised to 100; top 4 + "Other" rollup (G78)
    #
    # G78: every share list is capped at MAX_BARS by with_other_rollup — ≤5
    # segments stay discrete; more become top-4 + an OTHER_KEY bar carrying the
    # exact remainder, so a chart's bars ALWAYS total 100.
    #
    # Multi-subject aggregation notes:
    # - views (subscribed_status / devices / geography): exact integer sums across subjects.
    # - viewer_percentage (gender / age): per-subject percentages summed then renormalised
    #   to 100 by the kept-bucket sum. This is an approximation when the scope spans multiple
    #   channels or videos with different view counts — true views-weighting would require
    #   per-bucket views, which the demographics report does not return. Acceptable for v1.
    module Breakdown
      # Device types that the Analytics API may return; mapped to 3 buckets.
      # Unknown device types are silently ignored.
      DEVICE_BUCKET = {
        "MOBILE"       => "MOBILE",
        "TABLET"       => "MOBILE",  # TABLET folds into MOBILE
        "DESKTOP"      => "DESKTOP",
        "TV"           => "TV",
        "GAME_CONSOLE" => "TV"       # GAME_CONSOLE folds into TV
      }.freeze

      # Presentation order for device buckets.
      DEVICE_ORDER = %w[MOBILE DESKTOP TV].freeze

      # Presentation order for subscribed-status bars (typically larger bar first).
      SUBSCRIBED_ORDER = %w[UNSUBSCRIBED SUBSCRIBED].freeze

      # The rollup bucket's key (G78). Presentation maps it to the localized
      # "Other" label; it can never collide with a real dimension value
      # (country codes are 2 chars, age buckets carry the "age" prefix).
      OTHER_KEY = "OTHER"

      # Max bars a chart shows; when the data has more segments, the tail rolls
      # up into the 5th bar so every chart's percentages total 100 (G78 — the
      # old top-5 slice left e.g. Geography summing to 74% with the long tail
      # silently dropped).
      MAX_BARS = 5

      module_function

      # @param metric  [Symbol] one of :subscribed_status, :devices, :geography, :gender, :age
      # @param groups  [Array<[Channel, Array<String> | :channel]>] (as Primitives.fetch)
      # @param window  [Pito::Analytics::Window]
      # @return [Array<Hash{key: String, pct: Float}>] ordered bars; pct rounded to 1 decimal
      def for(metric:, groups:, window:)
        case metric
        when :subscribed_status then subscribed_status(groups:, window:)
        when :devices           then devices(groups:, window:)
        when :geography         then geography(groups:, window:)
        when :gender            then gender(groups:, window:)
        when :age               then age(groups:, window:)
        else
          Rails.logger.warn("[Analytics::Breakdown] unsupported metric: #{metric.inspect}")
          []
        end
      rescue StandardError => e
        Rails.logger.warn("[Analytics::Breakdown] #{metric}: #{e.class}: #{e.message}")
        []
      end

      # ── per-metric ─────────────────────────────────────────────────────────────

      # Views split by subscribed status. UNSUBSCRIBED rendered first — it is
      # typically the larger bar (most viewers haven't subscribed to the channel).
      def subscribed_status(groups:, window:)
        rows = all_rows(groups:, window:, report: "subscribed_status")
        return [] if rows.empty?

        totals = sum_by(rows, key: "subscribed_status", metric: "views")
        grand  = totals.values.sum
        return [] if grand.zero?

        SUBSCRIBED_ORDER.filter_map do |status|
          next unless totals.key?(status)
          { key: status, pct: pct(totals[status], grand) }
        end
      end

      # Views split by device type, folded into three buckets:
      #   MOBILE   = MOBILE + TABLET
      #   DESKTOP  = DESKTOP
      #   TV       = TV + GAME_CONSOLE
      # Rendered in fixed order: MOBILE → DESKTOP → TV. Empty buckets are excluded.
      def devices(groups:, window:)
        rows = all_rows(groups:, window:, report: "device")
        return [] if rows.empty?

        by_type = sum_by(rows, key: "device_type", metric: "views")
        buckets = Hash.new(0)
        by_type.each do |type, count|
          bucket = DEVICE_BUCKET[type]
          buckets[bucket] += count if bucket
        end

        grand = buckets.values.sum
        return [] if grand.zero?

        DEVICE_ORDER.filter_map do |bucket|
          next unless buckets[bucket] > 0
          { key: bucket, pct: pct(buckets[bucket], grand) }
        end
      end

      # Views share by country: top-4 countries + an "Other" rollup summing the
      # long tail (G78), so the bars always total 100. All ≤5 countries stay
      # discrete (no rollup needed to reach 100).
      def geography(groups:, window:)
        rows = all_rows(groups:, window:, report: "country")
        return [] if rows.empty?

        totals = sum_by(rows, key: "country", metric: "views")
        grand  = totals.values.sum
        return [] if grand.zero?

        shares = totals
          .sort_by { |_, v| -v }
          .map { |country, count| { key: country, pct: pct(count, grand) } }
        with_other_rollup(shares)
      end

      # viewer_percentage share by gender, renormalised to 100 over ALL buckets
      # (≤3 in the API, so the G78 rollup is a structural no-op here). See
      # module comment for the approximation caveat.
      def gender(groups:, window:)
        rows = all_rows(groups:, window:, report: "demographics")
        with_other_rollup(renormalised_shares(rows, key: "gender"))
      end

      # viewer_percentage share by age group, renormalised to 100 over ALL
      # buckets, then top-4 + "Other" (G78 — the API returns up to 7 age
      # buckets; the old top-5 renormalisation inflated the kept buckets to
      # fake 100 instead of naming the tail). See module comment for the
      # approximation caveat.
      def age(groups:, window:)
        rows = all_rows(groups:, window:, report: "demographics")
        with_other_rollup(renormalised_shares(rows, key: "age_group"))
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      # Fetch all primitive rows for a report, flattened across every subject.
      # Returns [] when Primitives returns nothing or a subject has no rows.
      def all_rows(groups:, window:, report:)
        Pito::Analytics::Primitives
          .fetch(groups:, window:, report:)
          .each_value
          .flat_map { |rows| Array(rows) }
          .select { |r| r.is_a?(Hash) }
      end

      # SUM a numeric metric column grouped by a dimension key.
      # Handles both String and Symbol row keys defensively (warm jsonb rows
      # always have String keys; Symbol keys can appear in test stubs or cold
      # reads before normalisation).
      # Returns Hash{ dimension_value => Float }.
      def sum_by(rows, key:, metric:)
        rows.each_with_object(Hash.new(0.0)) do |row, acc|
          dim = row[key] || row[key.to_sym]
          val = (row[metric] || row[metric.to_sym]).to_f
          acc[dim.to_s] += val if dim
        end
      end

      # Renormalise viewer_percentage sums over ALL buckets so shares total
      # 100 (multi-subject sums stack per-subject percentages; dividing by the
      # grand sum restores a 100 base). Ordered descending — with_other_rollup
      # decides what stays discrete. Returns [] on no data / zero sum.
      def renormalised_shares(rows, key:)
        return [] if rows.empty?

        totals = sum_by(rows, key:, metric: "viewer_percentage")
        return [] if totals.empty?

        grand = totals.values.sum
        return [] if grand.zero?

        totals
          .sort_by { |_, v| -v }
          .map { |k, v| { key: k, pct: pct(v, grand) } }
      end

      # G78: cap a full, descending, sums-to-100 share list at MAX_BARS.
      # ≤5 segments → all discrete; more → the top 4 stay discrete and the 5th
      # becomes OTHER_KEY carrying the exact remainder (100 − top-4), so the
      # rounded bars always total 100.0 and the long tail is named, not dropped.
      def with_other_rollup(shares)
        return shares if shares.size <= MAX_BARS

        top  = shares.first(MAX_BARS - 1)
        rest = (100.0 - top.sum { |s| s[:pct] }).round(1)
        top + [ { key: OTHER_KEY, pct: rest } ]
      end

      # Share of a bucket out of a total, rounded to 1 decimal place.
      def pct(value, total)
        ((value.to_f / total.to_f) * 100).round(1)
      end
    end
  end
end
