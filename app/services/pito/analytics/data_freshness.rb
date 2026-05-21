# Phase 13.3 — Data-freshness lookup. Returns the timestamp of the
# most recent successful analytics-v2 API call, optionally scoped to
# a single channel or video. The dashboards display this as
# `synced <human-relative-time> ago` per master-agent copy
# decision 8; nil means "never synced."
#
# Note: `YoutubeApiCall` rows track the connection, not the channel
# directly — scoping by channel/video means scoping by the
# underlying connection. When the channel has no connection, the
# helper returns nil.
module Pito
  module Analytics
    module DataFreshness
      OK_OUTCOMES = %w[success succeeded].freeze
      ANALYTICS_KIND = "analytics_v2".freeze

      module_function

      def last_synced_at(channel: nil, video: nil)
        scope = base_scope
        if channel
          connection_id = channel.youtube_connection_id
          return nil if connection_id.nil?
          scope = scope.where(youtube_connection_id: connection_id)
        elsif video
          connection_id = video.channel&.youtube_connection_id
          return nil if connection_id.nil?
          scope = scope.where(youtube_connection_id: connection_id)
        end
        scope.maximum(:created_at)
      end

      def base_scope
        YoutubeApiCall
          .where(client_kind: ANALYTICS_KIND)
          .where(outcome: OK_OUTCOMES)
      end
    end
  end
end
