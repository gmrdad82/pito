# Phase 13.3 — POST endpoint for the `[ refresh retention ]` button
# on `/videos/:video_id/analytics`.
#
# Retention is recomputed-in-place (per spec 01) so it deserves a
# dedicated refresh endpoint distinct from the V1-V8 sync trigger.
#
# Phase 13 security fix-forward (F3) — per-video retention cache lock
# is scoped distinctly from the V1-V8 analytics-refresh lock so the
# two refresh buttons do not block each other.
class Videos::RetentionRefreshController < ApplicationController
  LOCK_TTL = 60.seconds

  def create
    video = Video.friendly.find(params[:video_id])
    connection = video.channel&.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to video_analytics_path(video),
                  alert: "this connection needs re-authorization first."
      return
    end

    lock_key = "retention_refresh:video:#{video.id}"
    unless Rails.cache.write(lock_key, 1, expires_in: LOCK_TTL, unless_exist: true)
      redirect_to video_analytics_path(video),
                  alert: "refresh already in progress, please wait."
      return
    end

    VideoRetentionSync.perform_async(video.id)
    redirect_to video_analytics_path(video), notice: "syncing..."
  end
end
