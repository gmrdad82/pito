# Phase 13.3 — Top-level analytics dashboard at `/analytics`.
#
# Renders the cross-channel summary cards (only when ≥ 2 connected
# channels per master-agent decision 7), the per-channel cards
# (one per `Channel.connected`), and the four cross-video local
# rollups computed by `Analytics::CrossVideoLocals`.
class AnalyticsController < ApplicationController
  include AnalyticsWindow

  def show
    @window = current_window
    @window_start, @window_end = window_dates(@window)
    @connected_channels = Channel.connected.order(:id)
    @show_cross_channel_summary = @connected_channels.size >= 2
    @cross_channel_summary = build_cross_channel_summary if @show_cross_channel_summary
    @channel_decorators = @connected_channels.map { |c| Analytics::ChannelDecorator.new(c) }
    @last_synced_at = Analytics::DataFreshness.last_synced_at
    @cross_video_locals = Analytics::CrossVideoLocals.new
  end

  private

  # Sum the four headline metrics across every connected channel's
  # window summary for the chosen window. Returns a hash keyed by
  # metric name. Channels with no row for the chosen window simply
  # contribute zero (no nil propagation).
  def build_cross_channel_summary
    summaries = ChannelWindowSummary
      .where(channel_id: @connected_channels.map(&:id), window: @window)

    {
      views: summaries.sum(:views),
      estimated_minutes_watched: summaries.sum(:estimated_minutes_watched),
      net_subscribers: summaries.sum(:subscribers_gained) - summaries.sum(:subscribers_lost),
      likes: summaries.sum(:likes)
    }
  end
end
