# frozen_string_literal: true

module Pito
  module Analytics
    # Parses the `with` / `without` metric clauses from an `analyze` command (or a
    # reply) and resolves metric-name tokens to MetricOrder symbols.
    #
    #   `analyze vid #1`                 → all available metrics (default)
    #   `analyze vid #1 with views,subs` → ONLY views + subs (whitelist)
    #   `analyze vid #1 without comments` → all available EXCEPT comments (comms alias ok)
    #
    # Vocab = the metric names (canonical MetricOrder keys) + a few obvious aliases.
    module MetricSelection
      Selection = Data.define(:with, :without) do
        def any? = with.any? || without.any?
      end

      # token → metric symbol (aliases on top of the canonical MetricOrder keys).
      ALIASES = {
        "watched"     => :watched_hours,      "hours"      => :watched_hours,
        "duration"    => :avg_view_duration,  "avg_duration" => :avg_view_duration,
        "pct"         => :avg_viewed_pct,      "percent"    => :avg_viewed_pct,
        "viewed"      => :avg_viewed_pct,
        "comms"       => :comments,
        "subscribed"  => :subscribed_status,   "subs_status" => :subscribed_status,
        "geo"         => :geography,            "country"    => :geography,
        "heatmap"     => :day_of_week_heatmap,  "weekday"    => :day_of_week_heatmap,
        "gender"      => :demographics_gender,
        "age"         => :demographics_age,
        "device"      => :devices,
        "retention"   => :retention
      }.freeze

      module_function

      def parse(raw)
        Selection.new(with: clause_metrics(raw, "with"), without: clause_metrics(raw, "without"))
      end

      # Build a Selection from already-resolved symbol arrays (e.g. round-tripped
      # from a marker), dropping anything unknown.
      def from_lists(with_list, without_list)
        Selection.new(with: symbolize(with_list), without: symbolize(without_list))
      end

      # Apply a selection to an ORDERED list of metric symbols (preserves order).
      def apply(metrics, selection)
        kept = selection.with.any? ? metrics.select { |m| selection.with.include?(m) } : metrics
        kept.reject { |m| selection.without.include?(m) }
      end

      # ── internals ───────────────────────────────────────────────────────────

      # Tokens after `with`/`without`, up to the next clause keyword or end.
      def clause_metrics(raw, keyword)
        match = raw.to_s.match(/(?:\A|\s)#{keyword}\b\s+(.+?)(?=\s(?:with|without)\b|\z)/i)
        return [] unless match

        match[1].split(/[\s,]+/).filter_map { |t| resolve(t.strip.downcase) }.uniq
      end

      def resolve(token)
        return nil if token.blank?

        sym = token.to_sym
        return sym if MetricOrder::METRICS.key?(sym)

        ALIASES[token]
      end

      def symbolize(list)
        Array(list).filter_map { |t| resolve(t.to_s.downcase) }.uniq
      end
    end
  end
end
