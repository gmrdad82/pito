# Phase 13.3 — POST endpoint for the `[ refresh retention ]` button
# on `/videos/:video_id/analytics`.
#
# Retention is recomputed-in-place (per spec 01) so it deserves a
# dedicated refresh endpoint distinct from the V1-V8 sync trigger.
class Videos::RetentionRefreshController < ApplicationController
  def create
    video = Video.friendly.find(params[:video_id])
    connection = video.channel&.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to video_analytics_path(video),
                  alert: "this connection needs re-authorization first."
      return
    end

    VideoRetentionSync.perform_async(video.id)
    redirect_to video_analytics_path(video), notice: "syncing..."
  end
end
