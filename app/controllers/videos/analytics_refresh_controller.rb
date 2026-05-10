# Phase 13.3 — POST endpoint for the `[ refresh now ]` button on
# `/videos/:video_id/analytics`.
#
# Enqueues `VideoAnalyticsSync` for the video. The smuggle defense
# is implicit in `Video.find(params[:video_id])` — only the route's
# `:video_id` is honored; any body parameter named `video_id` is
# ignored.
class Videos::AnalyticsRefreshController < ApplicationController
  def create
    video = Video.friendly.find(params[:video_id])
    connection = video.channel&.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to video_analytics_path(video),
                  alert: "this connection needs re-authorization first."
      return
    end

    VideoAnalyticsSync.perform_async(video.id)
    redirect_to video_analytics_path(video), notice: "syncing..."
  end
end
