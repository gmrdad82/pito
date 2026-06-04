# frozen_string_literal: true

# P60 — Fetch general channel stats for one Channel via the YouTube API.
#
# Uses:
#   - YouTube Data API v3  `channels.list?part=statistics` for
#     `subscriberCount` and `viewCount`. (Cost: 1 quota unit)
#   - YouTube Analytics API v2  `reports.query?metrics=estimatedMinutesWatched`
#     for all-time watch hours. (Scope: youtube.readonly or yt-analytics.readonly)
#
# Watch-hours note:
#   The Analytics API requires the `yt-analytics.readonly` or
#   `yt-analytics-monetary.readonly` OAuth scope. If the connection does
#   not have those scopes, or if the Analytics query raises any error,
#   `watched_hours` is returned as nil (not 0) so the job can persist nil
#   and the caller can distinguish "not available" from "zero".
#
# Returns a Hash with:
#   :subscriber_count  (Integer | nil)
#   :view_count        (Integer | nil)
#   :watched_hours     (Integer | nil)  — nil if Analytics unavailable
#   :last_synced_at    (Time)
class Channel
  module Youtube
    class StatsFetcher
      # Fetch stats for a single connected channel.
      #
      # @param channel [Channel] a channel with a non-nil youtube_connection
      # @return [Hash] see class-level docs
      def self.call(channel)
        new(channel).call
      end

      def initialize(channel)
        @channel = channel
        @client  = Channel::Youtube::Client.new(channel.youtube_connection)
      end

      def call
        stats = fetch_data_stats
        hours = fetch_watched_hours

        {
          subscriber_count: stats[:subscriber_count],
          view_count:       stats[:view_count],
          watched_hours:    hours,
          last_synced_at:   Time.current
        }
      end

      private

      def fetch_data_stats
        response = @client.channels_list(
          ids:   [ @channel.youtube_channel_id ],
          parts: %i[statistics]
        )
        item  = response[:items]&.first || {}
        stats = item[:statistics] || {}

        {
          subscriber_count: stats[:subscriber_count]&.to_i,
          view_count:       stats[:view_count]&.to_i
        }
      end

      # Fetch all-time estimated watch hours via the Analytics API.
      #
      # TODO: If the stored OAuth token does not include the
      # `yt-analytics.readonly` scope, the API returns a 403. In that
      # case (or on any other error) we rescue and return nil so the job
      # can persist nil without aborting.
      def fetch_watched_hours
        analytics = @client.analytics_query(
          ids:        "channel==#{@channel.youtube_channel_id}",
          metrics:    "estimatedMinutesWatched",
          start_date: "2000-01-01",
          end_date:   Date.today.to_s
        )
        minutes = analytics[:rows]&.first&.first&.to_i || 0
        (minutes / 60.0).round
      rescue StandardError
        # Analytics API unavailable or scope missing — return nil so the
        # job knows watch-hours are not available, rather than storing 0.
        nil
      end
    end
  end
end
