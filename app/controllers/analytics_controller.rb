# Phase 13.3 — Top-level analytics dashboard at `/analytics`.
#
# Renders the cross-channel summary cards (only when ≥ 2 channels per
# master-agent decision 7), one card per channel, and the four
# cross-video local rollups computed by `Analytics::CrossVideoLocals`.
class AnalyticsController < ApplicationController
  include AnalyticsWindow

  def show
    @window = current_window
    @window_start, @window_end = window_dates(@window)
    @channels = Channel.order(:id)
    @show_cross_channel_summary = @channels.size >= 2
    @cross_channel_summary = build_cross_channel_summary if @show_cross_channel_summary
    @channel_decorators = @channels.map { |c| Analytics::ChannelDecorator.new(c) }
    @last_synced_at = Analytics::DataFreshness.last_synced_at
    @cross_video_locals = Analytics::CrossVideoLocals.new
  end

  private

  # Sum the four headline metrics across every channel's window summary
  # for the chosen window. Returns a hash keyed by metric name. Channels
  # with no row for the chosen window simply contribute zero (no nil
  # propagation).
  def build_cross_channel_summary
    summaries = ChannelWindowSummary
      .where(channel_id: @channels.map(&:id), window: @window)

    {
      views: summaries.sum(:views),
      estimated_minutes_watched: summaries.sum(:estimated_minutes_watched),
      net_subscribers: summaries.sum(:subscribers_gained) - summaries.sum(:subscribers_lost),
      likes: summaries.sum(:likes)
    }
  end
end
