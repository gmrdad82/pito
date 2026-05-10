class VideoDecorator < ApplicationDecorator
  # Phase 12 — video schema expansion. Decorator surfaces the new
  # writable subset + pre-publish checklist state. Boundary booleans
  # serialize as `"yes"` / `"no"` strings (CLAUDE.md hard rule).
  #
  # `as_summary_json` keeps the row-level shape used by the index page
  # JSON and the CLI; `as_detail_json` adds the full edit-form-shape
  # plus the pre-publish state.
  def as_summary_json
    {
      id: id,
      youtube_video_id: youtube_video_id,
      channel_id: channel_id,
      channel_url: channel&.channel_url,
      title: title,
      privacy_status: privacy_status,
      published_at: published_at&.iso8601,
      star: YesNo.to_yes_no(star),
      views: total_views_value,
      likes: total_likes_value,
      comments: total_comments_value,
      watch_time_minutes: total_watch_time_value,
      last_synced_at: last_synced_at&.iso8601,
      imported: YesNo.to_yes_no(imported?),
      trend: nil
    }
  end

  def as_detail_json
    as_summary_json.merge(
      description: description,
      tags: tags || [],
      category_id: category_id,
      thumbnail_url: thumbnail_url,
      publish_at: publish_at&.iso8601,
      duration_seconds: duration_seconds,
      project_id: project_id,
      self_declared_made_for_kids: YesNo.to_yes_no(self_declared_made_for_kids),
      made_for_kids_effective: YesNo.to_yes_no(made_for_kids_effective),
      contains_synthetic_media: YesNo.to_yes_no(contains_synthetic_media),
      etag: etag,
      last_sync_error: last_sync_error,
      pre_publish_checked_at: pre_publish_checked_at&.iso8601,
      pre_publish_game_ok: YesNo.to_yes_no(pre_publish_game_ok),
      pre_publish_age_ok: YesNo.to_yes_no(pre_publish_age_ok),
      pre_publish_paid_promotion_ok: YesNo.to_yes_no(pre_publish_paid_promotion_ok),
      pre_publish_end_screen_ok: YesNo.to_yes_no(pre_publish_end_screen_ok),
      studio_url: studio_url,
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
