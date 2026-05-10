# Phase 13.3 — POST endpoint for the `[ refresh now ]` button on
# `/videos/:video_id/analytics`.
#
# Enqueues `VideoAnalyticsSync` for the video. The smuggle defense
# is implicit in `Video.find(params[:video_id])` — only the route's
# `:video_id` is honored; any body parameter named `video_id` is
# ignored.
#
# Phase 13 security fix-forward (F3) — per-video cache lock prevents
# rapid-fire duplicate enqueues from a click-bomb. See
# `Channels::AnalyticsRefreshController` for the rationale.
class Videos::AnalyticsRefreshController < ApplicationController
  LOCK_TTL = 60.seconds

  def create
    video = Video.friendly.find(params[:video_id])
    connection = video.channel&.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to video_analytics_path(video),
                  alert: "this connection needs re-authorization first."
      return
    end

    lock_key = "analytics_refresh:video:#{video.id}"
    unless Rails.cache.write(lock_key, 1, expires_in: LOCK_TTL, unless_exist: true)
      redirect_to video_analytics_path(video),
                  alert: "refresh already in progress, please wait."
      return
    end

    VideoAnalyticsSync.perform_async(video.id)
    redirect_to video_analytics_path(video), notice: "syncing..."
  end
end
