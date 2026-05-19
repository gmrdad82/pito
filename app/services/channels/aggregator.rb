# Phase 37 Wave A2 — `Channels::Aggregator`.
#
# Pure module-function service. Sums each metric across the provided
# list of channel hashes (shape per `Channels::MockData.channels`,
# Wave B swap to `Channels::Stats.*` is a constant change).
#
# Wave A2 covers subscribers / views / videos / hours. Wave C/D/E
# methods (geography aggregation, demographics, trends) TBD.
module Channels
  module Aggregator
    module_function

    def subscribers_total(channels)
      channels.sum { |c| c[:subscriber_count].to_i }
    end

    def views_total(channels)
      channels.sum { |c| c[:view_count].to_i }
    end

    def videos_total(channels)
      channels.sum { |c| c[:video_count].to_i }
    end

    def watch_hours_total(channels)
      channels.sum { |c| c[:watch_hours].to_i }
    end
  end
end
