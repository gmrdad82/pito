# frozen_string_literal: true

# Fills the `analyze` :system + :enhanced messages for a turn, then completes it.
#
# The analyze handler emits TWO pending messages (roles system + enhanced) sharing
# ONE scope; the Finalizer's analyze-pending gate enqueues this job and defers each
# message's per-message thinking-indicator resolve + turn completion to here. So
# each message's spinner stays up until ITS data lands, and its "thought for
# xx.xxs" spans the full fan-out + aggregation (started_at was stamped at dispatch).
#
# Per turn: for each pending analyze event, rebuild the scope (level + entity_ids +
# period from the marker) → fetch per-video / per-channel PRIMITIVES (warm-or-cold)
# for the current and prior windows → aggregate → write the ready payload
# (PERSISTED, so a mid/post-job refresh is correct) → replace_event → resolve THAT
# message's indicator. The aggregate is memoised by scope signature so the two
# messages share one fan-out. The turn completes in `ensure`, only once EVERY
# indicator is resolved. Idempotent on retry (already-ready events are skipped).
class AnalyzePrepareJob < ApplicationJob
  queue_as :default

  # Metrics that render as AreaChart cells in the :system role.
  # Computed in this order; each gets its own chart hash in the marker.
  # avg_viewed_pct reads avg_view_duration's result (for the M:SS caption),
  # so avg_view_duration MUST come first.
  CHART_METRICS = %i[views watched_hours subs avg_view_duration avg_viewed_pct].freeze

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    cache = {}
    begin
      pending_events(turn).each do |event|
        marker = event.payload["analyze"]
        data   = (cache[signature(marker)] ||= compute(marker))
        write_ready(event, broadcaster, data:)
        broadcaster.resolve_thinking_for(turn:, message_id: event.id)
      end
    ensure
      broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
    end
  end

  private

  def pending_events(turn)
    turn.events.select { |e| Pito::MessageBuilder::Analyze::Message.pending?(e) }
  end

  # Signature per (level, ids, period, ROLE) — roles need different report sets, so
  # each role computes its own scaffold (memoised so a re-run of the same is free).
  def signature(marker)
    [ marker["level"], Array(marker["entity_ids"]).sort, marker["period"], marker["role"] ].join(":")
  end

  # Returns { scaffold: {metric=>bool}, charts: {metric=>chart_hash}|nil } for the
  # marker's role. `scaffold` is the 0/1 map every metric still uses; `charts` is
  # only populated for the :system role and contains AreaChart data for views,
  # watched_hours, and subs. A nil chart entry means the fetch errored — cells fall
  # back to the scaffold "0" display.
  def compute(marker)
    window   = Pito::Analytics::Window.for(marker["period"], reference_date: Date.current)
    level    = marker["level"]
    ids      = Array(marker["entity_ids"])
    groups   = groups_for(level, ids)
    scaffold = Pito::Analytics::Scaffold.for(groups:, window:, role: marker["role"].to_sym, level: level.to_sym)

    charts = nil
    likes  = nil
    if marker["role"] == "system"
      subs = Pito::Analytics::Thresholds.subs_for(level:, entity_ids: ids)
      # Accumulate results so later metrics can reference earlier ones.
      # avg_viewed_pct reads avg_view_duration's total for the M:SS caption.
      computed = {}
      CHART_METRICS.each do |metric|
        computed[metric] = compute_chart(metric:, groups:, window:, subs:, computed_charts: computed)
      end
      charts = computed
      # Likes HEARTS — ALWAYS lifetime (independent of the message's period).
      likes = Pito::Analytics::LikesHearts.for(groups:, level:)
    end

    { scaffold:, charts:, likes: }
  rescue StandardError => e
    Rails.logger.warn("[AnalyzePrepareJob] #{marker['level']} #{marker['entity_ids'].inspect}: #{e.class}: #{e.message}")
    { scaffold: {}, charts: nil, likes: nil } # empty → every cell renders "0", no chart
  end

  # Returns chart data hash (string-keyed, for jsonb round-trip) for one metric
  # in the scope. Returns nil when groups is empty or a fetch error occurs.
  # `subs` is the subscriber count for the scope.
  # `computed_charts` carries the results of previously computed metrics so
  # later metrics (e.g. avg_viewed_pct) can reference them (e.g. for M:SS).
  def compute_chart(metric:, groups:, window:, subs:, computed_charts: {})
    return nil if groups.empty?

    views_td = Pito::Analytics::Thresholds.views_target_daily(subs:)
    target   = Pito::Analytics::Thresholds.target_daily(metric:, subs:, views_target_daily: views_td)

    case metric
    when :avg_view_duration
      compute_avg_view_duration(groups:, window:, target:)
    when :avg_viewed_pct
      compute_avg_viewed_pct(groups:, window:, target:, computed_charts:)
    else
      compute_daily_chart(metric:, groups:, window:, target:)
    end
  rescue StandardError => e
    Rails.logger.warn("[AnalyzePrepareJob#compute_chart:#{metric}] #{e.class}: #{e.message}")
    nil
  end

  # Adaptive-bucketed avg view duration chart (no trend — always nil previous).
  # `dates` carries the first date of each adaptive bucket (daily/weekly/monthly)
  # so the x-ticks show real dates rather than bucket indices.
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

  # Lifetime retention chart (always lifetime window, views-weighted, no trend).
  # avg_duration_seconds is taken from the already-computed avg_view_duration
  # chart (period total) for the "M:SS (XX.X%)" caption.
  def compute_avg_viewed_pct(groups:, window:, target:, computed_charts:)
    result          = Pito::Analytics::RetentionSeries.for(groups:, window:)
    avg_dur_seconds = computed_charts.dig(:avg_view_duration, "total")

    at_mark   = Pito::Analytics::RetentionSeries.at_mark_pct(result.series, result.total_pct)
    benchmark = Pito::Analytics::RetentionSeries.benchmark_word(result.rel_performance)

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
  # `dates` carries each day's ISO-8601 date so the component can label x-ticks
  # with real dates instead of day indices.
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
      # "trend" key absent → cells_for defaults to true (backward compat)
    }
  end

  # Folds the daily primitives for a scope into a per-day series for `metric`.
  # Handles metric-specific transformations:
  #   :views         → "views" daily sum (integers)
  #   :watched_hours → "estimated_minutes_watched" daily sum, divided by 60 (hours)
  #   :subs          → net subscribers per day: subscribers_gained − subscribers_lost
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
      # Net subs per day: gained − lost. Two folds over the same primitives cache
      # (Primitives.fetch memoises by report+groups+window so no double HTTP call).
      gained = Pito::Analytics::DailySeries.for(groups:, window:, metric: "subscribers_gained")
      lost   = Pito::Analytics::DailySeries.for(groups:, window:, metric: "subscribers_lost")
      series = gained.series.zip(lost.series).map { |g, l| g - l }
      Pito::Analytics::DailySeries::Result.new(dates: gained.dates, series:, total: series.sum)
    else
      Pito::Analytics::DailySeries.for(groups:, window:)
    end
  end

  def write_ready(event, broadcaster, data:)
    event.update!(payload: Pito::MessageBuilder::Analyze::Message.ready_payload(event, data:))
    broadcaster.replace_event(event)
  end

  # level + entity_ids → [[channel, subjects], …] for Primitives.fetch:
  #   channel  → [channel, :channel]              (one channel-wide primitive)
  #   vid/game → [channel, [youtube_video_id, …]] (per-video primitives; games
  #              reuse shared vids across the requested ids)
  def groups_for(level, ids)
    case level
    when "channel"
      ::Channel.where(id: ids).select { |c| usable?(c) }.map { |c| [ c, :channel ] }
    when "vid"
      ::Video.where(id: ids).includes(:channel).group_by(&:channel).filter_map { |ch, vids| usable_group(ch, vids) }
    when "game"
      ::Video.joins(:video_game_links).where(video_game_links: { game_id: ids })
             .includes(:channel).distinct.group_by(&:channel).filter_map { |ch, vids| usable_group(ch, vids) }
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
end
