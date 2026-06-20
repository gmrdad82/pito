# frozen_string_literal: true

# Populates AchievementMetric rows and unlocks Achievement milestones
# for every video, channel, and game — 3×/day (see config/recurring.yml).
#
# Runs after the Pito::Stats passes (stats at 01/09/17 UTC; this job at
# 02/10/18 UTC) so the latest video data is already in the DB when it runs.
#
# == Per-channel flow (one connected channel at a time)
#
#   1. Analytics API (lifetime per-video): views, estimated_minutes_watched,
#      subscribers_gained — one `top_videos` call per channel.
#   2. Data API (per-video in batches of 50): like_count, comment_count.
#   3. Write AchievementMetric + run Evaluate for every Video.
#   4. Data API (channel-level): subscriber_count.
#   5. Write AchievementMetric + run Evaluate for the Channel, using
#      subscriber_count from step 4 and sums of video metrics from step 3.
#   6. Accumulate per-game sums into an in-memory Hash for post-pass rollup.
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

  BATCH_SIZE     = 50
  LIFETIME_START = Date.new(2005, 1, 1)

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
    connection = channel.youtube_connection
    analytics  = ::Channel::Youtube::AnalyticsClient.new(connection)
    client     = ::Channel::Youtube::Client.new(connection)

    # 1. Lifetime per-video analytics (views / watch time / subs gained).
    analytics_rows   = analytics.top_videos(
      channel_id: channel.youtube_channel_id,
      start_date: LIFETIME_START,
      end_date:   Date.current
    )
    analytics_by_vid = analytics_rows.index_by { |r| r[:video_id] }

    # 2. Per-video Data API stats (likes, comments) in batches of ≤50.
    video_ids   = channel.videos.pluck(:youtube_video_id).compact
    data_by_vid = {}

    video_ids.each_slice(BATCH_SIZE) do |batch|
      response = client.videos_list(ids: batch, parts: %i[statistics])
      Array(response[:items]).each do |item|
        stats = item[:statistics] || {}
        data_by_vid[item[:id].to_s] = {
          likes:    stats[:like_count]&.to_i    || 0,
          comments: stats[:comment_count]&.to_i || 0
        }
      end
    end

    # 3. Per-video write + evaluate; accumulate channel and game sums.
    channel_totals = Hash.new(0)

    channel.videos.find_each do |video|
      write_video(video, analytics_by_vid, data_by_vid, channel_totals, game_accumulator)
    end

    # 4. Channel subscriber count from Data API.
    ch_response = client.channels_list(ids: [ channel.youtube_channel_id ], parts: %i[statistics])
    ch_item     = Array(ch_response[:items]).first || {}
    ch_stats    = ch_item[:statistics] || {}
    subs        = ch_stats[:subscriber_count]&.to_i || 0

    # 5. Write channel AchievementMetrics + evaluate.
    write_and_evaluate(channel, {
      "subs"          => subs,
      "views"         => channel_totals[:views],
      "watched_hours" => channel_totals[:watched_hours],
      "likes"         => channel_totals[:likes],
      "comments"      => channel_totals[:comments]
    })
  rescue StandardError => e
    Rails.logger.error(
      "AchievementsRefreshJob: failed for channel=#{channel.id}: " \
      "#{e.class}: #{e.message}"
    )
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
