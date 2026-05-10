# Phase 13.3 — Per-channel analytics dashboard at
# `/channels/:channel_id/analytics`.
#
# Renders the channel's window summary cards, the daily line chart
# (C1), the top-videos leaderboard (C3), and the channel-level
# geography / demographics rollups (computed at query time per
# spec 02 master-agent decision — no dedicated C4/C5 tables).
class Channels::AnalyticsController < ApplicationController
  include AnalyticsWindow

  def show
    @channel = Channel.friendly.find(params[:channel_id])
    @decorator = Analytics::ChannelDecorator.new(@channel)
    @window = current_window
    @window_start, @window_end = window_dates(@window)
    @last_synced_at = Analytics::DataFreshness.last_synced_at(channel: @channel)
    @needs_reauth = @channel.youtube_connection&.needs_reauth?
  end
end
