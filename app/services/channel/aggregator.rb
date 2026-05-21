# Phase 37 Wave A2 — `Channel::Aggregator`.
#
# Pure module-function service. Sums each metric across the provided
# list of channel hashes (shape per `Channel::MockData.channels`,
# Wave B swap to `Channels::Stats.*` is a constant change).
#
# Wave A2 covers subscribers / views / videos / hours. Wave C/D/E
# methods (geography aggregation, demographics, trends) TBD.
class Channel
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

    # Per-window aggregate across the selected channels. Returns a
    # `{ subs_delta:, views_delta:, watch_hours_delta: }` hash.
    #
    # For the `"alltime"` window the per-channel mock entries store
    # `nil` deltas — this method falls back to the absolute totals
    # (`subscriber_count` / `view_count` / `watch_hours`) for that
    # window so the rendered cells stay numeric. For every other window
    # the method sums the three delta fields directly.
    #
    # `window` arrives as a string from the chip URL value. Defensive
    # `.to_s` coercion guards against symbol inputs in callers.
    def window_summary(channels, window)
      key = window.to_s

      if key == "alltime"
        return {
          subs_delta: subscribers_total(channels),
          views_delta: views_total(channels),
          watch_hours_delta: watch_hours_total(channels)
        }
      end

      subs = 0
      views = 0
      hours = 0
      channels.each do |c|
        per_window = c.dig(:window_summaries, key) || {}
        subs  += per_window[:subs_delta].to_i
        views += per_window[:views_delta].to_i
        hours += per_window[:watch_hours_delta].to_i
      end
      { subs_delta: subs, views_delta: views, watch_hours_delta: hours }
    end
  end
end
