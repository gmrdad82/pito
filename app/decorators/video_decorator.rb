class VideoDecorator < ApplicationDecorator
  def formatted_duration
    h.format_duration(duration_seconds)
  end

  def formatted_privacy
    privacy_status&.sub("_video", "") || "—"
  end

  def formatted_published_at
    published_at&.strftime("%Y-%m-%d %H:%M")
  end

  def as_summary_json
    {
      id: id,
      youtube_video_id: youtube_video_id,
      title: title,
      channel_id: channel_id,
      channel_title: channel.title,
      privacy_status: formatted_privacy,
      published_at: published_at&.iso8601,
      duration_seconds: duration_seconds,
      total_views: total_views_value,
      total_likes: total_likes_value,
      total_comments: total_comments_value,
      total_watch_time: total_watch_time_value
    }
  end

  def as_detail_json
    as_summary_json.merge(
      description: description,
      thumbnail_url: thumbnail_url,
      tags: tags,
      category_id: category_id,
      default_language: default_language,
      made_for_kids: made_for_kids,
      last_synced_at: last_synced_at&.iso8601,
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
    respond_to?(:total_watch_time) ? total_watch_time.to_i : video_stats.sum(:watch_time_minutes)
  end
end
