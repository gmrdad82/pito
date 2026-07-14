# frozen_string_literal: true

# Populates AchievementMetric rows and unlocks Achievement milestones
# for every video, channel, and game — 3×/day (see config/recurring.yml).
#
# Runs after the Pito::Stats passes (stats at 01/09/17 UTC; this job at
# 02/10/18 UTC) so the latest video data is already in the DB when it runs.
#
# == Per-channel flow (one connected channel at a time)
#
#   1. Lifetime per-video analytics (views, estimated_minutes_watched,
#      subscribers_gained) — via the shared Channel::Youtube::
#      LifetimeVideoReport cache (12h max_age; the distribution column
#      reads the same report, so it's fetched at most twice a day).
#   2. Per-video likes/comments — via Channel::Youtube::
#      VideoStatsReadThrough (3h max_age): reads the Pito::Stats rows the
#      stats passes wrote an hour earlier; only stale/missing videos hit
#      the Data API (self-healing when a producer pass failed).
#   3. Write AchievementMetric + run Evaluate for every Video.
#   4. Channel subscriber_count — the Pito::Stats row ChannelSync persists
#      (12h max_age), falling back to one channels.list fetch + persist.
#   5. Write AchievementMetric + run Evaluate for the Channel, using
#      subscriber_count from step 4 and sums of video metrics from step 3.
#   6. Accumulate per-game sums into an in-memory Hash for post-pass rollup.
#
#   Steady state (P20 batching): steps 1-4 make ZERO YouTube calls on the
#   10:00/18:00 runs and one lifetime top_videos call at 02:00 — the fleet
#   (01:00/13:00 syncs, 09:00/17:00 snapshots) already fetched everything.
#
# == Game rollup (after all channels)
#
#   Game sums are accumulated in-memory during the per-channel loop. After
#   all channels finish, the accumulator is flushed: AchievementMetric rows
#   written + Evaluate called per game. This handles cross-channel games
#   naturally (sums across all linked videos, regardless of which channel
#   they belong to) without a second DB read pass.
#
# == Error isolation
#
#   A StandardError rescue wraps each channel's `sync_channel` call so
#   one channel's failure (API error, quota, network) never aborts the run
#   for other channels. Per-video errors in `write_video` are similarly
#   isolated. Game rollup errors are isolated per game.
#
# == Assumptions (not live-validated — stubs only in specs)
#
#   - The Analytics API accepts `channel==<youtube_channel_id>` for owned
#     channels (not just `channel==MINE`). Google's docs allow an explicit
#     channel ID; `MINE` is a convenience form that resolves the same way.
#   - `top_videos` with a start_date of 2005-01-01 and today as end_date
#     returns lifetime totals covering all videos ever published.
#   - The Analytics API returns a row for every video with any activity;
#     videos with zero activity may be absent (treated as all-zeros).
class AchievementsRefreshJob < ApplicationJob
  queue_as :default

  # Freshness windows for the P20 read-throughs — matched to the producer
  # cadence: this job trails each stats pass by 1h (3h covers a failed pass
  # without going stale-blind) and each sync pass by ≤9h (12h ditto).
  VIDEO_STATS_MAX_AGE = 3.hours
  SUBS_MAX_AGE        = 12.hours
  LIFETIME_MAX_AGE    = 12.hours

  def perform
    # game_id → { metric_key → Integer sum }
    game_accumulator = Hash.new { |h, k| h[k] = Hash.new(0) }

    # Collect every newly-unlocked Achievement across the whole run so they can
    # be emitted as notifications after all processing is done.
    @all_unlocked = []

    connected_channels.find_each do |channel|
      sync_channel(channel, game_accumulator)
    end

    sync_games(game_accumulator)

    # Emit one notification per newly-unlocked shiny in ascending-threshold
    # order (stable tiebreak: metric → achievable_type → achievable_id).
    sorted = @all_unlocked.sort_by { |a| [ a.threshold, a.metric, a.achievable_type, a.achievable_id ] }
    sorted.each { |a| Pito::Notifications::Source::ShinyUnlocked.report!(a) }
  end

  private

  def connected_channels
    ::Channel
      .joins(:youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
  end

  # Fetch all metrics for one channel, write AchievementMetrics, run Evaluate,
  # and accumulate game sums. Errors are rescued so sibling channels still run.
  def sync_channel(channel, game_accumulator)
    # 1. Lifetime per-video analytics (views / watch time / subs gained) —
    #    shared cached report (see class header).
    analytics_rows   = ::Channel::Youtube::LifetimeVideoReport.rows_for(
      channel: channel, max_age: LIFETIME_MAX_AGE
    )
    analytics_by_vid = analytics_rows.index_by { |r| r[:video_id] }

    # 2. Per-video likes/comments — fresh Pito::Stats rows, API only for
    #    stale/missing ids (fetch+persist inside the read-through).
    data_by_vid = ::Channel::Youtube::VideoStatsReadThrough.call(
      channel: channel, max_age: VIDEO_STATS_MAX_AGE
    )

    # 3. Per-video write + evaluate; accumulate channel and game sums.
    channel_totals = Hash.new(0)

    channel.videos.find_each do |video|
      write_video(video, analytics_by_vid, data_by_vid, channel_totals, game_accumulator)
    end

    # 4. Channel subscriber count — ChannelSync's persisted row when fresh
    #    (a nil value — hidden-subs channels — falls through to the fetch).
    subs = fresh_subscriber_count(channel) || fetch_subscriber_count(channel)

    # 5. Write channel AchievementMetrics + evaluate.
    write_and_evaluate(channel, {
      "subs"          => subs,
      "views"         => channel_totals[:views],
      "watched_hours" => channel_totals[:watched_hours],
      "likes"         => channel_totals[:likes],
      "comments"      => channel_totals[:comments]
    })
  rescue StandardError => e
    # Isolation stays (siblings run on); the failure ALSO becomes an
    # AppSignal incident — report_error is a no-op when AppSignal is inactive.
    Appsignal.report_error(e)
    Rails.logger.error(
      "AchievementsRefreshJob: failed for channel=#{channel.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  # The subscribers stat row ChannelSync persists on every 01:00/13:00 pass —
  # nil when the row is missing, stale, or holds a nil value (hidden subs).
  def fresh_subscriber_count(channel)
    row = channel.stats.find_by(kind: "subscribers")
    return nil unless row&.synced_at && row.synced_at >= SUBS_MAX_AGE.ago

    row.value&.to_i
  end

  # Fallback: one channels.list fetch, persisted so the NEXT run reads it.
  def fetch_subscriber_count(channel)
    client   = ::Channel::Youtube::Client.new(channel.youtube_connection)
    response = client.channels_list(ids: [ channel.youtube_channel_id ], parts: %i[statistics])
    item     = Array(response[:items]).first || {}
    stats    = item[:statistics] || {}
    subs     = stats[:subscriber_count]&.to_i || 0

    ::Pito::Stats.set(channel, :subscribers, subs)
    subs
  end

  # Compute one video's metrics, write AchievementMetric rows, run Evaluate,
  # and add to the running channel and game sums.
  def write_video(video, analytics_by_vid, data_by_vid, channel_totals, game_accumulator)
    vid_id        = video.youtube_video_id
    analytics_row = analytics_by_vid[vid_id] || {}
    data_row      = data_by_vid[vid_id]       || {}

    views         = analytics_row[:views].to_i
    watched_hours = analytics_row[:estimated_minutes_watched].to_i / 60
    subs_gained   = analytics_row[:subscribers_gained].to_i
    likes         = data_row[:likes].to_i
    comments      = data_row[:comments].to_i

    write_and_evaluate(video, {
      "views"         => views,
      "watched_hours" => watched_hours,
      "subs_gained"   => subs_gained,
      "likes"         => likes,
      "comments"      => comments
    })

    channel_totals[:views]         += views
    channel_totals[:watched_hours] += watched_hours
    channel_totals[:subs_gained]   += subs_gained
    channel_totals[:likes]         += likes
    channel_totals[:comments]      += comments

    video.linked_games.each do |game|
      game_accumulator[game.id][:views]         += views
      game_accumulator[game.id][:watched_hours] += watched_hours
      game_accumulator[game.id][:subs_gained]   += subs_gained
      game_accumulator[game.id][:likes]         += likes
      game_accumulator[game.id][:comments]      += comments
    end
  rescue StandardError => e
    Appsignal.report_error(e)
    Rails.logger.error(
      "AchievementsRefreshJob: failed for video=#{video.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  # After all channels: flush the game accumulator, writing AchievementMetric
  # rows and running Evaluate per game. Errors are isolated per game.
  def sync_games(game_accumulator)
    game_accumulator.each do |game_id, totals|
      game = ::Game.find_by(id: game_id)
      next unless game

      write_and_evaluate(game, {
        "views"         => totals[:views],
        "watched_hours" => totals[:watched_hours],
        "subs_gained"   => totals[:subs_gained],
        "likes"         => totals[:likes],
        "comments"      => totals[:comments]
      })
    rescue StandardError => e
      Appsignal.report_error(e)
      Rails.logger.error(
        "AchievementsRefreshJob: failed for game=#{game_id}: " \
        "#{e.class}: #{e.message}"
      )
    end
  end

  # Upsert AchievementMetric rows and call Evaluate for every valid metric.
  #
  # Filters the supplied `metrics_hash` down to metrics valid for `achievable`'s
  # type (via `Pito::Achievements::Evaluate.metrics_for`), upserts a single
  # AchievementMetric row per metric, then calls Evaluate for each so that
  # any newly-crossed thresholds are unlocked.
  def write_and_evaluate(achievable, metrics_hash)
    valid_metrics = Pito::Achievements::Evaluate.metrics_for(achievable)
    return if valid_metrics.empty?

    now  = Time.current
    type = achievable.class.polymorphic_name
    id   = achievable.id

    rows = metrics_hash.filter_map do |metric, value|
      next unless valid_metrics.include?(metric)

      {
        achievable_type: type,
        achievable_id:   id,
        metric:          metric,
        value:           value,
        synced_at:       now,
        created_at:      now,
        updated_at:      now
      }
    end

    return if rows.empty?

    ::AchievementMetric.upsert_all(
      rows,
      unique_by: %i[achievable_type achievable_id metric]
    )

    metrics_hash.each do |metric, value|
      next unless valid_metrics.include?(metric)

      newly = Pito::Achievements::Evaluate.call(achievable: achievable, metric: metric, value: value)
      @all_unlocked&.concat(newly)
    end
  end
end
