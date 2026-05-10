# Phase 13.2 — Analytics sync engine. Per-video V7 retention curve.
# Fired by `VideoRetentionSyncOrchestrator` weekly (Mondays at 05:00
# UTC) and on-demand from the dashboard.
class VideoRetentionSync
  include Sidekiq::Job
  sidekiq_options queue: "analytics", retry: 5

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    channel = video.channel
    return if channel.nil?

    connection = channel.youtube_connection
    return if connection.nil? || connection.needs_reauth?

    client = Youtube::AnalyticsClient.new(connection: connection)
    response = client.video_retention(video: video)
    rows = parse_rows(response, video: video)
    return if rows.empty?

    VideoRetention.transaction do
      VideoRetention.where(video_id: video.id).delete_all
      VideoRetention.insert_all(rows, unique_by: %i[video_id elapsed_ratio_bucket])
    end
  rescue Youtube::AnalyticsClient::AuthError
    Rails.logger.warn(
      "[analytics-sync] retention skipped for video #{video_id}; connection #{connection&.id} needs reauth"
    )
    nil
  end

  private

  def parse_rows(response, video:)
    headers = header_names(response[:column_headers])
    response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      bucket = pairs["elapsedVideoTimeRatio"]
      next if bucket.nil?

      {
        video_id: video.id,
        elapsed_ratio_bucket: BigDecimal(bucket.to_s),
        audience_watch_ratio: dec_or_nil(pairs["audienceWatchRatio"]),
        relative_retention_performance: dec_or_nil(pairs["relativeRetentionPerformance"]),
        started_watching: int_or_zero(pairs["startedWatching"]),
        stopped_watching: int_or_zero(pairs["stoppedWatching"]),
        total_segment_impressions: int_or_zero(pairs["totalSegmentImpressions"]),
        computed_at: Time.current
      }
    end
  end

  def header_names(headers)
    Array(headers).map { |h| h.is_a?(Hash) ? h[:name].to_s : h.to_s }
  end

  def int_or_zero(value)
    value.nil? ? 0 : value.to_i
  end

  def dec_or_nil(value)
    value.nil? ? nil : BigDecimal(value.to_s)
  end
end
