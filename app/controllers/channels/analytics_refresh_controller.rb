# Phase 13.3 — POST endpoint for the `[ refresh now ]` button on
# `/channels/:channel_id/analytics`.
#
# Enqueues `ChannelAnalyticsSync` for the channel + a
# `VideoAnalyticsSync` for each of the channel's videos. Redirects
# back to the analytics page with a notice. When the channel's
# YouTube connection needs re-authorization, the redirect carries an
# alert flash instead and no jobs are enqueued (master-agent copy
# decision 7).
#
# Phase 13 security fix-forward (F3) — protects against a rapid-fire
# click-bomb that would otherwise enqueue dozens of duplicate jobs
# (and burn Analytics v2 quota) by holding a per-channel cache lock
# for 60 seconds. The lock key is scoped to the channel id; the same
# user hitting refresh on a *different* channel is not blocked. Once
# the lock expires (or the job finishes faster than that), the next
# refresh proceeds normally. The check is intentionally lighter than
# Rack::Attack — the goal is to drop accidental duplicates, not to
# defend against a determined attacker.
class Channels::AnalyticsRefreshController < ApplicationController
  LOCK_TTL = 60.seconds

  def create
    channel = Channel.friendly.find(params[:channel_id])
    connection = channel.youtube_connection

    if connection.nil? || connection.needs_reauth?
      redirect_to channel_analytics_path(channel),
                  alert: "this connection needs re-authorization first."
      return
    end

    lock_key = "analytics_refresh:channel:#{channel.id}"
    unless Rails.cache.write(lock_key, 1, expires_in: LOCK_TTL, unless_exist: true)
      redirect_to channel_analytics_path(channel),
                  alert: "refresh already in progress, please wait."
      return
    end

    ChannelAnalyticsSync.perform_later(channel.id)
    channel.videos.find_each { |video| VideoAnalyticsSync.perform_later(video.id) }

    redirect_to channel_analytics_path(channel), notice: "syncing..."
  end
end
