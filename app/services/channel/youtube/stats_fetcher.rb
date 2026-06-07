# frozen_string_literal: true

# P60 — Fetch general channel stats for one Channel via the YouTube API.
#
# Uses:
#   - YouTube Data API v3  `channels.list?part=statistics` for
#     `subscriberCount` and `viewCount`. (Cost: 1 quota unit)
#
# P4 — `watched_hours` (Analytics-sourced) was dropped; it returns in a
# future `Pito::Analytics`. This fetcher now returns subscribers + views
# only.
#
# Returns a Hash with:
#   :subscriber_count  (Integer | nil)
#   :view_count        (Integer | nil)
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

        {
          subscriber_count: stats[:subscriber_count],
          view_count:       stats[:view_count],
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
    end
  end
end
