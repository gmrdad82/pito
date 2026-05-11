# Phase 26 — 01g. Viewer-time analytics implementation.
#
# `video_viewer_time_buckets` stores the raw day-of-week × hour-of-day
# rollup pulled from the YouTube Analytics API. Buckets are stored in
# **UTC** (the storage contract from 01f); the user-tz rollup happens
# at query time via `Analytics::ViewerTimeRollup`. One row per
# `(video_id, day_of_week_utc, hour_of_day_utc)` triple — `view_count`
# and `watch_time_seconds` are summed in place on every sync via
# `upsert_all`.
#
# `day_of_week_utc` follows Postgres' `extract(dow ...)` convention
# (Sunday = 0, Saturday = 6) so the same SQL the rollup uses to bucket
# rolled-up timestamps composes cleanly with the stored column.
# `hour_of_day_utc` is `0..23`. Both are enforced with CHECK constraints
# at the DB level so a misbehaving sync cannot land out-of-range values.
class CreateVideoViewerTimeBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :video_viewer_time_buckets do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false
      t.integer :hour_of_day_utc, null: false
      t.integer :day_of_week_utc, null: false
      t.integer :view_count, null: false, default: 0
      t.bigint  :watch_time_seconds, null: false, default: 0
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :video_viewer_time_buckets,
              %i[video_id day_of_week_utc hour_of_day_utc],
              unique: true,
              name: :index_viewer_time_buckets_uniq

    add_index :video_viewer_time_buckets, :last_synced_at

    # Range constraints at the DB level — match the application-layer
    # validations belt-and-braces. A misbehaving sync (or a hand-edit)
    # cannot land out-of-range values.
    add_check_constraint :video_viewer_time_buckets,
                         "hour_of_day_utc BETWEEN 0 AND 23",
                         name: :viewer_time_buckets_hour_range
    add_check_constraint :video_viewer_time_buckets,
                         "day_of_week_utc BETWEEN 0 AND 6",
                         name: :viewer_time_buckets_dow_range
    add_check_constraint :video_viewer_time_buckets,
                         "view_count >= 0",
                         name: :viewer_time_buckets_view_count_nonneg
    add_check_constraint :video_viewer_time_buckets,
                         "watch_time_seconds >= 0",
                         name: :viewer_time_buckets_watch_time_nonneg
  end
end
