# Phase 13.1 — Analytics data model. Single migration creating every
# analytics table from Note 3 (`docs/notes/2026-05-09-18-19-27-
# analytics-model-youtube-api.md`):
#
#   * `analytics_window` Postgres enum — `7d`, `28d`, `90d`, `lifetime`.
#   * `channel_dailies` — Note 3 §C1 (channel daily spine).
#   * `video_dailies` — Note 3 §V1 (video daily spine).
#   * `video_daily_by_countries` — Note 3 §V3.
#   * `video_daily_by_device_types` — Note 3 §V4 (device split).
#   * `video_daily_by_operating_systems` — Note 3 §V4 (OS split, separate
#     table per spec 01 to keep the natural key clean).
#   * `video_daily_by_traffic_sources` — Note 3 §V5.
#   * `video_daily_by_subscribed_statuses` — Note 3 §V6
#     (subscribed_status only; creator_content_type deferred per master
#     agent decision #1).
#   * `video_daily_by_age_group_genders` — Note 3 §V8 (demographics).
#   * `channel_window_summaries` — Note 3 §C2 (Studio-faithful ratios).
#   * `video_window_summaries` — Note 3 §V2.
#   * `top_videos_windows` — Note 3 §C3 (leaderboard).
#   * `video_retentions` — Note 3 §V7 (retention curve).
#
# Locked decisions:
#   * No `tenant_id` on any table (ADR 0003).
#   * FK to `channels(id)` / `videos(id)` with ON DELETE CASCADE.
#   * Every per-day row carries a UNIQUE composite index on its natural
#     key — sync engine `upsert_all` target.
#   * Counters → `bigint NOT NULL DEFAULT 0`. Ratios → `numeric(10, 6)
#     NULL`. Durations → `numeric(10, 2) NULL`. Money → `numeric(12, 4)
#     NULL`.
#   * Monetization columns are nullable; sync engine writes NULL until a
#     `MONETIZATION_ENABLED` feature flag flips (spec 02 owns).
#   * `video_retentions` uses `computed_at timestamptz NOT NULL` only —
#     no `created_at` / `updated_at` pair. The retention curve is
#     recomputed-in-place, not row-history.
class CreateAnalyticsTables < ActiveRecord::Migration[8.1]
  def up
    # ───────────────────────────────────────────────────────────────────
    # Postgres enum — analytics_window. Used by *_window_summary and
    # top_videos_windows.window. Note 3's exact strings.
    # ───────────────────────────────────────────────────────────────────
    execute(<<~SQL)
      CREATE TYPE analytics_window AS ENUM ('7d', '28d', '90d', 'lifetime');
    SQL

    # ───────────────────────────────────────────────────────────────────
    # channel_dailies — Note 3 §C1
    # ───────────────────────────────────────────────────────────────────
    create_table :channel_dailies do |t|
      t.references :channel,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false

      # Views
      t.bigint :views,                         null: false, default: 0
      t.bigint :engaged_views,                 null: false, default: 0
      t.bigint :red_views,                     null: false, default: 0

      # Watch time
      t.bigint :estimated_minutes_watched,     null: false, default: 0
      t.bigint :estimated_red_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration, precision: 10, scale: 2

      # Engagement
      t.bigint :likes,                         null: false, default: 0
      t.bigint :dislikes,                      null: false, default: 0
      t.bigint :comments,                      null: false, default: 0
      t.bigint :shares,                        null: false, default: 0
      t.bigint :videos_added_to_playlists,     null: false, default: 0
      t.bigint :videos_removed_from_playlists, null: false, default: 0

      # Subscribers
      t.bigint :subscribers_gained,            null: false, default: 0
      t.bigint :subscribers_lost,              null: false, default: 0

      # Impressions / cards
      t.bigint :video_thumbnail_impressions,   null: false, default: 0
      t.bigint :card_impressions,              null: false, default: 0
      t.bigint :card_clicks,                   null: false, default: 0
      t.bigint :card_teaser_impressions,       null: false, default: 0
      t.bigint :card_teaser_clicks,            null: false, default: 0

      # Monetization (nullable; sync-disabled until MONETIZATION_ENABLED flips)
      t.decimal :estimated_revenue,             precision: 12, scale: 4
      t.decimal :estimated_ad_revenue,          precision: 12, scale: 4
      t.decimal :gross_revenue,                 precision: 12, scale: 4
      t.decimal :estimated_red_partner_revenue, precision: 12, scale: 4
      t.bigint :monetized_playbacks
      t.bigint :ad_impressions

      t.timestamps
    end
    add_index :channel_dailies, %i[channel_id date], unique: true
    add_index :channel_dailies, :date

    # ───────────────────────────────────────────────────────────────────
    # video_dailies — Note 3 §V1 (same metric set as channel_dailies)
    # ───────────────────────────────────────────────────────────────────
    create_table :video_dailies do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false

      t.bigint :views,                         null: false, default: 0
      t.bigint :engaged_views,                 null: false, default: 0
      t.bigint :red_views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched,     null: false, default: 0
      t.bigint :estimated_red_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration, precision: 10, scale: 2
      t.bigint :likes,                         null: false, default: 0
      t.bigint :dislikes,                      null: false, default: 0
      t.bigint :comments,                      null: false, default: 0
      t.bigint :shares,                        null: false, default: 0
      t.bigint :videos_added_to_playlists,     null: false, default: 0
      t.bigint :videos_removed_from_playlists, null: false, default: 0
      t.bigint :subscribers_gained,            null: false, default: 0
      t.bigint :subscribers_lost,              null: false, default: 0
      t.bigint :video_thumbnail_impressions,   null: false, default: 0
      t.bigint :card_impressions,              null: false, default: 0
      t.bigint :card_clicks,                   null: false, default: 0
      t.bigint :card_teaser_impressions,       null: false, default: 0
      t.bigint :card_teaser_clicks,            null: false, default: 0
      t.decimal :estimated_revenue,             precision: 12, scale: 4
      t.decimal :estimated_ad_revenue,          precision: 12, scale: 4
      t.decimal :gross_revenue,                 precision: 12, scale: 4
      t.decimal :estimated_red_partner_revenue, precision: 12, scale: 4
      t.bigint :monetized_playbacks
      t.bigint :ad_impressions

      t.timestamps
    end
    add_index :video_dailies, %i[video_id date], unique: true
    add_index :video_dailies, :date

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_countries — Note 3 §V3
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_countries do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :country_code, null: false

      t.bigint :views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration,   precision: 10, scale: 2
      t.decimal :average_view_percentage, precision: 10, scale: 6

      t.timestamps
    end
    add_index :video_daily_by_countries,
              %i[video_id date country_code],
              unique: true,
              name: "idx_video_daily_by_country_uniq"
    add_index :video_daily_by_countries, :country_code

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_device_types — Note 3 §V4 (device split)
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_device_types do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :device_type, null: false

      t.bigint :views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration,   precision: 10, scale: 2
      t.decimal :average_view_percentage, precision: 10, scale: 6

      t.timestamps
    end
    add_index :video_daily_by_device_types,
              %i[video_id date device_type],
              unique: true,
              name: "idx_video_daily_by_device_type_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_operating_systems — Note 3 §V4 (OS split)
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_operating_systems do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :operating_system, null: false

      t.bigint :views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration,   precision: 10, scale: 2
      t.decimal :average_view_percentage, precision: 10, scale: 6

      t.timestamps
    end
    add_index :video_daily_by_operating_systems,
              %i[video_id date operating_system],
              unique: true,
              name: "idx_video_daily_by_os_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_traffic_sources — Note 3 §V5
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_traffic_sources do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :traffic_source_type, null: false

      t.bigint :views,                       null: false, default: 0
      t.bigint :estimated_minutes_watched,   null: false, default: 0
      t.bigint :video_thumbnail_impressions, null: false, default: 0
      t.decimal :video_thumbnail_impressions_click_rate,
                precision: 10, scale: 6

      t.timestamps
    end
    add_index :video_daily_by_traffic_sources,
              %i[video_id date traffic_source_type],
              unique: true,
              name: "idx_video_daily_by_traffic_source_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_subscribed_statuses — Note 3 §V6
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_subscribed_statuses do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :subscribed_status, null: false

      t.bigint :views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched, null: false, default: 0
      t.decimal :average_view_percentage, precision: 10, scale: 6

      t.timestamps
    end
    add_index :video_daily_by_subscribed_statuses,
              %i[video_id date subscribed_status],
              unique: true,
              name: "idx_video_daily_by_subscribed_status_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_daily_by_age_group_genders — Note 3 §V8
    # ───────────────────────────────────────────────────────────────────
    create_table :video_daily_by_age_group_genders do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.text :age_group, null: false
      t.text :gender,    null: false

      # viewer_percentage is NOT NULL with default 0 per spec 01.
      t.decimal :viewer_percentage, precision: 10, scale: 6,
                                    null: false, default: 0

      t.timestamps
    end
    add_index :video_daily_by_age_group_genders,
              %i[video_id date age_group gender],
              unique: true,
              name: "idx_video_daily_by_age_gender_uniq"

    # ───────────────────────────────────────────────────────────────────
    # channel_window_summaries — Note 3 §C2
    # ───────────────────────────────────────────────────────────────────
    create_table :channel_window_summaries do |t|
      t.references :channel,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.column :window, :analytics_window, null: false
      t.date :window_start, null: false
      t.date :window_end,   null: false

      # C1 metric set (verbatim from channel_dailies)
      t.bigint :views,                         null: false, default: 0
      t.bigint :engaged_views,                 null: false, default: 0
      t.bigint :red_views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched,     null: false, default: 0
      t.bigint :estimated_red_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration, precision: 10, scale: 2
      t.bigint :likes,                         null: false, default: 0
      t.bigint :dislikes,                      null: false, default: 0
      t.bigint :comments,                      null: false, default: 0
      t.bigint :shares,                        null: false, default: 0
      t.bigint :videos_added_to_playlists,     null: false, default: 0
      t.bigint :videos_removed_from_playlists, null: false, default: 0
      t.bigint :subscribers_gained,            null: false, default: 0
      t.bigint :subscribers_lost,              null: false, default: 0
      t.bigint :video_thumbnail_impressions,   null: false, default: 0
      t.bigint :card_impressions,              null: false, default: 0
      t.bigint :card_clicks,                   null: false, default: 0
      t.bigint :card_teaser_impressions,       null: false, default: 0
      t.bigint :card_teaser_clicks,            null: false, default: 0
      t.decimal :estimated_revenue,             precision: 12, scale: 4
      t.decimal :estimated_ad_revenue,          precision: 12, scale: 4
      t.decimal :gross_revenue,                 precision: 12, scale: 4
      t.decimal :estimated_red_partner_revenue, precision: 12, scale: 4
      t.bigint :monetized_playbacks
      t.bigint :ad_impressions

      # Studio-faithful ratios (the four non-summable)
      t.decimal :average_view_percentage,                precision: 10, scale: 6
      t.decimal :video_thumbnail_impressions_click_rate, precision: 10, scale: 6
      t.decimal :card_click_rate,                        precision: 10, scale: 6
      t.decimal :card_teaser_click_rate,                 precision: 10, scale: 6

      # Money ratios (monetization)
      t.decimal :playback_based_cpm, precision: 12, scale: 4
      t.decimal :cpm,                precision: 12, scale: 4

      t.timestamps
    end
    add_index :channel_window_summaries,
              %i[channel_id window],
              unique: true,
              name: "idx_channel_window_summary_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_window_summaries — Note 3 §V2
    # ───────────────────────────────────────────────────────────────────
    create_table :video_window_summaries do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.column :window, :analytics_window, null: false
      t.date :window_start, null: false
      t.date :window_end,   null: false

      t.bigint :views,                         null: false, default: 0
      t.bigint :engaged_views,                 null: false, default: 0
      t.bigint :red_views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched,     null: false, default: 0
      t.bigint :estimated_red_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration, precision: 10, scale: 2
      t.bigint :likes,                         null: false, default: 0
      t.bigint :dislikes,                      null: false, default: 0
      t.bigint :comments,                      null: false, default: 0
      t.bigint :shares,                        null: false, default: 0
      t.bigint :videos_added_to_playlists,     null: false, default: 0
      t.bigint :videos_removed_from_playlists, null: false, default: 0
      t.bigint :subscribers_gained,            null: false, default: 0
      t.bigint :subscribers_lost,              null: false, default: 0
      t.bigint :video_thumbnail_impressions,   null: false, default: 0
      t.bigint :card_impressions,              null: false, default: 0
      t.bigint :card_clicks,                   null: false, default: 0
      t.bigint :card_teaser_impressions,       null: false, default: 0
      t.bigint :card_teaser_clicks,            null: false, default: 0
      t.decimal :estimated_revenue,             precision: 12, scale: 4
      t.decimal :estimated_ad_revenue,          precision: 12, scale: 4
      t.decimal :gross_revenue,                 precision: 12, scale: 4
      t.decimal :estimated_red_partner_revenue, precision: 12, scale: 4
      t.bigint :monetized_playbacks
      t.bigint :ad_impressions

      t.decimal :average_view_percentage,                precision: 10, scale: 6
      t.decimal :video_thumbnail_impressions_click_rate, precision: 10, scale: 6
      t.decimal :card_click_rate,                        precision: 10, scale: 6
      t.decimal :card_teaser_click_rate,                 precision: 10, scale: 6
      t.decimal :playback_based_cpm,                     precision: 12, scale: 4
      t.decimal :cpm,                                    precision: 12, scale: 4

      t.timestamps
    end
    add_index :video_window_summaries,
              %i[video_id window],
              unique: true,
              name: "idx_video_window_summary_uniq"

    # ───────────────────────────────────────────────────────────────────
    # top_videos_windows — Note 3 §C3 (leaderboard)
    # ───────────────────────────────────────────────────────────────────
    create_table :top_videos_windows do |t|
      t.references :channel,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.column :window, :analytics_window, null: false
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.integer :rank, null: false

      t.bigint :views,                     null: false, default: 0
      t.bigint :estimated_minutes_watched, null: false, default: 0
      t.decimal :average_view_duration,   precision: 10, scale: 2
      t.decimal :average_view_percentage, precision: 10, scale: 6
      t.bigint :subscribers_gained,        null: false, default: 0
      t.bigint :likes,                     null: false, default: 0
      t.bigint :comments,                  null: false, default: 0

      t.timestamps
    end
    add_index :top_videos_windows,
              %i[channel_id window video_id],
              unique: true,
              name: "idx_top_videos_window_video_uniq"
    add_index :top_videos_windows,
              %i[channel_id window rank],
              unique: true,
              name: "idx_top_videos_window_rank_uniq"

    # ───────────────────────────────────────────────────────────────────
    # video_retentions — Note 3 §V7 (retention curve)
    # No created_at / updated_at — `computed_at` is the sole timestamp.
    # ───────────────────────────────────────────────────────────────────
    create_table :video_retentions do |t|
      t.references :video,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.decimal :elapsed_ratio_bucket, precision: 5, scale: 4, null: false

      t.decimal :audience_watch_ratio,           precision: 10, scale: 6
      t.decimal :relative_retention_performance, precision: 10, scale: 6
      t.bigint :started_watching,          null: false, default: 0
      t.bigint :stopped_watching,          null: false, default: 0
      t.bigint :total_segment_impressions, null: false, default: 0

      t.column :computed_at, :timestamptz,
               null: false,
               default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :video_retentions,
              %i[video_id elapsed_ratio_bucket],
              unique: true,
              name: "idx_video_retention_bucket_uniq"
  end

  def down
    drop_table :video_retentions
    drop_table :top_videos_windows
    drop_table :video_window_summaries
    drop_table :channel_window_summaries
    drop_table :video_daily_by_age_group_genders
    drop_table :video_daily_by_subscribed_statuses
    drop_table :video_daily_by_traffic_sources
    drop_table :video_daily_by_operating_systems
    drop_table :video_daily_by_device_types
    drop_table :video_daily_by_countries
    drop_table :video_dailies
    drop_table :channel_dailies

    execute("DROP TYPE IF EXISTS analytics_window;")
  end
end
