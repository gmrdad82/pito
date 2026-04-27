class VideosController < ApplicationController
  def index
    @videos = Video.includes(:channel)
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS SIGNED), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(published_at: :desc)
    @max_panes = (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end
end
