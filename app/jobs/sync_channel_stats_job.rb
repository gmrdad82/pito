# frozen_string_literal: true

# P60 — Daily sync of general channel stats (subscribers, views, watch hours).
#
# Iterates every Channel that has a connected, non-reauth YoutubeConnection
# and calls Channel::Youtube::StatsFetcher to pull fresh stats from the
# YouTube Data API v3 (subscribers + views) and Analytics API (watch hours).
#
# Error posture: errors for one channel are rescued and logged so a single
# failing channel never aborts the rest of the batch.
#
# Scheduled daily at 01:00 UTC via config/recurring.yml.
class SyncChannelStatsJob < ApplicationJob
  queue_as :default

  def perform
    channels = Channel
      .joins(:youtube_connection)
      .where(youtube_connections: { needs_reauth: false })

    channels.each do |channel|
      sync_one(channel)
    end
  end

  private

  def sync_one(channel)
    stats = Channel::Youtube::StatsFetcher.call(channel)
    channel.update_columns(
      subscriber_count: stats[:subscriber_count],
      view_count:       stats[:view_count],
      watched_hours:    stats[:watched_hours],
      last_synced_at:   stats[:last_synced_at]
    )
  rescue StandardError => e
    Rails.logger.error(
      "SyncChannelStatsJob: failed for channel=#{channel.id} " \
      "(#{channel.youtube_channel_id}): #{e.class}: #{e.message}"
    )
  end
end
