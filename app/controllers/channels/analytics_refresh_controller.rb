# Phase 13.3 — POST endpoint for the `[ refresh now ]` button on
# `/channels/:channel_id/analytics`.
#
# Enqueues `ChannelAnalyticsSync` for the channel + a
# `VideoAnalyticsSync` for each of the channel's videos. Redirects
# back to the analytics page with a notice. When the channel's
# YouTube connection needs re-authorization, the redirect carries an
# alert flash instead and no jobs are enqueued (master-agent copy
# decision 7).
class Channels::AnalyticsRefreshController < ApplicationController
  def create
    channel = Channel.friendly.find(params[:channel_id])
    connection = channel.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to channel_analytics_path(channel),
                  alert: "this connection needs re-authorization first."
      return
    end

    ChannelAnalyticsSync.perform_async(channel.id)
    channel.videos.find_each { |video| VideoAnalyticsSync.perform_async(video.id) }

    redirect_to channel_analytics_path(channel), notice: "syncing..."
  end
end
