# frozen_string_literal: true

module Pito
  module Analytics
    # Reusable kv-table of scalar analytics metrics in a CSS grid.
    # Scope-agnostic — it takes a `Pito::Analytics::Scalars::Result`, so the
    # same table serves a video, a game (linked-video aggregate), or a channel.
    #
    # Layout (grid-cols-6):
    #   Row 1 (col-span-3 each): Views | Watched hours
    #   Row 2 (col-span-3 each): Avg view duration | Avg viewed %
    #   Row 3 (col-span-2 each): Subs | Likes | Comments
    #
    # Special cells:
    #   - Subs:  "+gained/-lost" — the +gained half green (:up shimmer), the
    #            -lost half red (:down shimmer); coloured by part, not net sign.
    #   - Likes: "<likes>👍/<dislikes>👎" — likes + thumbs-up green (:up), dislikes
    #            + thumbs-down red (:down). Replaces the standalone Dislikes cell.
    #   - Comments: word label + a plain trend-coloured count.
    #
    # The green/red shimmer reuses the TrendNumberComponent `.pito-trend-number`
    # classes so the numbers shimmer and the icons pick up the accent colour.
    class ScalarsTableComponent < ViewComponent::Base
      EM_DASH = "—"

      # Row 1 metric configs.
      ROW1 = [
        { key: :views,         label: "views",       polarity: true, format: :count },
        { key: :watched_hours, label: "watch_hours", polarity: true, format: :hours }
      ].freeze

      # Row 2 metric configs. (avg_viewed_pct removed from the glance — owner 2026-06-29.)
      ROW2 = [
        { key: :avg_view_duration, label: "avg_view_duration", polarity: true, format: :duration }
      ].freeze

      # @param series [Hash{Symbol=>Array}] optional day-series per metric
      #   (views/watched_hours/avg_view_duration/subs/likes) from
      #   Pito::Analytics::GlanceSeries — each renders a 2-row braille sparkline
      #   (Metric::SparklineComponent) above its scalar.
      def initialize(result:, series: {})
        @result = result
        @series = series || {}
      end

      def row1_cells = build_cells(ROW1)
      def row2_cells = build_cells(ROW2)

      # Ordered flat array of all metric cells for the flex-wrap layout.
      # Canonical order: views → watched_hours → avg_view_duration → subs → likes.
      # (avg_viewed_pct + comments removed from the glance — owner 2026-06-29; the
      # five remaining metrics all carry a GlanceSeries sparkline.)
      def cells
        build_cells(ROW1) + build_cells(ROW2) + [ subs_cell, likes_cell ]
      end

      # ── Row 3 cells (each `{ label:, value: }` with a pre-rendered value) ──

      # Subs: "+gained/-lost" — green +gained, red -lost (em dash when no data).
      def subs_cell
        gained = @result.metrics.dig(:subs_gained, :current)
        lost   = @result.metrics.dig(:subs_lost,   :current)
        value  =
          if gained.nil? && lost.nil?
            em_dash
          else
            split_value(
              up:   "+#{Pito::Formatter::CompactCount.call(gained.to_i)}",
              down: "-#{Pito::Formatter::CompactCount.call(lost.to_i)}"
            )
          end
        { label: metric_label("subs_net"), series: @series[:subs], value: }
      end

      # Likes: "<likes>👍/<dislikes>👎" — green likes, red dislikes (em dash when
      # neither side has data).
      def likes_cell
        likes    = @result.metrics.dig(:likes,    :current)
        dislikes = @result.metrics.dig(:dislikes, :current)
        value    =
          if likes.nil? && dislikes.nil?
            em_dash
          else
            split_value(
              up:   icon_count(likes,    "thumbs-up",   metric_label("likes")),
              down: icon_count(dislikes, "thumbs-down", metric_label("dislikes"))
            )
          end
        { label: metric_label("likes"), series: @series[:likes], value: }
      end

      private

      def build_cells(cfg_list)
        cfg_list.map do |cfg|
          metric = @result.metrics[cfg[:key]] || {}
          {
            label:  metric_label(cfg[:label]),
            series: @series[cfg[:key]],
            value:  render(Pito::Analytics::TrendNumberComponent.new(
              value:            metric[:current],
              previous:         metric[:previous],
              comparable:       @result.comparable,
              higher_is_better: cfg[:polarity],
              display:          format_value(cfg[:format], metric[:current])
            ))
          }
        end
      end

      def metric_label(key)
        Pito::Copy.render("pito.copy.analytics.metrics.#{key}")
      end

      def em_dash = tag.span(EM_DASH)

      # "<up> / <down>" with the up half green-shimmered, the down half red.
      #
      # Both halves share ONE shimmer offset so they pulse together (same
      # animation-delay) instead of drifting out of phase — the split reads as a
      # single shimmer unit. The "/" carries a space on each side so the values
      # breathe (e.g. "0👍 / 0👎", "+0 / -0") rather than touching the separator.
      def split_value(up:, down:)
        offset = Pito::Shimmer.offset_class("#{up}#{down}")
        safe_join([
          shimmer_span(up,   :up,   offset),
          tag.span(" / ", class: "text-fg-dim"),
          shimmer_span(down, :down, offset)
        ])
      end

      # A count + inline icon (e.g. "210👍"). The icon lives INSIDE the
      # .pito-trend-number--up/--down shimmer span, so it rides the same green/red
      # shimmer as its number (animated currentColor; see .pito-trend-number--up
      # .pito-icon in application.css) — number and icon shimmer as one unit.
      def icon_count(value, icon, label)
        safe_join([
          Pito::Formatter::CompactCount.call(value.to_i),
          render(Pito::IconComponent.new(name: icon, label: label))
        ])
      end

      # Reuses the TrendNumberComponent green/red shimmer classes so the number
      # shimmers and any child icon picks up the green/red accent colour. An
      # explicit `offset` lets a split value share ONE stagger across both halves
      # so they pulse in phase; falls back to a per-content offset otherwise.
      def shimmer_span(content, direction, offset = nil)
        offset ||= Pito::Shimmer.offset_class(content.to_s)
        css = "pito-trend-number pito-trend-number--#{direction} #{offset}"
        tag.span(content, class: css, data: { trend: direction })
      end

      def format_value(format, value)
        return EM_DASH if value.nil?

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
