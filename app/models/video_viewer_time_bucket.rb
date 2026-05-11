# Phase 26 — 01g. Viewer-time analytics implementation.
#
# Raw day-of-week × hour-of-day rollup row, stored in **UTC**. One row
# per `(video_id, day_of_week_utc, hour_of_day_utc)` triple. The
# user-tz rollup lives in `Analytics::ViewerTimeRollup` and converts
# at query time using `Current.user.time_zone` (the storage / render
# contract pinned by 01f).
#
# `day_of_week_utc` follows Postgres' `extract(dow ...)` convention
# (Sunday = 0, Saturday = 6) so the rollup SQL composes cleanly.
# `hour_of_day_utc` is `0..23`. Both are enforced via DB CHECK
# constraints AND model-level validations.
class VideoViewerTimeBucket < ApplicationRecord
  belongs_to :video

  HOUR_RANGE = (0..23).freeze
  DAY_OF_WEEK_RANGE = (0..6).freeze

  validates :hour_of_day_utc,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 23
            }
  validates :day_of_week_utc,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 6
            }
  validates :view_count,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :watch_time_seconds,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :video_id,
            uniqueness: { scope: %i[day_of_week_utc hour_of_day_utc] }

  scope :for_channel, ->(channel_id) {
    joins(:video).where(videos: { channel_id: channel_id })
  }

  # Convert UTC-stored buckets to the caller's timezone at query time.
  # Returns an Array of `[dow_local, hod_local, view_count, watch_time_seconds]`
  # 4-tuples summed within each local (dow, hod) cell. `tz` may be an
  # IANA name (`"Europe/Bucharest"`), a Rails-friendly alias
  # (`"Eastern Time (US & Canada)"`), or an `ActiveSupport::TimeZone`
  # instance — anything `ActiveSupport::TimeZone[]` resolves.
  #
  # The conversion anchors each `(dow_utc, hod_utc)` pair to a
  # synthetic Sunday-at-midnight reference week, shifts to the target
  # zone, and re-extracts the local (dow, hod). Postgres handles the
  # offset arithmetic and DST flips natively.
  #
  # Single SQL query — no N+1, no Ruby-side joins. Suitable for both
  # per-video and per-channel scopes (pre-filter via `where` /
  # `for_channel` before chaining).
  scope :rolled_up_to_tz, ->(tz) {
    iana = resolve_iana(tz)
    # Reference Sunday at 00:00 UTC anchors the synthetic week the
    # rollup re-projects through the target zone. Any past Sunday
    # works — DST behavior depends on the date for ambiguous zones,
    # so we pin a fixed reference (2024-01-07 was a Sunday). The
    # heatmap is timezone-shape only, not an instant-anchored view,
    # so picking a single reference is correct.
    sql = <<~SQL.squish
      SELECT
        EXTRACT(
          DOW FROM
          ((TIMESTAMP '2024-01-07 00:00:00 UTC' +
            (day_of_week_utc * INTERVAL '1 day') +
            (hour_of_day_utc * INTERVAL '1 hour'))
            AT TIME ZONE 'UTC' AT TIME ZONE :tz)
        )::int AS dow_local,
        EXTRACT(
          HOUR FROM
          ((TIMESTAMP '2024-01-07 00:00:00 UTC' +
            (day_of_week_utc * INTERVAL '1 day') +
            (hour_of_day_utc * INTERVAL '1 hour'))
            AT TIME ZONE 'UTC' AT TIME ZONE :tz)
        )::int AS hod_local,
        SUM(view_count)::bigint AS view_count,
        SUM(watch_time_seconds)::bigint AS watch_time_seconds
      FROM (#{all.to_sql}) AS scoped
      GROUP BY 1, 2
    SQL
    connection.exec_query(
      sanitize_sql_for_conditions([ sql, { tz: iana } ])
    )
  }

  # Public for callers + the rolled_up scope. Accepts ActiveSupport::TimeZone,
  # IANA names, or Rails-friendly aliases; always returns an IANA tz name.
  def self.resolve_iana(tz)
    case tz
    when ActiveSupport::TimeZone
      tz.tzinfo.name
    when String, Symbol
      lookup = ActiveSupport::TimeZone[tz.to_s]
      lookup ? lookup.tzinfo.name : tz.to_s
    else
      "Etc/UTC"
    end
  end
end
