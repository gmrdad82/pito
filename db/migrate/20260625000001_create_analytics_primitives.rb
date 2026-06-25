# frozen_string_literal: true

# Creates the analytics_primitives table used by Pito::Analytics::Primitives.
#
# A primitive is an ENTITY-AGNOSTIC per-video raw-count row — keyed by the video
# + report + resolved date range — that composes into any scope (game / channel /
# @all). It is NOT keyed by game/channel: a video's primitive cached while
# analyzing one entity is reused with no YouTube call for any later entity that
# shares that video.
#
#   video_youtube_id — the YouTube video id the row holds metrics for.
#   report           — which report group ("scalars", "daily", "country", …).
#   period_token     — the window token used (informational; e.g. "7d", "m1").
#   start_date/end_date — the RESOLVED date range (the real cache key, so two
#                       tokens that resolve to the same range share one row).
#   metrics          — jsonb raw counts (object, or array for snapshot reports).
#   fetched_at       — when the row was fetched from YouTube.
#   expires_at       — TTL; nil = frozen forever (a completed period that can no
#                       longer change). Live windows carry a short TTL.
class CreateAnalyticsPrimitives < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_primitives do |t|
      t.date     :end_date,         null: false
      t.datetime :expires_at
      t.datetime :fetched_at,       null: false
      t.jsonb    :metrics,          null: false, default: {}
      t.string   :period_token,     null: false
      t.string   :report,           null: false
      t.date     :start_date,       null: false
      t.string   :video_youtube_id, null: false
      t.timestamps
    end

    # The real cache/dedup key is the resolved date range (not the token), so a
    # 7d window and a discrete month that resolve to the same range share a row.
    add_index :analytics_primitives,
              %i[video_youtube_id report start_date end_date],
              unique: true,
              name: "index_analytics_primitives_on_video_report_range"

    add_index :analytics_primitives, :expires_at,
              name: "index_analytics_primitives_on_expires_at"
  end
end
