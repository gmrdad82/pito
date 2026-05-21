# Phase 26 — 01g. Viewer-time analytics implementation.
#
# Per-video sync job. Pulls viewer-time buckets for the given video
# from the YouTube Analytics API and upserts rows into
# `video_viewer_time_buckets`. Idempotent — the unique index on
# `(video_id, day_of_week_utc, hour_of_day_utc)` collapses repeat
# rows; `upsert_all` overwrites view + watch totals so each run lands
# the latest snapshot.
#
# Quota-aware: a 401 from the Analytics API flips
# `connection.needs_reauth` (via `Channel::Youtube::AnalyticsClient::AuthError`)
# and exits cleanly. A 403 (quota exhausted) raises and bubbles up to
# Sidekiq's retry policy — `sidekiq_options retry: 0` would burn the
# job; we let the default retry/backoff carry it through so the daily
# refresh can self-heal once the quota window resets.
class VideoViewerTimeSyncJob
  include Sidekiq::Job
  sidekiq_options queue: "analytics", retry: 5

  REFRESH_DAYS = 1

  def perform(video_id, days = REFRESH_DAYS)
    video = Video.find_by(id: video_id)
    return unless video

    channel = video.channel
    return if channel.nil?

    connection = channel.youtube_connection
    return if connection.nil? || connection.needs_reauth?

    client = Channel::Youtube::AnalyticsClient.new(connection: connection)
    today = client.today_pt
    from = today - days.to_i
    to = today - 1

    response = client.video_viewer_time(video: video, from: from, to: to)
    rows = parse_rows(response, video: video)
    return if rows.empty?

    VideoViewerTimeBucket.upsert_all(
      rows,
      unique_by: %i[video_id day_of_week_utc hour_of_day_utc]
    )
  rescue Channel::Youtube::AnalyticsClient::AuthError
    Rails.logger.warn(
      "[viewer-time-sync] video #{video_id} skipped — connection " \
      "#{connection&.id} needs reauth"
    )
    nil
  end

  private

  def parse_rows(response, video:)
    headers = header_names(response[:column_headers])
    aggregated = Hash.new { |h, k| h[k] = { views: 0, watch_minutes: 0 } }

    Array(response[:rows]).each do |row|
      pairs = headers.zip(row).to_h
      day_str = pairs["day"].to_s
      hour    = pairs["hour"]
      next if day_str.blank? || hour.nil?

      date = safe_parse_date(day_str)
      next if date.nil?

      key = [ date.wday, hour.to_i ]
      aggregated[key][:views] += pairs["views"].to_i
      aggregated[key][:watch_minutes] += pairs["estimatedMinutesWatched"].to_i
    end

    now = Time.current
    aggregated.map do |(dow, hod), totals|
      {
        video_id: video.id,
        day_of_week_utc: dow,
        hour_of_day_utc: hod,
        view_count: totals[:views],
        watch_time_seconds: totals[:watch_minutes] * 60,
        last_synced_at: now,
        created_at: now,
        updated_at: now
      }
    end
  end

  def header_names(headers)
    Array(headers).map { |h| h.is_a?(Hash) ? h[:name].to_s : h.to_s }
  end

  def safe_parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
