class VideoDecorator < ApplicationDecorator
  # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
  # Video is a thin YouTube-reference record: id, channel_id,
  # youtube_video_id, star, youtube_connection_id, last_synced_at,
  # timestamps. All title / description / tags / privacy / metadata is
  # gone. JSON surface collapses around the surviving columns.
  def as_summary_json
    {
      id: id,
      youtube_video_id: youtube_video_id,
      channel_id: channel_id,
      channel_url: channel&.channel_url,
      star: YesNo.to_yes_no(star),
      views: total_views_value,
      likes: total_likes_value,
      comments: total_comments_value,
      watch_time_minutes: total_watch_time_value,
      last_synced_at: last_synced_at&.iso8601,
      trend: nil
    }
  end

  def as_detail_json
    as_summary_json.merge(
      stats: video_stats.order(date: :desc).limit(30).map { |s| VideoStatDecorator.new(s).as_json_entry }
    )
  end

  private

  def total_views_value
    respond_to?(:total_views) ? total_views.to_i : video_stats.sum(:views)
  end

  def total_likes_value
    respond_to?(:total_likes) ? total_likes.to_i : video_stats.sum(:likes)
  end

  def total_comments_value
    respond_to?(:total_comments) ? total_comments.to_i : video_stats.sum(:comments)
  end

  def total_watch_time_value
    raw = respond_to?(:total_watch_time) ? total_watch_time : video_stats.sum(:watch_time_minutes)
    raw.to_f
  end
end
