# Phase 13.3 — Per-video analytics dashboard at
# `/videos/:video_id/analytics`.
#
# Renders the video's window summary cards, daily line (V1),
# retention curve (V7), and the six per-video breakdowns (country,
# device, OS, traffic source, subscribed status, demographics).
class Videos::AnalyticsController < ApplicationController
  include AnalyticsWindow

  def show
    @video = Video.friendly.find(params[:video_id])
    @decorator = Analytics::VideoDecorator.new(@video)
    @window = current_window
    @window_start, @window_end = window_dates(@window)
    @last_synced_at = Analytics::DataFreshness.last_synced_at(video: @video)
    @needs_reauth = @video.channel&.youtube_connection&.needs_reauth?
  end
end
