module Pito
  module ExternalApiTracker
    # YouTube Data API quota tracker.
    # Backed by app/models/youtube_api_call.rb + Channel::Youtube::Quota.
    # Column is `units` (not cost_units) per the YoutubeApiCall schema.
    class Youtube
      DAILY_QUOTA = 10_000  # default per the YouTube Data API v3

      def self.usage
        ::YoutubeApiCall.where("created_at >= ?", Time.current.beginning_of_day).sum(:units)
      end

      def self.quota = DAILY_QUOTA
      def self.window = :daily
      def self.percent = quota ? (usage.to_f / quota).clamp(0.0, 1.0) : 0.0
      def self.status
        p = percent
        return :critical if p >= 0.9
        return :warn if p >= 0.7
        :ok
      end
    end
  end
end
