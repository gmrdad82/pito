# Phase 26 — 01g. Viewer-time analytics implementation.
#
# Pure-Ruby wrapper around the rollup query. Pulls UTC-stored
# `video_viewer_time_buckets` rows for a video (or every video on a
# channel), shifts to the caller's timezone in a single SQL query
# (via `VideoViewerTimeBucket.rolled_up_to_tz`), and returns a hash of
# `{ [dow_local, hod_local] => { views:, watch_time_seconds: } }`.
#
# The hash shape feeds `ViewerTimeHeatmapComponent` directly. Empty
# cells (missing keys) render as the zero-intensity baseline.
#
# Per 01f §"Query patterns", the SQL stays a single statement so
# there is no N+1 from caller code.
module Analytics
  class ViewerTimeRollup
    Result = Struct.new(:views, :watch_time_seconds, keyword_init: true)

    # @param scope [Symbol] either `:video` or `:channel`.
    # @param id   [Integer] the id of the video or channel.
    # @param tz   [String, ActiveSupport::TimeZone] the target zone.
    # @return [Hash{[Integer, Integer] => Analytics::ViewerTimeRollup::Result}]
    def call(scope:, id:, tz: "Etc/UTC")
      relation = base_relation(scope: scope, id: id)
      return {} if relation.nil?

      rows = relation.rolled_up_to_tz(tz)

      rows.each_with_object({}) do |row, acc|
        key = [ row["dow_local"].to_i, row["hod_local"].to_i ]
        acc[key] = Result.new(
          views: row["view_count"].to_i,
          watch_time_seconds: row["watch_time_seconds"].to_i
        )
      end
    end

    private

    def base_relation(scope:, id:)
      case scope.to_sym
      when :video
        VideoViewerTimeBucket.where(video_id: id)
      when :channel
        VideoViewerTimeBucket.for_channel(id)
      else
        raise ArgumentError, "scope must be :video or :channel (got #{scope.inspect})"
      end
    end
  end
end
