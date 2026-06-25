# frozen_string_literal: true

module Pito
  module Analytics
    # Folds per-video scalar PRIMITIVES into a scope-level result — additive sums
    # for counts, views-weighted averages for ratios — with the prior comparable
    # window so the view layer can render trends.
    #
    # This mirrors Pito::Analytics::Scalars' aggregation math, but consumes the
    # already-fetched primitives map (no YouTube calls): the analyze fan-out fetches
    # per-video primitives (warm-or-cold) then folds them here.
    #
    #   Aggregate.scalars(current: {id => raw, …}, previous: {id => raw, …} | nil)
    #   # => { views: { current: 1234, previous: 1000 }, … }   (keys = Scalars::KEYS)
    #
    # `current` / `previous` are Hash{ youtube_video_id => raw scalar metrics } with
    # STRING keys (as stored by Pito::Analytics::Primitives). `previous` is nil for
    # a non-comparable window (e.g. lifetime).
    module Aggregate
      # Canonical render-order metric keys — shared with the scalars glance.
      KEYS = Pito::Analytics::Scalars::KEYS

      module_function

      def scalars(current:, previous: nil)
        cur = fold(current.values)
        prv = previous && fold(previous.values)
        KEYS.index_with { |k| { current: cur[k], previous: prv && prv[k] } }
      end

      # Sum additive metrics; views-weight the ratio metrics.
      def fold(rows)
        sums         = Hash.new(0)
        weighted_dur = 0.0
        weighted_pct = 0.0
        views_total  = 0

        rows.each do |row|
          next if row.blank?

          v = row["views"].to_i
          views_total                      += v
          sums[:views]                     += v
          sums[:estimated_minutes_watched] += row["estimated_minutes_watched"].to_i
          sums[:subscribers_gained]        += row["subscribers_gained"].to_i
          sums[:subscribers_lost]          += row["subscribers_lost"].to_i
          sums[:likes]                     += row["likes"].to_i
          sums[:dislikes]                  += row["dislikes"].to_i
          sums[:comments]                  += row["comments"].to_i
          weighted_dur                     += row["average_view_duration"].to_f * v
          weighted_pct                     += row["average_view_percentage"].to_f * v
        end

        {
          views:             sums[:views],
          watched_hours:     (sums[:estimated_minutes_watched] / 60.0).round(1),
          avg_view_duration: views_total.positive? ? (weighted_dur / views_total).round : 0,
          avg_viewed_pct:    views_total.positive? ? (weighted_pct / views_total).round(1) : 0.0,
          subs_gained:       sums[:subscribers_gained],
          subs_lost:         sums[:subscribers_lost],
          likes:             sums[:likes],
          dislikes:          sums[:dislikes],
          comments:          sums[:comments]
        }
      end
    end
  end
end
