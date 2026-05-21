module Pito
  module ExternalApiTracker
    # IGDB API quota tracker.
    # IGDB enforces per-second rate limit (4 req/s) via Twitch token.
    # No daily quota; track rolling 60s call count for awareness.
    class Igdb
      ROLLING_WINDOW = 60  # seconds
      RATE_LIMIT_PER_SECOND = 4

      def self.usage
        # Skeleton: read from Rails.cache or in-memory counter maintained
        # by Game::Igdb::RateLimiter. For now, return 0.
        0
      end

      def self.quota = RATE_LIMIT_PER_SECOND * ROLLING_WINDOW
      def self.window = :rolling_60s
      def self.percent = (usage.to_f / quota).clamp(0.0, 1.0)
      def self.status
        p = percent
        return :critical if p >= 0.9
        return :warn if p >= 0.7
        :ok
      end
    end
  end
end
