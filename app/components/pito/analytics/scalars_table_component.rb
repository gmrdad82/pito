# frozen_string_literal: true

module Pito
  module Analytics
    # Reusable kv-table of scalar analytics metrics, one row per metric: a label
    # and a `TrendNumberComponent` value coloured by its trend vs the prior
    # window. Scope-agnostic — it takes a `Pito::Analytics::Scalars::Result`, so
    # the same table serves a video, a game (linked-video aggregate), or a
    # channel.
    #
    # Polarity: `subs_lost` and `dislikes` are more-is-worse (`higher_is_better:
    # false`) so a rise reads red-down. All others are higher-is-better.
    class ScalarsTableComponent < ViewComponent::Base
      # Render order + per-metric config: copy label key, polarity, value format.
      METRICS = [
        { key: :views,             label: "views",             polarity: true,  format: :count },
        { key: :watched_hours,     label: "watch_hours",       polarity: true,  format: :hours },
        { key: :avg_view_duration, label: "avg_view_duration", polarity: true,  format: :duration },
        { key: :avg_viewed_pct,    label: "avg_viewed_pct",    polarity: true,  format: :percent },
        { key: :subs_gained,       label: "subs_gained",       polarity: true,  format: :count },
        { key: :subs_lost,         label: "subs_lost",         polarity: false, format: :count },
        { key: :likes,             label: "likes",             polarity: true,  format: :count },
        { key: :dislikes,          label: "dislikes",          polarity: false, format: :count },
        { key: :comments,          label: "comments",          polarity: true,  format: :count }
      ].freeze

      def initialize(result:)
        @result = result
      end

      def rows
        METRICS.map do |cfg|
          metric = @result.metrics[cfg[:key]] || {}
          {
            label: Pito::Copy.render("pito.copy.analytics.metrics.#{cfg[:label]}"),
            trend: Pito::Analytics::TrendNumberComponent.new(
              value:            metric[:current],
              previous:         metric[:previous],
              comparable:       @result.comparable,
              higher_is_better: cfg[:polarity],
              display:          format_value(cfg[:format], metric[:current])
            )
          }
        end
      end

      private

      def format_value(format, value)
        return "—" if value.nil?

        case format
        when :count    then Pito::Formatter::CompactCount.call(value)
        when :percent  then "#{value.round}%"
        when :duration then format_duration(value)
        when :hours    then format_hours(value)
        end
      end

      # Hours with a decimal under 10 (so a small channel's "0.5h" isn't "0"),
      # compact above (e.g. "1.2Kh").
      def format_hours(hours)
        return "0h" if hours.to_f.zero?

        hours < 10 ? "#{hours.round(1)}h" : "#{Pito::Formatter::CompactCount.call(hours.round)}h"
      end

      def format_duration(seconds)
        s = seconds.to_i
        format("%d:%02d", s / 60, s % 60)
      end
    end
  end
end
