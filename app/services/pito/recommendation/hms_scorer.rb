module Pito
  module Recommendation
    # Heat Map Score — fixed-color hard-stop buckets used in recommendation
    # heat bars (game↔channel, channel↔bundle, etc.).
    # Buckets: bad / weak / ok / good / great (hard stops, not gradients).
    class HmsScorer
      # @param score [Float] raw similarity / weighted score, normalized 0..1
      # @return [Symbol] one of :bad / :weak / :ok / :good / :great
      BAD_MAX = 0.2
      WEAK_MAX = 0.4
      OK_MAX = 0.6
      GOOD_MAX = 0.8

      def self.bucket(score:)
        return :bad if score < BAD_MAX
        return :weak if score < WEAK_MAX
        return :ok if score < OK_MAX
        return :good if score < GOOD_MAX
        :great
      end
    end
  end
end
