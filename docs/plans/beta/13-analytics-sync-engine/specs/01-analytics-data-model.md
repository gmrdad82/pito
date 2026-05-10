# Phase 13.1 — Analytics Data Model

> **Status:** dispatched 2026-05-10. Single-lane: **rails**. First of three
> specs in Phase 13 (analytics sync engine + tables + dashboard). This spec
> covers ONLY the schema. Sync engine = spec 02; dashboard = spec 03.
>
> **Cross-references:**
>
> - `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — source of
>   truth for every table enumerated below.
> - `docs/realignment-2026-05-09.md` — work unit 5; "split into sub-units."
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
>   `tenant_id` on any new table.
> - `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
>   `YoutubeConnection` exists; FK targets reference it.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — destructive-and-reseed migration posture inherited.
> - `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
>   — `youtube_connections` table exists; FK column convention is
>   `youtube_connection_id`.
> - `docs/plans/beta/12-video-schema-expansion/` — Video schema with
>   `youtube_video_id`, `published_at`, `category_id`, `duration`, `tags`.
> - `docs/plans/beta/13-analytics-sync-engine/specs/02-analytics-sync-engine.md`
>   — consumes every table defined here.
> - `docs/plans/beta/13-analytics-sync-engine/specs/03-analytics-dashboard.md` —
>   reads every table defined here.
> - `CLAUDE.md` — top-level rules.

## Goal

Land the full analytics data model in one migration sweep. Every table from Note
3 — daily time-series tables (channel, video), sliced daily tables (six slices),
windowed-summary tables (channel, video), the top-videos leaderboard, and the
per-video retention curve. Schema-only. No model behavior beyond associations +
scopes that downstream specs will need. No sync code. No views.

After this spec lands, the database holds empty tables ready for the sync engine
(spec 02) to populate. The dashboard (spec 03) consumes the populated tables.

This is the schema spine for the entire YouTube management workflow's analytics
surface. Get the columns right; everything else flows.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                              |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Tenant-free.** No `tenant_id` on any analytics table. Per ADR 0003.                                                                                                                                                                                                                                                                 |
| Q2  | **FK targets.** `channel_daily.channel_id → channels.id`. `video_daily.video_id → videos.id`. No FK to `youtube_connections` on the analytics tables; the sync engine resolves connections at write time.                                                                                                                             |
| Q3  | **Numeric storage.** Counters (`views`, `likes`, etc.) → `bigint NOT NULL DEFAULT 0`. Ratios / percentages (`average_view_percentage`, `card_click_rate`, etc.) → `numeric(10, 6) NULL`. Durations in seconds (`average_view_duration`) → `numeric(10, 2) NULL`. Money (`estimated_revenue`, `cpm`) → `numeric(12, 4) NULL` (see Q5). |
| Q4  | **Column naming.** Convert YouTube's camelCase to snake_case (`videoThumbnailImpressions` → `video_thumbnail_impressions`). Direct mapping; no abbreviation. Preserves Note 3's metric grouping (Views / Watch time / Engagement / Subscribers / Impressions / Cards / Retention / Demographics / Live / Playlist / Revenue).         |
| Q5  | **Monetization columns.** Schema-ready, sync-disabled. Every revenue column lands as nullable; the sync engine (spec 02) writes NULL until a `MONETIZATION_ENABLED` feature flag flips. Per Note 3 "Monetization posture."                                                                                                            |
| Q6  | **Window enum values.** `'7d'`, `'28d'`, `'90d'`, `'lifetime'` stored as Postgres enum (`analytics_window`). Per Note 3's exact strings.                                                                                                                                                                                              |
| Q7  | **Slice enum values.** `'country'`, `'device_type'`, `'operating_system'`, `'traffic_source'`, `'subscribed_status'`, `'age_group_gender'` — six slices, one table per slice per Note 3's "Storage strategy" block.                                                                                                                   |
| Q8  | **Retention bucket.** `elapsed_ratio_bucket numeric(5, 4)` (range `0.0000` to `1.0000`, two decimal precision = 100 buckets per Note 3's "~100 rows per video"). Stored exactly as YouTube returns it; no quantization.                                                                                                               |
| Q9  | **Date type.** All time-series rows use `date` (not `timestamp`). YouTube Analytics returns Pacific-Time day boundaries — see Note 3 "Mutual-exclusion gotchas" §8. The sync engine (spec 02) is responsible for the timezone conversion when querying; the column stores the YouTube-PT date as-is.                                  |
| Q10 | **Idempotency.** Every per-day row uses a unique composite index on its natural key — `(channel_id, date)`, `(video_id, date)`, `(video_id, date, country_code)`, etc. Sync engine upserts via `upsert_all` against this key.                                                                                                         |
| Q11 | **Cascade behavior.** `dependent: :delete_all` from `Channel` / `Video` to every analytics table that references them. Analytics rows are derived; deleting the parent wipes them. No orphan retention.                                                                                                                               |
| Q12 | **Migration ordering.** Single migration file. Tables created parent-first (already exist: `channels`, `videos`, `youtube_connections`) then enums then daily time-series, then sliced daily, then windowed summaries, then top-videos, then retention. Single sweep so a partial migration cannot leave half the surface live.       |
| Q13 | **Playlist analytics — defer.** Note 3 §"Playlist queries" warns that `isCurated==1` is being deprecated; the filter shape is in flight. Playlist analytics tables are NOT created in this spec. Surface as an explicit non-goal. The Playlist Sync follow-up files when YouTube's revision history settles.                          |
| Q14 | **Cross-video local rollups — no separate tables.** Note 3 §"Cross-video questions (computed locally)" is satisfied by joining `videos` against `video_window_summary` and `video_daily` at query time. No precomputed `topics_that_work` / `best_duration_buckets` tables; the dashboard (spec 03) owns the SQL.                     |
| Q15 | **Computed-at column.** `video_retention.computed_at timestamptz NOT NULL` per Note 3's literal listing. All other analytics tables use the standard Rails `created_at, updated_at` pair. The retention table's `computed_at` is the spec-explicit name; do not collapse into `updated_at`.                                           |

## Migration posture (LOCKED)

**Additive.** Phase 8 reseed is past; no destructive sweep is licensed here. The
migration creates new tables only — no drops, no renames, no column changes on
existing tables. Every existing migration in `db/migrate/` stays untouched. Down
migrations drop the new tables in reverse order. `down` is permitted but not
load-bearing for testing (no production data).

If the implementation agent finds during the sweep that an enum collision exists
(Postgres enums are global per database), STOP and surface — the spec expects no
collisions.

## Files touched

### Schema / migration

- `db/migrate/<NN>_create_analytics_tables.rb` (new) — single migration named
  per Rails 8.1 convention (`<YYYYMMDDHHMMSS>_create_analytics_tables.rb`).
  Scope outlined below in **Schema (table-by-table)**.
- `db/schema.rb` — auto-regenerated; verify every table below appears.

### Models (new)

- `app/models/channel_daily.rb`
- `app/models/video_daily.rb`
- `app/models/video_daily_by_country.rb`
- `app/models/video_daily_by_device_type.rb`
- `app/models/video_daily_by_operating_system.rb`
- `app/models/video_daily_by_traffic_source.rb`
- `app/models/video_daily_by_subscribed_status.rb`
- `app/models/video_daily_by_age_group_gender.rb`
- `app/models/channel_window_summary.rb`
- `app/models/video_window_summary.rb`
- `app/models/top_videos_window.rb`
- `app/models/video_retention.rb`

Each model: `belongs_to` parent, scopes for the windows / dates that the
dashboard will need, NO sync logic (spec 02 owns that), NO chart helpers (spec
03 owns that).

### Models (edit)

- `app/models/channel.rb`:
  - `has_many :channel_dailies, dependent: :delete_all`
  - `has_many :channel_window_summaries, dependent: :delete_all`
  - `has_many :top_videos_windows, dependent: :delete_all`
- `app/models/video.rb`:
  - `has_many :video_dailies, dependent: :delete_all`
  - `has_many :video_daily_by_countries, dependent: :delete_all`
  - `has_many :video_daily_by_device_types, dependent: :delete_all`
  - `has_many :video_daily_by_operating_systems, dependent: :delete_all`
  - `has_many :video_daily_by_traffic_sources, dependent: :delete_all`
  - `has_many :video_daily_by_subscribed_statuses, dependent: :delete_all`
  - `has_many :video_daily_by_age_group_genders, dependent: :delete_all`
  - `has_many :video_window_summaries, dependent: :delete_all`
  - `has_many :video_retentions, dependent: :delete_all`

### Factories (new)

One factory per new model. Standard FactoryBot shape, no traits beyond the
smallest set the spec writers need (window-of-7d trait on summaries; slice-of-X
traits on the slice tables). The implementation agent picks trait sparseness;
the test sweep below names every callsite that needs one.

### Documentation (post-implementation; dispatched separately to docs-keeper)

The Rails implementation does NOT touch these files. After validation:

- `docs/architecture.md` — append an "Analytics subsystem (data model)" section
  pointing at this spec.
- `CLAUDE.md` — add the analytics tables to the Architecture-notes table list
  (one bullet line each).

These edits are NOT part of the rails-impl dispatch's file scope.

## Schema (table-by-table)

Every column listed below is required in the migration. Defaults and nullability
are explicit. The migration uses Rails' `t.column` helpers; the implementation
agent picks the precise DSL.

### Enum types (Postgres)

```sql
CREATE TYPE analytics_window AS ENUM ('7d', '28d', '90d', 'lifetime');
```

Used by: `channel_window_summary.window`, `video_window_summary.window`,
`top_videos_window.window`.

No other enum is defined; slice values are stored as plain `text` columns
because YouTube's vocabulary for `country`, `traffic_source`, etc. is ungoverned
and we do not gate writes on the enum surface.

### `channel_daily` — Note 3 §C1 (the channel spine)

| Column                          | Type             | Null | Default | Notes                                             |
| ------------------------------- | ---------------- | ---- | ------- | ------------------------------------------------- |
| `id`                            | `bigint`         | NO   | seq     | Standard Rails PK.                                |
| `channel_id`                    | `bigint`         | NO   |         | FK → `channels(id)` ON DELETE CASCADE.            |
| `date`                          | `date`           | NO   |         | YouTube Pacific-Time day.                         |
| `views`                         | `bigint`         | NO   | 0       | C1 metric.                                        |
| `engaged_views`                 | `bigint`         | NO   | 0       |                                                   |
| `red_views`                     | `bigint`         | NO   | 0       | YouTube Premium views.                            |
| `estimated_minutes_watched`     | `bigint`         | NO   | 0       |                                                   |
| `estimated_red_minutes_watched` | `bigint`         | NO   | 0       |                                                   |
| `average_view_duration`         | `numeric(10, 2)` | YES  |         | Seconds. Derivable from sums but cached for perf. |
| `likes`                         | `bigint`         | NO   | 0       |                                                   |
| `dislikes`                      | `bigint`         | NO   | 0       |                                                   |
| `comments`                      | `bigint`         | NO   | 0       |                                                   |
| `shares`                        | `bigint`         | NO   | 0       |                                                   |
| `videos_added_to_playlists`     | `bigint`         | NO   | 0       |                                                   |
| `videos_removed_from_playlists` | `bigint`         | NO   | 0       |                                                   |
| `subscribers_gained`            | `bigint`         | NO   | 0       |                                                   |
| `subscribers_lost`              | `bigint`         | NO   | 0       |                                                   |
| `video_thumbnail_impressions`   | `bigint`         | NO   | 0       |                                                   |
| `card_impressions`              | `bigint`         | NO   | 0       |                                                   |
| `card_clicks`                   | `bigint`         | NO   | 0       |                                                   |
| `card_teaser_impressions`       | `bigint`         | NO   | 0       |                                                   |
| `card_teaser_clicks`            | `bigint`         | NO   | 0       |                                                   |
| `estimated_revenue`             | `numeric(12, 4)` | YES  |         | Monetization. NULL until flag flips. Per Q5.      |
| `estimated_ad_revenue`          | `numeric(12, 4)` | YES  |         | Monetization.                                     |
| `gross_revenue`                 | `numeric(12, 4)` | YES  |         | Monetization.                                     |
| `estimated_red_partner_revenue` | `numeric(12, 4)` | YES  |         | Monetization.                                     |
| `monetized_playbacks`           | `bigint`         | YES  |         | Monetization.                                     |
| `ad_impressions`                | `bigint`         | YES  |         | Monetization.                                     |
| `created_at`                    | `timestamptz`    | NO   | now()   |                                                   |
| `updated_at`                    | `timestamptz`    | NO   | now()   |                                                   |

**Indexes:**

- UNIQUE `(channel_id, date)` — natural key. Sync engine `upsert_all` target.
- `(date)` — for cross-channel "what was that day" queries (rare, but cheap).
- FK index on `(channel_id)` — implicit via
  `add_reference :channel, foreign_key: { on_delete: :cascade }, index: true`.

**Notes:**

- `average_view_percentage`, `video_thumbnail_impressions_click_rate`,
  `card_click_rate`, `card_teaser_click_rate` are intentionally absent. Per Note
  3 §C1: "non-summable; should come from C2 instead." Those metrics live on
  `channel_window_summary`.

### `video_daily` — Note 3 §V1 (the video spine)

Same column set as `channel_daily`, plus `video_id` instead of `channel_id`.

| Column                                                            | Type          | Null | Default | Notes                                |
| ----------------------------------------------------------------- | ------------- | ---- | ------- | ------------------------------------ |
| `id`                                                              | `bigint`      | NO   | seq     |                                      |
| `video_id`                                                        | `bigint`      | NO   |         | FK → `videos(id)` ON DELETE CASCADE. |
| `date`                                                            | `date`        | NO   |         |                                      |
| (every metric column from `channel_daily`'s list — copy verbatim) |               |      |         | Same nullability + defaults.         |
| `created_at`                                                      | `timestamptz` | NO   | now()   |                                      |
| `updated_at`                                                      | `timestamptz` | NO   | now()   |                                      |

**Indexes:**

- UNIQUE `(video_id, date)` — natural key.
- `(date)` — cross-video day queries.
- FK index on `(video_id)` — implicit.

### Sliced daily tables (six tables)

Schema shape: `(video_id, date, slice_value, [metrics])`. One table per slice
per Note 3 §V3-V6, V8.

#### `video_daily_by_country` — Note 3 §V3

| Column                      | Type             | Null | Default |
| --------------------------- | ---------------- | ---- | ------- |
| `id`                        | `bigint`         | NO   | seq     |
| `video_id`                  | `bigint`         | NO   |         |
| `date`                      | `date`           | NO   |         |
| `country_code`              | `text`           | NO   |         |
| `views`                     | `bigint`         | NO   | 0       |
| `estimated_minutes_watched` | `bigint`         | NO   | 0       |
| `average_view_duration`     | `numeric(10, 2)` | YES  |         |
| `average_view_percentage`   | `numeric(10, 6)` | YES  |         |
| `created_at`, `updated_at`  |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, country_code)`.
- `(country_code)` — cross-video country rollup at query time.

**Notes:** YouTube returns ISO 3166-1 alpha-2 codes (`US`, `GB`, etc.) and the
value `ZZ` for "unknown / not set." Stored verbatim.

#### `video_daily_by_device_type` — Note 3 §V4 (device split)

| Column                      | Type             | Null | Default |
| --------------------------- | ---------------- | ---- | ------- |
| `id`                        | `bigint`         | NO   | seq     |
| `video_id`                  | `bigint`         | NO   |         |
| `date`                      | `date`           | NO   |         |
| `device_type`               | `text`           | NO   |         |
| `views`                     | `bigint`         | NO   | 0       |
| `estimated_minutes_watched` | `bigint`         | NO   | 0       |
| `average_view_duration`     | `numeric(10, 2)` | YES  |         |
| `average_view_percentage`   | `numeric(10, 6)` | YES  |         |
| `created_at`, `updated_at`  |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, device_type)`.

**Notes:** YouTube vocabulary: `MOBILE`, `TABLET`, `DESKTOP`, `TV`,
`GAME_CONSOLE`, `UNKNOWN_PLATFORM`. Stored verbatim.

#### `video_daily_by_operating_system` — Note 3 §V4 (OS split — separate from device)

Note 3's V4 query passes both `deviceType` and `operatingSystem` as dimensions
in one call (`dimensions=deviceType,operatingSystem`). The data model splits
them into two tables to keep the natural key clean and the upsert simple. The
sync engine (spec 02) issues two separate API calls (one per dimension) rather
than parsing the cross-product back into two tables, OR splits a single response
— agent picks; spec 02 commits.

| Column                      | Type             | Null | Default |
| --------------------------- | ---------------- | ---- | ------- |
| `id`                        | `bigint`         | NO   | seq     |
| `video_id`                  | `bigint`         | NO   |         |
| `date`                      | `date`           | NO   |         |
| `operating_system`          | `text`           | NO   |         |
| `views`                     | `bigint`         | NO   | 0       |
| `estimated_minutes_watched` | `bigint`         | NO   | 0       |
| `average_view_duration`     | `numeric(10, 2)` | YES  |         |
| `average_view_percentage`   | `numeric(10, 6)` | YES  |         |
| `created_at`, `updated_at`  |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, operating_system)`.

**Notes:** YouTube vocabulary: `IOS`, `ANDROID`, `WINDOWS`, `MACINTOSH`,
`LINUX`, `OTHER`, etc.

#### `video_daily_by_traffic_source` — Note 3 §V5

| Column                                   | Type             | Null | Default |
| ---------------------------------------- | ---------------- | ---- | ------- |
| `id`                                     | `bigint`         | NO   | seq     |
| `video_id`                               | `bigint`         | NO   |         |
| `date`                                   | `date`           | NO   |         |
| `traffic_source_type`                    | `text`           | NO   |         |
| `views`                                  | `bigint`         | NO   | 0       |
| `estimated_minutes_watched`              | `bigint`         | NO   | 0       |
| `video_thumbnail_impressions`            | `bigint`         | NO   | 0       |
| `video_thumbnail_impressions_click_rate` | `numeric(10, 6)` | YES  |         |
| `created_at`, `updated_at`               |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, traffic_source_type)`.

**Notes:** YouTube vocabulary (per Analytics docs): `YT_SEARCH`, `EXT_URL`,
`RELATED_VIDEO`, `SUBSCRIBER`, `YT_CHANNEL`, `YT_OTHER_PAGE`, `PLAYLIST`,
`NOTIFICATION`, `SHORTS`, etc. Stored verbatim. The note about
`videoThumbnailImpressionsClickRate` being non-summable applies (the value is
the YouTube-computed rate for that day's slice, not a sum).

#### `video_daily_by_subscribed_status` — Note 3 §V6

V6's actual query is `dimensions=subscribedStatus,creatorContentType`. As with
V4, splitting the cross-product across two tables keeps the schema clean. Two
tables: `video_daily_by_subscribed_status` and (optionally) a
`video_daily_by_creator_content_type` follow-up. The user told the architect
"implement every enumerated view"; the architect interprets this as: subscribed
status is the headline dimension and lands here; creator content type is the
context (Shorts / VOD / Live), which deserves a separate table. **Architect
decision: subscribed status only in this spec; creator content type a follow-up
table to spec.**

| Column                      | Type             | Null | Default |
| --------------------------- | ---------------- | ---- | ------- |
| `id`                        | `bigint`         | NO   | seq     |
| `video_id`                  | `bigint`         | NO   |         |
| `date`                      | `date`           | NO   |         |
| `subscribed_status`         | `text`           | NO   |         |
| `views`                     | `bigint`         | NO   | 0       |
| `estimated_minutes_watched` | `bigint`         | NO   | 0       |
| `average_view_percentage`   | `numeric(10, 6)` | YES  |         |
| `created_at`, `updated_at`  |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, subscribed_status)`.

**Notes:** YouTube vocabulary: `SUBSCRIBED`, `UNSUBSCRIBED`. Two values.

#### `video_daily_by_age_group_gender` — Note 3 §V8 (demographics)

V8's query is `dimensions=ageGroup,gender` with `metrics=viewerPercentage`.
Cross-product modeled as one table since the natural key is the pair. Note 3
explicitly warns: `viewerPercentage` is non-additive and percentages do not
normalize across `subscribedStatus` / `liveOrOnDemand` / `youtubeProduct`. Spec
03 (dashboard) is responsible for not adding extraneous dimensions when reading.

| Column                     | Type             | Null | Default |
| -------------------------- | ---------------- | ---- | ------- |
| `id`                       | `bigint`         | NO   | seq     |
| `video_id`                 | `bigint`         | NO   |         |
| `date`                     | `date`           | NO   |         |
| `age_group`                | `text`           | NO   |         |
| `gender`                   | `text`           | NO   |         |
| `viewer_percentage`        | `numeric(10, 6)` | NO   | 0       |
| `created_at`, `updated_at` |                  |      |         |

**Indexes:**

- UNIQUE `(video_id, date, age_group, gender)`.

**Notes:** YouTube vocabulary for age: `AGE_13_17`, `AGE_18_24`, `AGE_25_34`,
`AGE_35_44`, `AGE_45_54`, `AGE_55_64`, `AGE_65_PLUS`. Gender: `FEMALE`, `MALE`,
`GENDER_OTHER`.

### `channel_window_summary` — Note 3 §C2

One row per `(channel_id, window)` per Note 3's "These give Studio-faithful
ratios" framing. Holds every C1 metric PLUS the four non-summable ratios.

| Column                                                                               | Type               | Null | Default |
| ------------------------------------------------------------------------------------ | ------------------ | ---- | ------- |
| `id`                                                                                 | `bigint`           | NO   | seq     |
| `channel_id`                                                                         | `bigint`           | NO   |         |
| `window`                                                                             | `analytics_window` | NO   |         |
| `window_start`                                                                       | `date`             | NO   |         |
| `window_end`                                                                         | `date`             | NO   |         |
| (all C1 columns from `channel_daily` — copy verbatim including monetization columns) |                    |      |         |
| `average_view_percentage`                                                            | `numeric(10, 6)`   | YES  |         |
| `video_thumbnail_impressions_click_rate`                                             | `numeric(10, 6)`   | YES  |         |
| `card_click_rate`                                                                    | `numeric(10, 6)`   | YES  |         |
| `card_teaser_click_rate`                                                             | `numeric(10, 6)`   | YES  |         |
| `playback_based_cpm`                                                                 | `numeric(12, 4)`   | YES  |         |
| `cpm`                                                                                | `numeric(12, 4)`   | YES  |         |
| `created_at`, `updated_at`                                                           |                    |      |         |

**Indexes:**

- UNIQUE `(channel_id, window)`.

### `video_window_summary` — Note 3 §V2

Same shape as `channel_window_summary` with `video_id` instead of `channel_id`.

| Column                                                                                       | Type               | Null | Default |
| -------------------------------------------------------------------------------------------- | ------------------ | ---- | ------- |
| `id`                                                                                         | `bigint`           | NO   | seq     |
| `video_id`                                                                                   | `bigint`           | NO   |         |
| `window`                                                                                     | `analytics_window` | NO   |         |
| `window_start`                                                                               | `date`             | NO   |         |
| `window_end`                                                                                 | `date`             | NO   |         |
| (all C1 columns + non-summable ratios + monetization — same set as `channel_window_summary`) |                    |      |         |
| `created_at`, `updated_at`                                                                   |                    |      |         |

**Indexes:**

- UNIQUE `(video_id, window)`.

### `top_videos_window` — Note 3 §C3

Leaderboard. One row per `(channel_id, window, video_id)`. Captures the window's
top-N (50 per Note 3 §C3 `maxResults=50`). Note 3 explicitly says sort by
`-estimatedMinutesWatched`; rank is materialized server-side at sync time so
dashboards do not re-sort on every read.

| Column                      | Type               | Null | Default | Notes                                                        |
| --------------------------- | ------------------ | ---- | ------- | ------------------------------------------------------------ |
| `id`                        | `bigint`           | NO   | seq     |                                                              |
| `channel_id`                | `bigint`           | NO   |         |                                                              |
| `window`                    | `analytics_window` | NO   |         |                                                              |
| `video_id`                  | `bigint`           | NO   |         | FK → `videos(id)` ON DELETE CASCADE.                         |
| `rank`                      | `integer`          | NO   |         | 1-based. The leaderboard rank within `(channel_id, window)`. |
| `views`                     | `bigint`           | NO   | 0       |                                                              |
| `estimated_minutes_watched` | `bigint`           | NO   | 0       |                                                              |
| `average_view_duration`     | `numeric(10, 2)`   | YES  |         |                                                              |
| `average_view_percentage`   | `numeric(10, 6)`   | YES  |         |                                                              |
| `subscribers_gained`        | `bigint`           | NO   | 0       |                                                              |
| `likes`                     | `bigint`           | NO   | 0       |                                                              |
| `comments`                  | `bigint`           | NO   | 0       |                                                              |
| `created_at`, `updated_at`  |                    |      |         |                                                              |

**Indexes:**

- UNIQUE `(channel_id, window, video_id)` — natural key (a video appears at most
  once per window).
- UNIQUE `(channel_id, window, rank)` — leaderboard slot uniqueness; rank is
  dense within `(channel_id, window)`.
- `(video_id)` — for "which leaderboards does this video appear on" reads.

### `video_retention` — Note 3 §V7

One row per `(video_id, elapsed_ratio_bucket)`. Refreshed weekly per Note 3.

| Column                           | Type             | Null | Default | Notes                                |
| -------------------------------- | ---------------- | ---- | ------- | ------------------------------------ |
| `id`                             | `bigint`         | NO   | seq     |                                      |
| `video_id`                       | `bigint`         | NO   |         | FK → `videos(id)` ON DELETE CASCADE. |
| `elapsed_ratio_bucket`           | `numeric(5, 4)`  | NO   |         | Range `0.0000` – `1.0000`.           |
| `audience_watch_ratio`           | `numeric(10, 6)` | YES  |         |                                      |
| `relative_retention_performance` | `numeric(10, 6)` | YES  |         |                                      |
| `started_watching`               | `bigint`         | NO   | 0       |                                      |
| `stopped_watching`               | `bigint`         | NO   | 0       |                                      |
| `total_segment_impressions`      | `bigint`         | NO   | 0       |                                      |
| `computed_at`                    | `timestamptz`    | NO   | now()   | Per Q15.                             |

**Indexes:**

- UNIQUE `(video_id, elapsed_ratio_bucket)`.

**Notes:** Per Note 3 V7's "Returns ~100 rows per video" — the bucket
granularity is YouTube's. Stored verbatim. No `created_at` / `updated_at` pair;
`computed_at` is the sole timestamp because the spec is "recomputed-in-place,"
not row-history.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies:

### Schema

- [ ] `db/schema.rb` shows `create_table "channel_daily"` (or `channel_dailies`
      per Rails inflection — agent picks; spec covers both) with every column
      listed above.
- [ ] `db/schema.rb` shows `create_table "video_daily"` with every column listed
      above.
- [ ] `db/schema.rb` shows the six sliced tables (`video_daily_by_country`,
      `video_daily_by_device_type`, `video_daily_by_operating_system`,
      `video_daily_by_traffic_source`, `video_daily_by_subscribed_status`,
      `video_daily_by_age_group_gender`).
- [ ] `db/schema.rb` shows `channel_window_summary` and `video_window_summary`
      with the full metric set including monetization columns and non-summable
      ratios.
- [ ] `db/schema.rb` shows `top_videos_window` with the rank + leaderboard
      shape.
- [ ] `db/schema.rb` shows `video_retention` with `computed_at` (NOT
      `created_at` / `updated_at`).
- [ ] The `analytics_window` enum exists in Postgres
      (`SELECT     typname FROM pg_type WHERE typname = 'analytics_window'`).
- [ ] Every UNIQUE composite index listed above appears in `db/schema.rb`.
- [ ] FK constraints reference `channels(id)` / `videos(id)` with
      `ON DELETE CASCADE`.
- [ ] Migration's `up` runs cleanly:
      `bin/rails db:drop db:create     db:migrate db:seed` succeeds end-to-end.
- [ ] No `tenant_id` column on any new table.

### Models

- [ ] All 12 model files exist and load
      (`Channel.reflect_on_association(:channel_dailies)` returns a non-nil
      `has_many`).
- [ ] Each new model has the right `belongs_to`.
- [ ] `Channel.first.channel_dailies` and `Video.first.video_dailies` are empty
      AR relations on a fresh seed (no rows yet — the sync engine writes them;
      this spec just sets up the join).
- [ ] `dependent: :delete_all` cascade verified: deleting a `Channel` deletes
      its `channel_dailies` rows.
- [ ] Validations on each model: `validates :date, presence: true`,
      `validates :video_id` / `:channel_id, presence: true` (Rails infers via
      `belongs_to`), `validates_uniqueness_of` matching the composite index.
- [ ] Enum on `*_window_summary` and `top_videos_window` models:
      `enum :window, %i[7d 28d 90d lifetime]` (Rails 8.1 enum DSL — the agent
      picks the exact form; the values must round-trip the Postgres enum
      verbatim).

### Factories

- [ ] One factory per new model exists; each generates a valid record with
      default attributes.
- [ ] Factories build with valid associations (`build(:video_daily)` ⇒ builds a
      `Video` + `Channel` chain via `association :video`).
- [ ] Trait coverage matches the test sweep below — at minimum, `:lifetime` /
      `:seven_d` / `:twenty_eight_d` / `:ninety_d` traits on `*_window_summary`
      factories.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] No existing spec breaks. (The new tables are additive.)
- [ ] All new model specs pass. Each one minimally covers: validations,
      associations, scopes the spec defines, the unique-composite-index
      collision (build a duplicate, assert `not be_valid` AND that the DB-level
      index is hit if you insert directly via `upsert_all`).

## Test sweep

Exhaustive coverage. The implementation agent owns the full sweep. Total
enumerated test cases counted at the end.

### Specs to add — model unit specs

One file per model. Each follows the project convention. Total 12 files.

#### `spec/models/channel_daily_spec.rb`

- **Associations:**
  - `it { is_expected.to belong_to(:channel) }`.
- **Validations:**
  - `it "is invalid without a date"`.
  - `it "is invalid without a channel_id"`.
  - `it "is invalid with a duplicate (channel_id, date) pair"` — build two rows
    with same channel + date; assert second is not_valid.
  - `it "rejects a row when (channel_id, date) collides at the DB level"` —
    direct `upsert_all` collision; assert error / no second row.
- **Defaults:**
  - `it "defaults every counter column to 0"` — build a fresh row with only
    required attributes; assert `views == 0`, `likes == 0`, etc. (One assertion
    per counter — agent picks bundling style.)
  - `it "leaves every monetization column NULL"` — assert
    `estimated_revenue.nil?`, etc.
- **Scopes:**
  - `it "scope :for_window(start, end) filters by date range"` — spec 02/03 will
    rely on this scope; define here.
  - `it "scope :ordered_by_date ascends by date"`.

Total: **9** test cases.

#### `spec/models/video_daily_spec.rb`

Same shape as `channel_daily_spec.rb` with `video` instead of `channel`.

Total: **9** test cases.

#### `spec/models/video_daily_by_country_spec.rb`

- **Associations:** `belongs_to(:video)`.
- **Validations:**
  - `it "is invalid without a country_code"`.
  - `it "is invalid with a duplicate (video_id, date, country_code)"`.
- **Defaults:** counters default 0; ratios default NULL.
- **Scopes:**
  - `it "scope :for_country(code) filters"`.
  - `it "scope :for_window(start, end) filters by date range"`.

Total: **6** test cases.

#### `spec/models/video_daily_by_device_type_spec.rb`

Same shape, with `device_type` in place of `country_code`.

Total: **6** test cases.

#### `spec/models/video_daily_by_operating_system_spec.rb`

Same shape, with `operating_system`.

Total: **6** test cases.

#### `spec/models/video_daily_by_traffic_source_spec.rb`

Same shape, with `traffic_source_type`. Add one more case:

- **Special:** `it "stores video_thumbnail_impressions_click_rate as a ratio"` —
  value `0.085` round-trips with full precision.

Total: **7** test cases.

#### `spec/models/video_daily_by_subscribed_status_spec.rb`

Same shape, with `subscribed_status`.

Total: **6** test cases.

#### `spec/models/video_daily_by_age_group_gender_spec.rb`

- **Associations:** `belongs_to(:video)`.
- **Validations:**
  - `it "is invalid without an age_group"`.
  - `it "is invalid without a gender"`.
  - `it "is invalid with a duplicate (video_id, date, age_group, gender)"`.
- **Special:**
  - `it "viewer_percentage defaults to 0 not NULL"` — per the schema table; the
    column is NOT NULL with default 0.
  - `it "round-trips fractional viewer_percentage"` — value `12.345678`
    round-trips at 6 decimal precision.
- **Scopes:**
  - `it "scope :for_age_group(group)"`.
  - `it "scope :for_gender(gender)"`.

Total: **7** test cases.

#### `spec/models/channel_window_summary_spec.rb`

- **Associations:** `belongs_to(:channel)`.
- **Enum:**
  - `it "casts window to one of the analytics_window values"`.
  - `it "rejects an unknown window value"` — `record.window = 'bogus'`; assert
    validation / cast error.
  - `it "round-trips each of the four window values"` — one assertion per
    `'7d'`, `'28d'`, `'90d'`, `'lifetime'`.
- **Validations:**
  - `it "is invalid without window_start / window_end"`.
  - `it "is invalid with a duplicate (channel_id, window)"`.
- **Special:**
  - `it "stores non-summable ratios as nullable numerics"` —
    `average_view_percentage`, `video_thumbnail_impressions_click_rate`,
    `card_click_rate`, `card_teaser_click_rate` round-trip at 6 decimal
    precision; NULL is valid.
  - `it "stores monetization columns as NULL until set"` — every revenue column
    nil on a fresh row.
- **Scopes:**
  - `it "scope :seven_d / :twenty_eight_d / :ninety_d / :lifetime each filters by window"`.

Total: **11** test cases (one per window value collapsed into 1 case).

#### `spec/models/video_window_summary_spec.rb`

Same shape as `channel_window_summary_spec.rb`, with `video` instead of
`channel`.

Total: **11** test cases.

#### `spec/models/top_videos_window_spec.rb`

- **Associations:** `belongs_to(:channel)`, `belongs_to(:video)`.
- **Enum:** `window` round-trips the four values.
- **Validations:**
  - `it "is invalid without rank"`.
  - `it "is invalid with rank < 1"`.
  - `it "is invalid with a duplicate (channel_id, window, video_id)"`.
  - `it "is invalid with a duplicate (channel_id, window, rank)"` — leaderboard
    slot is unique.
- **Scopes:**
  - `it "scope :top_n(n) returns the first n by rank"`.
  - `it "scope :for_window(window) filters by window"`.
- **Special:**
  - `it "is destroyed when its channel is destroyed"` — cascade.
  - `it "is destroyed when its video is destroyed"` — cascade.

Total: **10** test cases.

#### `spec/models/video_retention_spec.rb`

- **Associations:** `belongs_to(:video)`.
- **Validations:**
  - `it "is invalid without elapsed_ratio_bucket"`.
  - `it "rejects elapsed_ratio_bucket < 0 or > 1"` — boundary + out-of-range.
  - `it "is invalid with a duplicate (video_id, elapsed_ratio_bucket)"`.
- **Special:**
  - `it "uses computed_at, not created_at / updated_at"` — assert the column
    exists; assert the timestamps pair does NOT exist.
  - `it "round-trips audience_watch_ratio at 6 decimal precision"`.
  - `it "round-trips relative_retention_performance"`.
  - `it "defaults started_watching / stopped_watching / total_segment_impressions to 0"`.
- **Cascade:**
  - `it "is destroyed when its video is destroyed"`.

Total: **8** test cases.

### Specs to add — schema integrity

#### `spec/db/analytics_schema_spec.rb` (new)

- `it "defines analytics_window as a Postgres enum with the four documented values"`
  — query `pg_enum` directly.
- `it "places UNIQUE indexes on every natural key"` — list all 12 unique
  composite indexes; assert each exists with the right column tuple.
- `it "places ON DELETE CASCADE on every FK to channels and videos"` — query
  `information_schema.referential_constraints`.
- `it "leaves no analytics table with a tenant_id column"` — query
  `information_schema.columns`; assert absence.
- `it "leaves no analytics table with the wrong numeric scale on ratio columns"`
  — assert `numeric(10, 6)` for ratios.
- `it "leaves no analytics table with the wrong numeric scale on duration columns"`
  — assert `numeric(10, 2)` for `average_view_duration`.

Total: **6** test cases.

### Specs to add — model integration sanity

#### `spec/models/analytics_associations_spec.rb` (new)

- `it "Channel.has_many :channel_dailies"` — and the cascade is delete_all.
- `it "Channel.has_many :channel_window_summaries"`.
- `it "Channel.has_many :top_videos_windows"`.
- `it "Video.has_many :video_dailies"`.
- One case per slice — six total.
- `it "Video.has_many :video_window_summaries"`.
- `it "Video.has_many :video_retentions"`.

Total: **11** test cases.

### Test count summary

| Spec file                                              | New cases |
| ------------------------------------------------------ | --------- |
| `spec/models/channel_daily_spec.rb`                    | 9         |
| `spec/models/video_daily_spec.rb`                      | 9         |
| `spec/models/video_daily_by_country_spec.rb`           | 6         |
| `spec/models/video_daily_by_device_type_spec.rb`       | 6         |
| `spec/models/video_daily_by_operating_system_spec.rb`  | 6         |
| `spec/models/video_daily_by_traffic_source_spec.rb`    | 7         |
| `spec/models/video_daily_by_subscribed_status_spec.rb` | 6         |
| `spec/models/video_daily_by_age_group_gender_spec.rb`  | 7         |
| `spec/models/channel_window_summary_spec.rb`           | 11        |
| `spec/models/video_window_summary_spec.rb`             | 11        |
| `spec/models/top_videos_window_spec.rb`                | 10        |
| `spec/models/video_retention_spec.rb`                  | 8         |
| `spec/db/analytics_schema_spec.rb`                     | 6         |
| `spec/models/analytics_associations_spec.rb`           | 11        |
| **Total NEW test cases**                               | **113**   |

## Manual playbook (post-implementation)

1. **Drop and re-migrate.**
   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```
   Confirm migration succeeds; no errors about FK constraints or enum
   collisions.
2. **Inspect the schema.**
   ```bash
   bin/rails runner 'puts ActiveRecord::Base.connection.tables.grep(/^(channel_|video_|top_videos)/).sort'
   ```
   Expect exactly the 12 table names listed in this spec.
3. **Inspect the enum.**
   ```sql
   SELECT enumlabel FROM pg_enum WHERE enumtypid =
     (SELECT oid FROM pg_type WHERE typname = 'analytics_window');
   ```
   Expect: `7d`, `28d`, `90d`, `lifetime`.
4. **Inspect the indexes.**
   ```sql
   \d+ channel_daily
   \d+ video_daily
   \d+ video_daily_by_country
   \d+ channel_window_summary
   \d+ video_window_summary
   \d+ top_videos_window
   \d+ video_retention
   ```
   Confirm every unique composite index listed in this spec is present under the
   documented column tuple.
5. **Smoke a write via the Rails console.**
   ```ruby
   c = Channel.first
   ChannelDaily.create!(channel: c, date: Date.yesterday, views: 100)
   c.channel_dailies.count # => 1
   ```
   Confirm the row roundtrips. Repeat for
   `VideoDaily.create!(video: v, date: Date.yesterday, views: 50)`.
6. **Smoke an upsert-collision.**
   ```ruby
   ChannelDaily.create!(channel: c, date: Date.yesterday, views: 200)
   # ActiveRecord::RecordNotUnique
   ```
   The composite index fires. Cleanup: `ChannelDaily.delete_all`.
7. **Smoke a cascade.** Pick a freshly-created `Channel`; create a
   `ChannelDaily` row referencing it; `c.destroy`; assert
   `ChannelDaily.count == 0`.
8. **Run the full RSpec suite.**
   ```bash
   bundle exec rspec
   ```
   Confirm green.
9. **Run rubocop.**
   ```bash
   bundle exec rubocop
   ```
   Confirm clean (or no new violations).

## Cross-stack scope

| Surface           | Status                                                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Rails web app     | **In scope.** Schema only. No views, no controllers, no jobs.                                                                  |
| MCP rack app      | **Skipped.** No analytics tools yet (sync engine in spec 02 doesn't expose MCP either; analytics MCP tools are a future spec). |
| Doorkeeper        | **N/A.**                                                                                                                       |
| `pito` CLI (Rust) | **Skipped.** CLI parity for analytics is a deferred follow-up.                                                                 |
| Astro / website   | **N/A.**                                                                                                                       |

## Copy questions to escalate

This spec is schema-only — no user-facing copy. None.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Should `creator_content_type` get its own table?** Note 3 §V6 passes
   `dimensions=subscribedStatus,creatorContentType`. The architect splits this
   into one table for `subscribed_status` only, deferring
   `creator_content_type`. Recommendation: defer to a follow-up — a separate
   `video_daily_by_creator_content_type` table when the dashboard demonstrates
   the need. The Shorts vs VOD vs Live split is interesting but secondary to the
   headline subscribed/unsubscribed split. User confirms.
2. **Inflector pluralization — `channel_daily` or `channel_dailies`?** Rails'
   default inflector pluralizes `daily` to `dailies`; the model class is
   `ChannelDaily` and the table is `channel_dailies`. Note 3 uses the singular
   noun (`channel_daily(...)`) as the conceptual name. This spec writes the
   singular form in prose; the migration uses Rails' pluralized form for the
   actual table name. Recommendation: follow Rails convention
   (`channel_dailies`); update the spec's table headers to match the actual
   `db/schema.rb` output post-implementation. User confirms.
3. **Should monetization columns ship behind a Postgres-level CHECK constraint
   that requires them all to be NULL together (or all set together)?** Cleaner
   data shape. Cost: one CHECK per table. Recommendation: skip — the
   application-level feature flag in spec 02 is the gate; a CHECK gives nothing
   extra and complicates the `MONETIZATION_ENABLED=true` flip. User confirms.
4. **Should the `analytics_window` enum live in a dedicated migration that runs
   first?** Single migration is cleaner if the agent uses
   `execute("CREATE TYPE ...")` at the top. Postgres enums cannot be created
   mid-statement-batch in older Rails versions; agent confirms Rails 8.1
   supports it inline. If a snag surfaces, the agent splits into two migrations
   and surfaces. Recommendation: single migration; surface if blocked.
5. **Empty-state behavior for `dependent: :delete_all`.** When a `Channel` is
   destroyed, its `top_videos_window` rows reference the channel; the videos
   within those rows are NOT destroyed (the videos belong to that channel and
   ARE deleted by the existing `Channel has_many :videos, dependent: :destroy`
   cascade). The cascade order is: Channel destroy → top_videos_windows delete
   (FK on channel_id) → videos destroy → the videos' video_dailies /
   video_window_summaries / video_retentions delete (FK on video_id). Verify the
   order is well-defined; if Postgres' FK evaluation order differs, surface.
   Recommendation: ON DELETE CASCADE on every FK handles the order correctly
   without Rails-level intervention; the `dependent: :delete_all` Rails
   declarations are belt-and-suspenders.
6. **Active-video classification.** Note 3 §"Sync schedule" defines "active" as
   "uploaded in last 90 days OR > 100 views in last 7 days". This classification
   is a function of `videos` + `video_daily`; spec 02 (sync engine) implements
   the logic. NO column lands on `videos` for this — it is a derived predicate.
   Recommendation: confirm in spec 02; no schema change needed here. User
   confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

1. **`creator_content_type` slice.** Defer to a follow-up. Architect's
   recommended `video_daily_by_creator_content_type` table is NOT added in this
   spec.
2. **Inflector pluralization.** Follow Rails convention. Tables are
   `channel_dailies`, `video_dailies`, etc. Spec prose uses singular conceptual
   names; the migration uses Rails' pluralized form. Spec headers will be
   updated post-implementation to match the actual `db/schema.rb` output.
3. **CHECK constraint on monetization columns.** Skip. The app-level feature
   flag (Spec 02) is the gate.
4. **`analytics_window` enum migration shape.** Single migration. Use
   `execute("CREATE TYPE ...")` at the top. Implementation agent surfaces back
   if Rails 8.1 inline-enum support snags.
5. **Cascade order on Channel destroy.** `ON DELETE CASCADE` on every FK PLUS
   Rails-level `dependent: :delete_all` declarations as belt-and-suspenders.
6. **Active-video classification — schema column?** No column. Pure derived
   predicate, recomputed on each nightly orchestrator pass. Logic lives in
   Spec 02.

## Non-goals (explicit)

- **Sync engine.** Spec 02.
- **Dashboard views.** Spec 03.
- **MCP tools for analytics.** Future spec.
- **CLI parity for analytics.** Future follow-up.
- **Playlist analytics tables.** Per Q13; YouTube's playlist filter shape is in
  flight.
- **Cross-video local rollup tables.** Per Q14; computed at query time.
- **`creator_content_type` slice table.** Per Open question §1; deferred.
- **Migration rollback testing.** Per inherited posture from Phase 8.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`). Touches:

- `db/migrate/`, `db/schema.rb`
- `app/models/` (12 new files + 2 edits)
- `spec/factories/`, `spec/models/`, `spec/db/`

No `extras/cli/`, no `extras/website/`, no `app/controllers/`, no `app/views/`,
no `app/jobs/`, no `app/services/`, no `docs/`.

## Reviewer checkpoints (post-implementation)

1. `git grep 'tenant_id' db/migrate/<NN>_create_analytics_tables.rb` → zero
   matches.
2. `bin/rails db:drop db:create db:migrate db:seed` succeeds.
3. `bundle exec rspec spec/models/{channel_daily,video_daily,video_daily_by_*,channel_window_summary,video_window_summary,top_videos_window,video_retention}_spec.rb`
   → green.
4. `bundle exec rspec spec/db/analytics_schema_spec.rb` → green.
5. `bundle exec rspec spec/models/analytics_associations_spec.rb` → green.
6. `bundle exec rspec` → full suite green.
7. `bundle exec rubocop` → clean (or no new violations).
8. `bundle exec brakeman -q` → clean (or no new findings).
9. Manual playbook §1-§9.
10. Spec count delta logged in
    `docs/plans/beta/13-analytics-sync-engine/log.md`.
