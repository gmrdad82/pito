# Phase 13.3 — Channel decorator for the analytics dashboard.
# Wraps a `Channel` with analytics-aware lookups so views stay
# query-free. Each method returns either an ActiveRecord row /
# relation, or a pre-aggregated hash; views never reach for
# `ChannelDaily` etc. directly.
#
# Lives under the `Analytics::` sub-namespace so it doesn't collide
# with the existing top-level `ChannelDecorator` (which carries the
# JSON wire-shape used by the pito CLI).
module Analytics
  class ChannelDecorator < Draper::Decorator
    delegate_all

    # Return the `ChannelWindowSummary` row for the chosen window, or
    # nil when no row exists. Views render the empty-state caption
    # whenever this is nil.
    def window_summary(window)
      ChannelWindowSummary.find_by(channel_id: id, window: window)
    end

    # Daily rows in the inclusive `(start_date, end_date)` range. The
    # caller computes the dates from `AnalyticsWindow#window_dates`.
    def daily_for_window(start_date, end_date)
      ChannelDaily
        .for_window(start_date, end_date)
        .where(channel_id: id)
        .ordered_by_date
    end

    # Top-videos leaderboard rows for the chosen window, ordered by
    # rank ascending (rank 1 = top performer). Joins the video
    # relation so views can render `row.video.title` without N+1
    # queries.
    def top_videos(window)
      TopVideosWindow
        .where(channel_id: id, window: window)
        .includes(:video)
        .order(:rank)
    end

    # Channel geography (Q15) — SUM-aggregated across this channel's
    # videos. Returns an array of `{ country_code:, views: }` hashes
    # ordered by views desc, capped to the top 25 to keep bar charts
    # legible.
    def geography_summed(start_date, end_date, limit: 25)
      VideoDailyByCountry
        .joins(:video)
        .where(videos: { channel_id: id })
        .where(date: start_date..end_date)
        .group(:country_code)
        .order(Arel.sql("SUM(video_daily_by_countries.views) DESC"))
        .limit(limit)
        .sum(:views)
    end

    # Channel demographics (Q15) — same SUM-aggregation. Returns a
    # hash keyed by `[age_group, gender]` to summed `viewer_percentage`
    # values; the `viewer_percentage` floats are summed across days
    # (an approximation, called out via the Q15 caveat caption).
    def demographics_summed(start_date, end_date)
      VideoDailyByAgeGroupGender
        .joins(:video)
        .where(videos: { channel_id: id })
        .where(date: start_date..end_date)
        .group(:age_group, :gender)
        .sum(:viewer_percentage)
    end
  end
end
