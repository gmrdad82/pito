# Phase 13.2 — Analytics sync engine. Active-video classifier per
# Note 3's rule: a video is "active" if it was published in the last
# 90 days OR has > 100 views in the last 7 days.
#
# Pure function. No cache (master-agent decision: pure function
# recomputed each pass; no schema column).
#
# Boundary semantics (master-agent decision 6):
#
# - "Last 90 days" is INCLUSIVE: `published_at >= 90.days.ago` returns
#   true for a video published exactly 90 days ago.
# - "More than 100 views" is STRICT: `> 100`, not `>= 100`.
module Youtube
  module ActiveVideoClassifier
    DAYS_WINDOW = 90
    VIEWS_WINDOW_DAYS = 7
    VIEWS_THRESHOLD = 100

    module_function

    def active?(video)
      return false if video.nil?

      published = video.published_at
      return true if published.present? && published >= DAYS_WINDOW.days.ago

      recent_views_for(video) > VIEWS_THRESHOLD
    end

    # Relation of active videos under the connection's channels. Used by
    # `Backfill::AnalyticsRange` and the orchestrator. Implemented as a
    # subselect-by-id pass over the candidate set so the active rule is
    # evaluated once per row.
    def active_for(connection)
      candidate = Video
        .joins(:channel)
        .where(channels: { youtube_connection_id: connection.id })

      ids = candidate.find_each.select { |v| active?(v) }.map(&:id)
      Video.where(id: ids)
    end

    def recent_views_for(video)
      VideoDaily
        .where(video_id: video.id)
        .where(date: VIEWS_WINDOW_DAYS.days.ago.to_date..Date.current)
        .sum(:views)
        .to_i
    end
  end
end
