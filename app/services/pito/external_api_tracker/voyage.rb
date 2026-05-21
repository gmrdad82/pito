module Pito
  module ExternalApiTracker
    # Voyage AI embedding API quota tracker.
    # Tracks monthly token usage against the Voyage tier's monthly cap.
    class Voyage
      # Monthly token cap depends on the user's Voyage plan.
      # Skeleton: read from Rails.application.credentials.voyage[:monthly_token_cap] if set.
      def self.usage = 0  # TODO: wire to Voyage::Stats or a dedicated counter
      def self.quota = Rails.application.credentials.dig(:voyage, :monthly_token_cap)
      def self.window = :monthly
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
