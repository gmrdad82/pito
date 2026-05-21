module Pito
  module Schedule
    # Cross-channel publish-schedule conflict detection.
    #
    # The owner runs N channels and wants to avoid publishing videos
    # too close together across them (so channels don't compete with
    # each other on a given day).
    #
    # `Pito::Schedule::Conflict.check(channel:, publish_at:, window_hours: 24)`
    #
    # @param channel [Channel] the channel proposing the publish
    # @param publish_at [Time] proposed publish timestamp
    # @param window_hours [Integer] +/- window in hours (default 24)
    # @return [Array<Hash>] conflicts: [{ channel:, video:, scheduled_at:, distance_hours: }, ...]
    #   Empty array if no conflicts.
    class Conflict
      DEFAULT_WINDOW_HOURS = 24

      def self.check(channel:, publish_at:, window_hours: DEFAULT_WINDOW_HOURS)
        # Skeleton: query Video where channel_id != channel.id AND
        # scheduled_publish_at BETWEEN (publish_at - window) AND (publish_at + window).
        # Returns conflicts; empty if none.
        #
        # Real implementation pending — depends on Video model's scheduled
        # publish timestamp column (currently varies between :publish_at,
        # :scheduled_publish_at, etc. — needs grounding when /videos edit
        # flow lands).
        raise NotImplementedError,
              "Pito::Schedule::Conflict pending /videos schedule column grounding"
      end
    end
  end
end
