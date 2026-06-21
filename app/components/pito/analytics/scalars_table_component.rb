# frozen_string_literal: true

module Pito
  module Analytics
    # Reusable kv-table of scalar analytics metrics in a 4-row CSS grid.
    # Scope-agnostic — it takes a `Pito::Analytics::Scalars::Result`, so the
    # same table serves a video, a game (linked-video aggregate), or a channel.
    #
    # Layout:
    #   Row 1 (col-span-3 each): Views | Watch hours
    #   Row 2 (col-span-3 each): Avg view duration | Avg viewed %
    #   Row 3 (col-span-6):      Subs (net gained − lost)
    #   Row 4 (col-span-2 each): Likes | Dislikes | Comms
    #
    # Polarity: `dislikes` is more-is-worse (`higher_is_better: false`).
    # Subs net is always coloured by sign (green/red/neutral), independent of the
    # comparable window.
    class ScalarsTableComponent < ViewComponent::Base
      # Row 1 metric configs.
      ROW1 = [
        { key: :views,         label: "views",       polarity: true, format: :count },
        { key: :watched_hours, label: "watch_hours", polarity: true, format: :hours }
      ].freeze

      # Row 2 metric configs.
      ROW2 = [
        { key: :avg_view_duration, label: "avg_view_duration", polarity: true, format: :duration },
        { key: :avg_viewed_pct,    label: "avg_viewed_pct",    polarity: true, format: :percent }
      ].freeze

      # Row 4 metric configs.
      ROW4 = [
        { key: :likes,    label: "likes",    polarity: true,  format: :count },
        { key: :dislikes, label: "dislikes", polarity: false, format: :count },
        { key: :comments, label: "comments", polarity: true,  format: :count }
      ].freeze

      def initialize(result:)
        @result = result
      end

      def row1_cells = build_cells(ROW1)
      def row2_cells = build_cells(ROW2)
      def row4_cells = build_cells(ROW4)

      # Returns `{ label:, trend: }` for the net-subs cell (Row 3).
      #
      # Net = subs_gained − subs_lost. Coloured by sign regardless of the
      # comparable window: positive → :up (green), negative → :down (red),
      # zero or no-data → :neutral (plain fg, shows "—").
      def row3_subs_net
        gained = @result.metrics[:subs_gained] || {}
        lost   = @result.metrics[:subs_lost]   || {}

        gained_current = gained[:current]
        lost_current   = lost[:current]

        label = Pito::Copy.render("pito.copy.analytics.metrics.subs_net")
        trend = net_subs_trend_component(gained_current, lost_current)
        { label:, trend: }
      end

      private

      def build_cells(cfg_list)
        cfg_list.map do |cfg|
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

      # Builds the TrendNumberComponent for the net-subs cell.
      #
      # Colour is determined by the sign of (gained − lost):
      #   net > 0 → :up   (pass previous: 0 so TrendNumber sees growth-from-nothing)
      #   net < 0 → :down (pass previous: 1 so current < previous → :down)
      #   net = 0 or both nil → :neutral (pass value: nil)
      def net_subs_trend_component(gained_current, lost_current)
        both_nil = gained_current.nil? && lost_current.nil?

        if both_nil
          return Pito::Analytics::TrendNumberComponent.new(
            value: nil, previous: 0, comparable: true,
            higher_is_better: true, display: "—"
          )
        end

        net = gained_current.to_i - lost_current.to_i

        if net > 0
          display  = "+#{Pito::Formatter::CompactCount.call(net)}"
          value    = net
          previous = 0   # growth-from-nothing path in TrendNumber → :up
        elsif net < 0
          display  = "-#{Pito::Formatter::CompactCount.call(net.abs)}"
          value    = net
          previous = 1   # current (negative) < previous (1) → Trend.for → :down
        else
          # Zero net — neutral, show em dash
          return Pito::Analytics::TrendNumberComponent.new(
            value: nil, previous: 0, comparable: true,
            higher_is_better: true, display: "—"
          )
        end

        Pito::Analytics::TrendNumberComponent.new(
          value:, previous:, comparable: true,
          higher_is_better: true, display:
        )
      end

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
