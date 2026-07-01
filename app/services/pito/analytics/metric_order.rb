# frozen_string_literal: true

module Pito
  module Analytics
    # The owner-defined metric ORDER per analyze message role, each metric's label
    # + backing report group, and per-metric entity availability.
    #
    # "Sort available": render a role's metrics in this exact order, SKIPPING any not
    # available for the entity level (e.g. retention is single-video only → skipped
    # for channel/game). The analyze messages render every listed metric as a `0`/`1`
    # data-pulled scaffold (one generic cell) for now; bespoke per-metric components
    # come on the owner's "revisit".
    module MetricOrder
      # metric → { label: copy-key suffix under pito.copy.analytics.metrics,
      #            report: the Primitives report group, vid_only: restricted to videos }
      METRICS = {
        views:               { label: "views",               report: "scalars" },
        subs:                { label: "subs_net",             report: "scalars" },
        likes:               { label: "likes",               report: "scalars" },
        watched_hours:       { label: "watch_hours",          report: "scalars" },
        avg_view_duration:   { label: "avg_view_duration",    report: "scalars" },
        avg_viewed_pct:      { label: "avg_viewed_pct",       report: "scalars" },
        comments:            { label: "comments",             report: "daily" },
        subscribed_status:   { label: "subscribed_status",    report: "subscribed_status" },
        retention:           { label: "retention",            report: "retention" },
        devices:             { label: "devices",              report: "device" },
        geography:           { label: "geography",            report: "country" },
        day_of_week_heatmap: { label: "day_of_week_heatmap",  report: "daily" },
        demographics_gender: { label: "demographics_gender",  report: "demographics" },
        demographics_age:    { label: "demographics_age",     report: "demographics" }
      }.freeze

      # Owner-defined order. :system groups the area-chart metrics first (the visual
      # charts together at the top), then the likes heart + remaining scalars.
      # :enhanced LEADS with the day-of-week heatmap (owner 2026-07-01), then the
      # lifetime audience-composition BARS (subscribers, device, country/geography,
      # age, gender), retention (now on channel + game too, not vid-only), and
      # finally comments as an Area chart in the LAST position (moved :system →
      # :enhanced 2026-07-01). (subscribers moved :system → :enhanced 2026-06-29.)
      SYSTEM   = %i[views watched_hours subs avg_view_duration avg_viewed_pct likes].freeze
      ENHANCED = %i[day_of_week_heatmap subscribed_status devices geography demographics_age demographics_gender retention comments].freeze
      ROLE_METRICS = { system: SYSTEM, enhanced: ENHANCED }.freeze

      module_function

      # Ordered metrics for a role, filtered to those available for the entity level.
      # @param role  [Symbol/String] :system | :enhanced
      # @param level [Symbol/String] :channel | :vid | :game
      # @return [Array<Symbol>]
      def for(role:, level:)
        ROLE_METRICS.fetch(role.to_sym).select { |metric| available?(metric, level) }
      end

      def available?(metric, level)
        meta = METRICS.fetch(metric)
        return level.to_sym == :vid if meta[:vid_only]

        true
      end

      def label_key(metric)
        "pito.copy.analytics.metrics.#{METRICS.fetch(metric)[:label]}"
      end

      def report(metric)
        METRICS.fetch(metric)[:report]
      end

      # Distinct report groups a role+level needs (for the fan-out).
      def reports(role:, level:)
        self.for(role:, level:).map { |metric| report(metric) }.uniq
      end
    end
  end
end
