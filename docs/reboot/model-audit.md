# Model & Schema Audit — Beta Reboot P7 (LOCKED)

> Reference: `docs/plan-beta-reboot.md` phase P7.
>
> **Status**: LOCKED via user sign-off (T7.2 manual review complete).
>
> The beta baseline migration (T7.8) covers the 15 KEEP entries below.
> DROP entries get their model files deleted (T7.3–T7.6). No DEFER tier
> in this audit — anything not in the 15-model baseline is dropped now;
> the user will rebuild later phases from scratch when scope clarifies.

---

## The 15-model baseline

### Domain (10 models)

| # | Model | Notes |
|---|---|---|
| 1 | **Channel** | YouTube channel; no `star`, no `summary_embedding` |
| 2 | **Video** | YouTube video; has `summary_embedding` (Voyage) |
| 3 | **Game** | IGDB game; 3 ratings + 3 TTBs + `platforms` text[] + `summary_embedding` |
| 4 | **Genre** | IGDB ref table |
| 5 | **GameGenre** | join, with `position` for picker |
| 6 | **Company** | IGDB ref table (developer / publisher) |
| 7 | **GameDeveloper** | join |
| 8 | **GamePublisher** | join |
| 9 | **GamePlatformOwnership** | lean: `(game_id, platform_token)` only |
| 10 | **Footage** | local clips; no `recorded_at` |
| 11 | **VideoGameLink** | video ↔ game |

### Auth + config (4 models)

| # | Model | Notes |
|---|---|---|
| 12 | **YoutubeConnection** | OAuth2 grant |
| 13 | **Session** | TOTP session row |
| 14 | **TotpBackupCode** | backup codes |
| 15 | **AppSetting** | singleton + key/value, TOTP fields, pre-allocated API key columns |

---

## Column specs (locked)

### 1. Channel — `channels`

- `youtube_channel_id` (string, unique) — the `UC...` id (no full URL stored)
- `youtube_connection_id` (FK, nullable)
- `title`, `handle`, `description`
- `avatar_url`, `banner_url`
- `subscriber_count` (bigint), `view_count` (bigint), `video_count` (integer)
- `last_synced_at` (timestamptz)
- `created_at`, `updated_at`

Dropped vs old: `star`, `country`, `default_language`, `keywords`, `watermark_*`,
`links`, `title_changed_at`, `handle_changed_at`, `published_at`, `hidden_subscriber_count`,
`summary_embedding` (no Voyage indexing for Channel — derived from Videos at query time).

### 2. Video — `videos`

- `youtube_video_id` (string, unique), `channel_id` (FK)
- `title`, `description`, `tags` (text[])
- `category_id` (string)
- `privacy_status` (integer enum: `private`, `public`, `unlisted`)
- `publish_at` (timestamptz), `published_at` (timestamptz)
- `thumbnail_url` (string)
- `view_count` (bigint), `like_count` (bigint), `comment_count` (bigint)
- `duration_seconds` (integer)
- `last_synced_at` (timestamptz)
- `summary_embedding` (vector 1024)
- `created_at`, `updated_at`

Dropped vs old: pre_publish_* booleans, `last_sync_error`, `etag`, `embeddable`,
`public_stats_viewable`, `made_for_kids_effective`, `last_diff_checked_at`,
`contains_synthetic_media`, `self_declared_made_for_kids`, `star`, thumbnail Active Storage attachment.

### 3. Game — `games`

- `igdb_id` (bigint, unique partial)
- `igdb_slug` (string, unique partial)
- `igdb_checksum` (string)
- `title` (string, default `"Untitled game"`)
- `summary` (text)
- `cover_image_id` (string) — IGDB CDN token; local variant at `public/covers/games/<id>/master.jpg`
- `platforms` (text[]) — 3-token canonical set: `["ps", "switch", "steam"]` subset
- `release_date` (date), `release_year` (integer), `release_precision` (integer enum: `day`, `month`, `quarter`, `year`, `tba`)
- **3 ratings + counts**: `igdb_rating` (decimal 5,2), `igdb_rating_count` (integer), `total_rating`, `total_rating_count`, `aggregated_rating`, `aggregated_rating_count`
- **3 TTBs**: `ttb_main_seconds` (integer), `ttb_extras_seconds`, `ttb_completionist_seconds`
- `external_steam_app_id` (string)
- `alternative_names` (text[], default `{}`)
- `primary_genre_id` (FK to genres, nullable) — picked by `Pito::Igdb::PrimaryGenrePicker`
- `igdb_synced_at` (timestamptz)
- `played_at` (date) — local
- `notes` (text) — local
- `summary_embedding` (vector 1024)
- `created_at`, `updated_at`

### 4. Genre — `genres`

- `igdb_id` (bigint, unique)
- `name` (string)
- `slug` (string, nullable — no FriendlyId)
- `created_at`, `updated_at`

### 5. GameGenre — `game_genres`

- `game_id`, `genre_id`
- `position` (integer, nullable)
- `created_at`, `updated_at`
- Unique: `(game_id, genre_id)`

### 6. Company — `companies`

- `igdb_id` (bigint, unique), `name`, `slug` (nullable)
- `created_at`, `updated_at`

### 7. GameDeveloper — `game_developers`

- `game_id`, `company_id`
- `created_at`, `updated_at`
- Unique: `(game_id, company_id)`

### 8. GamePublisher — `game_publishers`

- `game_id`, `company_id`
- `created_at`, `updated_at`
- Unique: `(game_id, company_id)`

### 9. GamePlatformOwnership — `game_platform_ownerships` (NEW)

- `game_id` (FK, not null)
- `platform_token` (text, not null) — CHECK `platform_token IN ('ps', 'switch', 'steam')`
- `created_at`, `updated_at`
- Unique: `(game_id, platform_token)`

Distinction recap:
- `Game.platforms` text[] = where the game ships (IGDB sync-driven, read-only)
- `GamePlatformOwnership` rows = where I own it (user-driven, write-driven)

### 10. Footage — `footages`

- `game_id` (FK, **nullable** — un-attached footage is allowed)
- `filename`, `local_path` (string, unique)
- `duration_seconds` (integer)
- `resolution` (string, e.g., `"3840x2160"`)
- `aspect_ratio` (string)
- `fps` (decimal 6,3)
- `codec` (string)
- `bit_depth` (integer, default 8) — 8/10/12 implies SDR vs HDR
- `color_profile` (string, e.g., `"BT.709"` / `"BT.2020"`)
- `audio_track_count` (integer) — `nil` when ffprobe didn't return track info
- `audio_track_names` (text[], default `{}`) — populated when ffprobe surfaces per-track
  titles (OBS records named tracks); empty array when nameless or single-track.
  Useful **only** in concert with `audio_track_count` — the array length should
  equal the count when names are available.
- `has_commentary_track` (boolean, default false)
- `created_at`, `updated_at`

Explicitly dropped: `recorded_at` (unreliable: OBS .mkv doesn't embed it, filesystem
timestamps drift on drive moves). `nas_path` (single-path baseline). `description`,
`frames_extracted_at`, `filesize_bytes` (defer).

### 11. VideoGameLink — `video_game_links`

- `video_id` (FK), `game_id` (FK)
- `created_at`, `updated_at`
- Unique: `(video_id, game_id)`

Dropped: `link_type`, `is_primary`, `created_by_user_id`.

### 12. YoutubeConnection — `youtube_connections`

- `google_subject_id` (string, unique)
- `email` (string)
- `access_token` (text, AR-encrypted)
- `refresh_token` (text, AR-encrypted)
- `scopes` (jsonb, default `[]`)
- `expires_at` (timestamptz)
- `last_authorized_at` (timestamptz)
- `needs_reauth` (boolean, default false)
- `created_at`, `updated_at`

### 13. Session — `sessions`

- `token_digest` (string, unique)
- `state` (integer enum: `active`, `expired`, `revoked`)
- `revoked_at` (timestamptz, nullable)
- `last_activity_at` (timestamptz)
- `ip` (inet)
- `user_agent` (text)
- `device` (string, derived), `browser` (string, derived)
- `created_at`, `updated_at`

### 14. TotpBackupCode — `totp_backup_codes`

- `code_digest` (string)
- `used_at` (timestamptz, nullable)
- `created_at`, `updated_at`

### 15. AppSetting — `app_settings`

- `key` (string, unique, nullable for the singleton row's `"__singleton__"` key)
- `value` (text, AR-encrypted, nullable on the singleton row)
- **Singleton row TOTP fields**: `totp_seed_encrypted` (text, AR-encrypted),
  `totp_enabled_at` (timestamptz), `totp_disabled_at` (timestamptz),
  `totp_last_used_step` (integer)
- **Singleton row pre-allocated API key columns (encrypted, nullable)**:
  - `google_oauth_client_id` (text, AR-encrypted)
  - `google_oauth_client_secret` (text, AR-encrypted)
  - `voyage_api_key` (text, AR-encrypted)
- `created_at`, `updated_at`

Read-pattern for the new API keys: `AppSetting.google_oauth_client_id ||
Rails.application.credentials.dig(:google, :client_id)`. Lets keys move out of
credentials gradually without a forced migration.

---

## Models to DROP (delete the file in T7.3)

| Model | File |
|---|---|
| ApiToken | `app/models/api_token.rb` |
| BulkOperation | `app/models/bulk_operation.rb` |
| BulkOperationItem | `app/models/bulk_operation_item.rb` |
| CalendarEntry | `app/models/calendar_entry.rb` |
| ChannelChangeLog | `app/models/channel_change_log.rb` |
| ChannelDaily | `app/models/channel_daily.rb` |
| ChannelWindowSummary | `app/models/channel_window_summary.rb` |
| ImportJob | `app/models/import_job.rb` |
| MilestoneRule | `app/models/milestone_rule.rb` |
| Notification | `app/models/notification.rb` |
| NotificationDeliveryChannel | `app/models/notification_delivery_channel.rb` |
| Playlist | `app/models/playlist.rb` |
| PlaylistVideo | `app/models/playlist_video.rb` |
| RejectedVideoImport | `app/models/rejected_video_import.rb` |
| SavedView | `app/models/saved_view.rb` |
| TopVideosWindow | `app/models/top_videos_window.rb` |
| VideoChangeLog | `app/models/video_change_log.rb` |
| VideoChapter | `app/models/video_chapter.rb` |
| VideoDaily | `app/models/video_daily.rb` |
| VideoDailyByAgeGroupGender | `app/models/video_daily_by_age_group_gender.rb` |
| VideoDailyByCountry | `app/models/video_daily_by_country.rb` |
| VideoDailyByDeviceType | `app/models/video_daily_by_device_type.rb` |
| VideoDailyByOperatingSystem | `app/models/video_daily_by_operating_system.rb` |
| VideoDailyBySubscribedStatus | `app/models/video_daily_by_subscribed_status.rb` |
| VideoDailyByTrafficSource | `app/models/video_daily_by_traffic_source.rb` |
| VideoDiff | `app/models/video_diff.rb` |
| VideoEndScreen | `app/models/video_end_screen.rb` |
| VideoRetention | `app/models/video_retention.rb` |
| VideoStat | `app/models/video_stat.rb` |
| VideoUpload | `app/models/video_upload.rb` |
| VideoViewerTimeBucket | `app/models/video_viewer_time_bucket.rb` |
| VideoWindowSummary | `app/models/video_window_summary.rb` |
| YoutubeApiCall | `app/models/youtube_api_call.rb` |

**33 files deleted** in T7.3.

### Models to NEW-WRITE in T7.8 (don't exist yet)

- `app/models/game_platform_ownership.rb` — needs to be created when the migration ships.

### Models to SIMPLIFY in T7.8 (kept files; need column references updated)

These survive but their current Ruby has callbacks / validations / scopes pointing
at dropped columns and dropped associations. T7.8 trims each to match the locked
column spec above:

- `app/models/channel.rb` — drop `star`, watermark, links, change-log assoc, calendar derivation, etc.
- `app/models/video.rb` — drop pre_publish_*, diff/changelog assocs, calendar derivation, thumbnail attachment, viewer-time buckets, retention, dailies, etc.
- `app/models/game.rb` — drop calendar derivation, cover_art Active Storage, edition/version_parent system, etc.
- `app/models/genre.rb` — strip to bare bones
- `app/models/game_genre.rb` — drop primary-genre recompute callbacks (rebuild via picker service)
- `app/models/company.rb` — already minimal
- `app/models/game_developer.rb` — already minimal
- `app/models/game_publisher.rb` — already minimal
- `app/models/footage.rb` — drop friendly-id finder, drop platform-allowlist validator, drop `nas_path`, drop `recorded_at`
- `app/models/video_game_link.rb` — drop `link_type`, drop `is_primary`, drop hooks
- `app/models/youtube_connection.rb` — strip per spec
- `app/models/session.rb` — drop cable broadcast hook, keep activity tracking
- `app/models/totp_backup_code.rb` — already minimal
- `app/models/app_setting.rb` — keep the singleton pattern + TOTP helpers; drop sync-state methods, reindex lock methods, home rows, notification toggle helpers; add API-key accessors

---

## Concerns (T7.4)

| File | Verdict |
|---|---|
| `app/models/concerns/calendar_derivable.rb` | **drop** — CalendarEntry is gone |
| `app/models/concerns/searchable.rb` | **drop** — Meilisearch was removed in P6 |
| `app/models/concerns/timezoned.rb` | **drop** — User model was dropped pre-reboot |

---

## Decorators (T7.5)

All decorators are dropped. The web terminal UI uses ViewComponents (P10), not decorators.

| File | Verdict |
|---|---|
| `app/decorators/analytics/` (dir) | **drop** |
| `app/decorators/application_decorator.rb` | **drop** |
| `app/decorators/calendar_entry_decorator.rb` | **drop** |
| `app/decorators/channel_decorator.rb` | **drop** |
| `app/decorators/game_decorator.rb` | **drop** |
| `app/decorators/notification_decorator.rb` | **drop** |
| `app/decorators/video_decorator.rb` | **drop** |
| `app/decorators/video_stat_decorator.rb` | **drop** |

The entire `app/decorators/` directory is removed.

---

## Policies (T7.6)

All policies dropped. Single-user app — no policies for v1.

| File | Verdict |
|---|---|
| `app/policies/video_policy.rb` | **drop** |

The entire `app/policies/` directory is removed.

---

## Tables that go to the baseline migration (T7.8)

Beyond the 15 domain tables, the baseline migration also creates / enables:

### Extensions
- `pgcrypto` (existing, keep)
- `citext` (existing — saved_views was dropped, but harmless to keep)
- `vector` (pgvector, keep)
- `pg_trgm` — **enable** (P8 FTS will use trigram indexes)
- `unaccent` — **enable** (P8 FTS for accent-insensitive search)

### Enums (Postgres-side)
- `release_precision_enum` — `day`, `month`, `quarter`, `year`, `tba` (or use integer enum at AR layer — TBD in T7.8)
- `privacy_status_enum` — `private`, `public`, `unlisted` (or integer enum)
- `session_state_enum` — `active`, `expired`, `revoked` (or integer enum)

Implementation note for T7.8: integer-backed enums on the AR side are simpler and
match existing Rails conventions; we'll go with integers unless there's a clear
reason to use PG enums.

### Vectors (1024 dim, HNSW indexes)
- `games.summary_embedding`
- `videos.summary_embedding`
- (no `channels.summary_embedding` — derived from Videos at query time)

### Vector indexes (HNSW, cosine)
- `index_games_on_summary_embedding_hnsw` — `using: :hnsw, opclass: :vector_cosine_ops`
- `index_videos_on_summary_embedding_hnsw` — same

### ActiveStorage tables
**Dropped from baseline.** Will be added when Video.thumbnail upload arrives in a later phase.

### SolidQueue / SolidCache / SolidCable tables
**Kept** (already in schema via P4/P5 installers). The baseline migration leaves
these alone — they're managed by their respective install generators.

---

## Services / value objects not in schema (memory aid for future phases)

These get rebuilt later but are tracked here so they don't get lost:

- `Pito::Igdb::Client` + `Pito::Igdb::GameMapper`
- `Pito::Igdb::MainGameFilter` — strips deluxe / definitive / expansion / platform edition variants
- `Pito::Igdb::PlatformMapper` — IGDB platform → `ps` / `switch` / `steam` token
- `Pito::Igdb::PrimaryGenrePicker` — N → 1 genre picker
- `Pito::Game::Cover::Normalizer` — IGDB CDN → libvips → `public/covers/games/<id>/master.jpg`
- `Pito::Voyage::Indexer::Game`, `Pito::Voyage::Indexer::Video`
- `Pito::Game::RatingHeatmap` value object → `RatingHeatmapComponent` (P10)
- `Pito::Game::TimeToBeat` value object → `TimeToBeatComponent` (P10)
- `Pito::Game::Recommendation::ByGame` (game ↔ game via pgvector)
- `Pito::Game::Recommendation::ByChannel` (game ↔ channel via Video aggregation)
- `Pito::Auth::Totp` (P14)
- `Pito::Notifications::*` — later phase
- `Pito::Calendar::*` — later phase

---

## Sign-off

User locked this audit on the conversation thread (2026-05-27).
T7.2 marked done; proceeding with T7.3 onward.
