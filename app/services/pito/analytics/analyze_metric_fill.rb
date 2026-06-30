# frozen_string_literal: true

module Pito
  module Analytics
    # Fetches ONE analyze metric via its OWN dedicated YouTube Analytics request(s).
    # Returns a cell-data Hash for that metric in the same shape that
    # Pito::MessageBuilder::Analyze::Message#cells_for produces, or
    # { no_data: true, caption: <label> } when there is nothing to show or an
    # error occurs. This is the per-metric, dedicated-request analog of the
    # at-a-glance Pito::Analytics::MetricFill — each metric makes its OWN YouTube
    # request(s), with NO shared primitives cache between metrics.
    #
    # Period rules
    #   AREA metrics (views / watched_hours / subs / avg_view_duration /
    #                 avg_viewed_pct)               → use the passed `period` window.
    #   likes (HEART)                               → LIFETIME always.
    #   BAR metrics (subscribed_status / devices /
    #               geography / demographics_gender
    #               / demographics_age)             → LIFETIME always.
    #   comments                                    → plain scalar; passed `period`.
    #   retention + day_of_week_heatmap             → { no_data:, caption: } only
    #                                                 (components not yet built).
    #
    # Fault isolation: any StandardError per call → returns the no_data cell and
    # logs a warning. Never raises.
    module AnalyzeMetricFill
      AREA_METRICS = %i[views watched_hours subs avg_view_duration avg_viewed_pct].freeze

      # MetricOrder symbol → Breakdown metric symbol.
      BAR_METRICS = {
        subscribed_status:   :subscribed_status,
        devices:             :devices,
        geography:           :geography,
        demographics_gender: :gender,
        demographics_age:    :age
      }.freeze

      # Metrics whose components are not yet built — always return no_data.
      STUB_METRICS = %i[retention day_of_week_heatmap].freeze

      module_function

      # @param metric     [Symbol]
      # @param level      [String, Symbol]  "channel" | "vid" | "game"
      # @param entity_ids [Array<Integer>]
      # @param period     [String]          shift+space window token (e.g. "28d")
      # @return [Hash]
      def for(metric:, level:, entity_ids:, period:)
        metric = metric.to_sym
        return no_data_cell(metric) if STUB_METRICS.include?(metric)

        groups = groups_for(level, entity_ids)
        return no_data_cell(metric) if groups.empty?

        dispatch(metric:, groups:, level: level.to_s, period:)
      rescue StandardError => e
        Rails.logger.warn("[Analytics::AnalyzeMetricFill] #{metric} #{level} #{entity_ids.inspect}: #{e.class}: #{e.message}")
        no_data_cell(metric)
      end

      # ── per-metric dispatch ─────────────────────────────────────────────────────

      def dispatch(metric:, groups:, level:, period:)
        if AREA_METRICS.include?(metric)
          area_cell(metric:, groups:, period:)
        elsif metric == :likes
          likes_cell(groups:, level:)
        elsif (breakdown_metric = BAR_METRICS[metric])
          bar_cell_for(metric:, breakdown_metric:, groups:)
        elsif metric == :comments
          comments_cell(groups:, period:)
        else
          no_data_cell(metric)
        end
      end

      # ── AREA (chart) cells ───────────────────────────────────────────────────────

      def area_cell(metric:, groups:, period:)
        window   = Pito::Analytics::Window.for(period, reference_date: Date.current)
        subs     = subs_for_groups(groups)
        views_td = Pito::Analytics::Thresholds.views_target_daily(subs:)
        target   = Pito::Analytics::Thresholds.target_daily(metric:, subs:, views_target_daily: views_td)

        chart = case metric
        when :avg_view_duration
          compute_avg_view_duration(groups:, window:, target:)
        when :avg_viewed_pct
          # avg_view_duration total feeds the M:SS component of the caption.
          avd_target = Pito::Analytics::Thresholds.target_daily(metric: :avg_view_duration, subs:)
          avd_chart  = compute_avg_view_duration(groups:, window:, target: avd_target)
          compute_avg_viewed_pct(groups:, window:, target:, computed_charts: { avg_view_duration: avd_chart })
        else
          compute_daily_chart(metric:, groups:, window:, target:)
        end

        return no_data_cell(metric) if chart.nil?

        caption = Pito::MessageBuilder::Analyze::Message.render_chart_caption(metric:, chart:)
        {
          chart:           metric,
          series:          Array(chart["series"]),
          target_daily:    chart["target_daily"].to_f,
          caption:         caption,
          trend:           chart.fetch("trend", true),
          reference_token: chart["reference_token"],
          dates:           chart["dates"]
        }
      end

      # ── HEART (likes) cell ───────────────────────────────────────────────────────

      def likes_cell(groups:, level:)
        likes_data = Pito::Analytics::LikesHearts.for(groups:, level: level.to_s)
        return no_data_cell(:likes) if likes_data.blank?

        marker = Pito::MessageBuilder::Analyze::Message.likes_marker(likes_data)
        return no_data_cell(:likes) if marker.nil?

        Pito::MessageBuilder::Analyze::Message.heart_cell(marker)
      end

      # ── BAR cells ────────────────────────────────────────────────────────────────

      def bar_cell_for(metric:, breakdown_metric:, groups:)
        lifetime = Pito::Analytics::Window.for("lifetime", reference_date: Date.current)
        rows     = Pito::Analytics::Breakdown.for(metric: breakdown_metric, groups:, window: lifetime)
        return no_data_cell(metric) if rows.blank?

        caption = Pito::MessageBuilder::Analyze::Message.render_bar_caption(metric)
        Pito::MessageBuilder::Analyze::Message.bar_cell(metric, rows, caption)
      end

      # ── comments scalar cell ─────────────────────────────────────────────────────

      def comments_cell(groups:, period:)
        window = Pito::Analytics::Window.for(period, reference_date: Date.current)
        data   = Pito::Analytics::Primitives.fetch(groups:, window:, report: "scalars")
        total  = data.values.sum { |row| row.is_a?(Hash) ? (row["comments"] || row[:comments]).to_i : 0 }
        label  = Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(:comments))
        { label:, value: total.to_s }
      end

      # ── chart compute helpers (mirrors AnalyzePrepareJob) ────────────────────────

      # Adaptive-bucketed avg view duration chart (trend always false — no baseline).
      def compute_avg_view_duration(groups:, window:, target:)
        result = Pito::Analytics::AdaptiveSeries.for(groups:, window:)
        {
          "series"       => result.series,
          "total"        => result.total,
          "previous"     => nil,
          "target_daily" => target,
          "trend"        => false,
          "dates"        => result.dates.map(&:iso8601)
        }
      end

      # Views-weighted average audience-retention chart (lifetime window always;
      # trend false — no baseline). `computed_charts` provides the avg_view_duration
      # total (seconds) for the M:SS caption.
      def compute_avg_viewed_pct(groups:, window:, target:, computed_charts:)
        result          = Pito::Analytics::RetentionSeries.for(groups:, window:)
        avg_dur_seconds = computed_charts.dig(:avg_view_duration, "total")
        at_mark         = Pito::Analytics::RetentionSeries.at_mark_pct(result.series, result.total_pct)
        benchmark       = Pito::Analytics::RetentionSeries.benchmark_word(result.rel_performance)
        {
          "series"               => result.series,
          "total_pct"            => result.total_pct,
          "avg_duration_seconds" => avg_dur_seconds,
          "previous"             => nil,
          "target_daily"         => target,
          "trend"                => false,
          "reference_token"      => "lifetime",
          "at_mark_pct"          => at_mark,
          "benchmark_word"       => benchmark
        }
      end

      # Standard daily-series chart (views / watched_hours / subs) with trend.
      def compute_daily_chart(metric:, groups:, window:, target:)
        daily       = fetch_daily_for_metric(metric, groups, window)
        prev_window = window.previous
        previous    = prev_window && fetch_daily_for_metric(metric, groups, prev_window).total
        {
          "series"       => daily.series,
          "total"        => daily.total,
          "previous"     => previous,
          "target_daily" => target,
          "dates"        => daily.dates.map(&:iso8601)
        }
      end

      # Fold the daily primitives for a scope into a per-day series for `metric`.
      def fetch_daily_for_metric(metric, groups, window)
        case metric
        when :views
          Pito::Analytics::DailySeries.for(groups:, window:)
        when :watched_hours
          raw    = Pito::Analytics::DailySeries.for(groups:, window:, metric: "estimated_minutes_watched")
          series = raw.series.map { |m| (m / 60.0).round(2) }
          total  = (raw.total / 60.0).round(2)
          Pito::Analytics::DailySeries::Result.new(dates: raw.dates, series:, total:)
        when :subs
          gained = Pito::Analytics::DailySeries.for(groups:, window:, metric: "subscribers_gained")
          lost   = Pito::Analytics::DailySeries.for(groups:, window:, metric: "subscribers_lost")
          series = gained.series.zip(lost.series).map { |g, l| g - l }
          Pito::Analytics::DailySeries::Result.new(dates: gained.dates, series:, total: series.sum)
        else
          Pito::Analytics::DailySeries.for(groups:, window:)
        end
      end

      # ── scope resolution (mirrors AnalyzePrepareJob#groups_for) ─────────────────

      def groups_for(level, ids)
        case level.to_s
        when "channel"
          ::Channel.where(id: ids).select { |c| usable?(c) }.map { |c| [ c, :channel ] }
        when "vid"
          ::Video.where(id: ids).includes(:channel).group_by(&:channel)
                 .filter_map { |ch, vids| usable_group(ch, vids) }
        when "game"
          ::Video.joins(:video_game_links).where(video_game_links: { game_id: ids })
                 .includes(:channel).distinct.group_by(&:channel)
                 .filter_map { |ch, vids| usable_group(ch, vids) }
        else
          []
        end
      end

      def usable_group(channel, videos)
        return nil unless usable?(channel)

        ids = videos.filter_map(&:youtube_video_id)
        ids.empty? ? nil : [ channel, ids ]
      end

      def usable?(channel)
        conn = channel&.youtube_connection
        conn.present? && !conn.needs_reauth
      end

      # ── helpers ──────────────────────────────────────────────────────────────────

      # Sum subscriber counts across the distinct channels in the scope's groups.
      def subs_for_groups(groups)
        groups.filter_map { |ch, _| ch }.uniq(&:id).sum { |c| c.subscriber_count.to_i }
      end

      def no_data_cell(metric)
        { no_data: true, caption: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric.to_sym)) }
      end
    end
  end
end
