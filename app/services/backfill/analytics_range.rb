# Phase 13.2 — Analytics sync engine. Out-of-band backfill helper for
# catching gaps in analytics data after a connection re-authorizes or
# when filling in initial history.
#
# Per the master-agent decision (open question 3): no app-side
# throttle. Sidekiq retries handle rate-limit responses; the YouTube
# Analytics API quota is separate from Data API v3.
#
# Usage (rake task wrapper at `analytics:backfill`):
#
#   Backfill::AnalyticsRange.call(
#     connection: YoutubeConnection.first,
#     from: 30.days.ago.to_date,
#     to:   1.day.ago.to_date
#   )
#
# Returns the count of jobs enqueued.
module Backfill
  module AnalyticsRange
    module_function

    def call(connection:, from:, to:, channels: nil, videos: nil)
      raise ArgumentError, "connection is required" if connection.nil?
      raise ArgumentError, "from must be <= to" if from.to_date > to.to_date
      raise ArgumentError, "connection #{connection.id} is not active (needs_reauth)" if connection.needs_reauth?

      channel_scope = scoped_channels(connection, channels)
      video_scope   = scoped_videos(connection, videos)

      enqueued = 0
      channel_scope.find_each do |channel|
        ChannelAnalyticsSync.perform_later(channel.id)
        enqueued += 1
      end

      video_scope.find_each do |video|
        next unless Channel::Youtube::ActiveVideoClassifier.active?(video)

        VideoAnalyticsSync.perform_later(video.id)
        enqueued += 1
      end

      enqueued
    end

    def scoped_channels(connection, channels)
      base = Channel.where(youtube_connection_id: connection.id)
      return base if channels.blank?

      ids = Array(channels).map { |c| c.is_a?(Channel) ? c.id : c.to_i }
      base.where(id: ids)
    end

    def scoped_videos(connection, videos)
      base = Video.joins(:channel).where(channels: { youtube_connection_id: connection.id })
      return base if videos.blank?

      ids = Array(videos).map { |v| v.is_a?(Video) ? v.id : v.to_i }
      base.where(id: ids)
    end
  end
end
