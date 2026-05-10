# Phase 13 — Analytics Sync Engine + Tables + Dashboard

> **Status:** specs in flight as of 2026-05-10. No implementation yet. Phase
> folder created during the architect-spec dispatch that wrote the three specs
> under `specs/`.

## Plan

Per realignment work unit 5 + Mobile note 3
(`docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md`). Big work
unit; split into three specs landing in this order:

1. `specs/01-analytics-data-model.md` — schema for every analytics table
   enumerated in Note 3. Migrations only. No API client. No views.
2. `specs/02-analytics-sync-engine.md` — Sidekiq orchestrator + per-channel /
   per-video child jobs + `Youtube::AnalyticsClient` wrapper around
   `google-apis-youtube_analytics_v2` + retry/backoff + token-expiry + backfill
   mode + sidekiq-cron schedule. Builds on spec 01.
3. `specs/03-analytics-dashboard.md` — Hotwire / Chartkick views for every
   dashboard surface enumerated in Note 3. Builds on specs 01 + 02.

## Cross-references

- `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — source of
  truth for the data model + query shapes.
- `docs/realignment-2026-05-09.md` — work unit 5 ("Analytics sync engine
  - tables + dashboard"); marked "very big — split into sub-units."
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
  `tenant_id` on any analytics table.
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
  `YoutubeConnection` is the OAuth grant holder used by the sync engine.
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — Phase 8 prerequisite (analytics tables shed `tenant_id`).
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  — Phase 9 prerequisite (`YoutubeConnection` rename).
- `docs/plans/beta/12-video-schema-expansion/` — Phase 12 prerequisite (Video
  schema with `youtube_video_id`, `published_at`, `category_id`, `duration`,
  `tags`).

## Sessions

### 2026-05-10 — rails-impl: Spec 01 (analytics data model) lands

**Spec:** `specs/01-analytics-data-model.md`. **Outcome:** schema-only
implementation complete and green. Specs 02 (sync engine) and 03
(dashboard) deferred to a separate dispatch — see "Open follow-ups"
below.

**Note on commit lineage.** The Spec-01 files (12 models, 12 factories,
13 specs, 1 migration, the 2 has-many additions on Channel + Video)
landed in commit `6391f12 Fix Turbo Frame mismatch on bulk actions
across 5 list surfaces` on 2026-05-10 16:04 UTC+2 — bundled into a
larger commit that also covered Phase 14 Spec 02 (bundles) and other
phase-in-flight work. This session re-implemented the Spec-01 lane
end-to-end against a clean tree and confirmed every file matches main
byte-for-byte (`git diff HEAD app/models/channel_daily.rb …` empty for
every Spec-01 file). The implementation contract is unchanged from
what `main` already shipped; this session's net diff is the log entry
below.

**Files added (analytics models, schema, factories, specs):**

- `db/migrate/20260510155554_create_analytics_tables.rb` — single
  migration creating the `analytics_window` Postgres enum + 12
  analytics tables (`channel_dailies`, `video_dailies`, six sliced
  `video_daily_by_*` tables, `channel_window_summaries`,
  `video_window_summaries`, `top_videos_windows`, `video_retentions`).
- `app/models/channel_daily.rb`, `app/models/video_daily.rb`, six
  `app/models/video_daily_by_*.rb` files,
  `app/models/channel_window_summary.rb`,
  `app/models/video_window_summary.rb`,
  `app/models/top_videos_window.rb`, `app/models/video_retention.rb`
  — 12 new model files.
- `spec/factories/{channel_dailies,video_dailies,video_daily_by_countries,video_daily_by_device_types,video_daily_by_operating_systems,video_daily_by_traffic_sources,video_daily_by_subscribed_statuses,video_daily_by_age_group_genders,channel_window_summaries,video_window_summaries,top_videos_windows,video_retentions}.rb`
  — 12 new factory files.
- `spec/models/{channel_daily,video_daily,video_daily_by_country,video_daily_by_device_type,video_daily_by_operating_system,video_daily_by_traffic_source,video_daily_by_subscribed_status,video_daily_by_age_group_gender,channel_window_summary,video_window_summary,top_videos_window,video_retention,analytics_associations}_spec.rb`
  — 13 model specs.
- `spec/db/analytics_schema_spec.rb` — schema integrity spec
  (Postgres enum existence, UNIQUE composite indexes on natural keys,
  ON DELETE CASCADE on FKs to `channels` / `videos`, no `tenant_id`
  columns, ratio-column scale `numeric(10, 6)`, duration-column scale
  `numeric(10, 2)`).

**Files edited:**

- `app/models/channel.rb` — added `has_many :channel_dailies`,
  `:channel_window_summaries`, `:top_videos_windows`, all
  `dependent: :delete_all`.
- `app/models/video.rb` — added `has_many` for the eight per-video
  analytics relations and `:video_window_summaries`,
  `:video_retentions`, all `dependent: :delete_all`.
- `db/schema.rb` — auto-regenerated to include the 12 new tables and
  the `analytics_window` enum.

**Architectural decisions honored verbatim from the spec's Master agent
decisions block:**

1. `creator_content_type` slice — deferred (not added).
2. Tables use Rails-pluralized inflector form (`channel_dailies`,
   `video_dailies`, etc.).
3. No CHECK constraint on monetization columns (app-level
   `MONETIZATION_ENABLED` flag is the gate; Spec 02 owns).
4. Single migration with `execute("CREATE TYPE analytics_window AS
   ENUM (...);")` at the top — Rails 8.1 captured the enum in
   `schema.rb` cleanly via `create_enum`.
5. Cascade order: ON DELETE CASCADE on every FK + Rails-level
   `dependent: :delete_all` declarations as belt-and-suspenders.
6. Active-video classification: no schema column; pure derived
   predicate (Spec 02 owns).

**Notable implementation choices:**

- `*_window_summary` and `top_videos_windows` use the
  `analytics_window` Postgres enum directly via `t.column :window,
  :analytics_window`. Rails' built-in `enum :window` macro is NOT
  used because that macro expects an integer column; the value is
  stored as the string itself. Rails-side validation of the four
  values uses `validates :window, inclusion: { in: WINDOWS }`. An
  out-of-range value (e.g., `"bogus"`) is rejected by Postgres at
  the wire level — `ActiveRecord::StatementInvalid` is raised before
  the row reaches the table. Specs assert this.
- `video_retentions` omits `created_at` / `updated_at` per spec; the
  model sets `self.record_timestamps = false` and a
  `before_validation :stamp_computed_at` callback lazily populates
  `computed_at` if the caller hasn't already.
- `top_videos_windows` rank-uniqueness validation is
  custom-implemented because Rails' built-in `validates :rank,
  uniqueness: { scope: %i[channel_id window] }` would shadow the
  primary natural-key uniqueness on `(channel_id, window, video_id)`.
  Two named uniqueness validations let the model's `valid?` method
  surface either violation correctly.
- The sliced daily tables' UNIQUE indexes were given short names
  (`idx_video_daily_by_country_uniq`, etc.) because the auto-generated
  names collide with Postgres' 63-character limit.

**Test sweep:**

- Spec 01 enumerated 113 test cases across 14 spec files. The
  implementation landed 118 atomic test cases across 14 spec files
  (the small surplus reflects natural test grouping — a couple of
  enumerated cases expanded into 2 atomic `it` blocks). All 118 pass.
- Full RSpec suite: 3158 examples, 7 failures, 1 pending. The 7
  failures are pre-existing on `main` (bundles, games, calendar,
  composites — unrelated phase-in-flight work). No analytics spec
  fails; no Channel / Video spec broken by the additive `has_many`
  declarations.

**Quality gates:**

- `bundle exec rspec spec/models/{channel_daily,video_daily,…} spec/db/analytics_schema_spec.rb spec/models/analytics_associations_spec.rb`
  → 118 examples, 0 failures.
- `bundle exec rubocop` over the 41 changed/new files → 41 files
  inspected, no offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

**Reviewer checkpoints (from Spec 01) covered:**

1. ✅ `git grep 'tenant_id' db/migrate/20260510155554_create_analytics_tables.rb`
   → zero matches.
2. ✅ `bin/rails db:migrate` succeeds (already exercised in dev + test).
3. ✅ Model unit specs green.
4. ✅ `spec/db/analytics_schema_spec.rb` green.
5. ✅ `spec/models/analytics_associations_spec.rb` green.
6. ✅ Full RSpec suite no analytics-related regressions.
7. ✅ Rubocop clean.
8. ✅ Brakeman clean.
9. ⏳ Manual playbook §1-§9 — pending user validation.

**Open follow-ups for next dispatch:**

- **Spec 02 (analytics-sync-engine.md) — DEFERRED.** ~139 enumerated
  test cases. Touches `app/jobs/`, `app/services/youtube/`,
  `app/services/backfill/`, `config/sidekiq*.yml`, `db/seeds.rb`,
  plus the ~10 spec files. Note: the existing
  `app/models/youtube_api_call.rb` has `CLIENT_KINDS = %w[oauth
  public]` and a fixed `OUTCOMES` whitelist — Spec 02 must extend
  these (`analytics_v2` kind, `succeeded` / `auth_failed` /
  `rate_limited` / `failed` outcomes). The existing fixture also
  uses `success` rather than `succeeded`; reconcile with the
  master-agent copy decision (`youtube_analytics.query.succeeded`)
  during the Spec 02 dispatch.
- **Spec 03 (analytics-dashboard.md) — DEFERRED.** ~118 enumerated
  test cases. Routes, controllers, views, helpers, decorators,
  Stimulus controllers. Depends on Spec 02 having populated tables
  for system-spec coverage.
- **Channel-level slice tables (C4 / C5).** Per spec 02 master-agent
  decision, deferred entirely; query-time rollup in Spec 03.
- **Documentation updates.** `docs/architecture.md` and `CLAUDE.md`
  edits called out by Spec 01's "Files touched → Documentation"
  block — dispatched separately to docs-keeper, not part of this
  rails-impl session.

## 2026-05-10 — Spec 02 implementation (rails-impl agent)

### Context

Spec 02 (analytics sync engine) implemented end to end against
`docs/plans/beta/13-analytics-sync-engine/specs/02-analytics-sync-engine.md`.
Builds on Spec 01's twelve analytics tables (already in main as of
`6391f12`) and consumes `YoutubeConnection`, the existing
`YoutubeApiCall` audit row, and the
`google-apis-youtube_analytics_v2` gem. All twelve master-agent
decisions (5 copy + 8 open question) honored verbatim.

### Files (production)

- `app/services/youtube/oauth_refresh.rb` — shared OAuth-token
  freshness module (extracted per master-agent decision 7). Mixed
  into `Youtube::AnalyticsClient`; `Youtube::Client` continues to
  use its in-class implementation (re-extraction is a follow-up).
- `app/services/youtube/analytics_query_builder.rb` — pure-function
  builder for the 14 query shapes from Note 3 (C1, C2, C3, C4, C5,
  V1, V2, V3, V4-device, V4-os, V5, V6, V7, V8). Enforces
  mutual-exclusion guards: `liveOrOnDemand` ↔
  `averageViewPercentage`, `day` ↔ `month`, V7's single-video-filter
  rule. Monetization-enabled mode appends revenue metrics; default
  mode omits them. `WINDOWS = %w[7d 28d 90d lifetime]`.
- `app/services/youtube/analytics_client.rb` —
  `Youtube::AnalyticsClient` wrapping
  `Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService`. Twelve
  public methods: `channel_daily`, `channel_window_summary`,
  `top_videos`, `channel_geography` (NotImplementedError stub),
  `channel_demographics` (NotImplementedError stub), `video_daily`,
  `video_window_summary`, `video_by_country`, `video_by_device_type`,
  `video_by_operating_system`, `video_by_traffic_source`,
  `video_by_subscribed_status`, `video_demographics`,
  `video_retention`, plus `today_pt` and `monetization_enabled?`
  helpers. Translates Google API errors into typed exceptions
  (`AuthError`, `RateLimitError`, `TransientError`,
  `PermanentError`). Writes a `youtube_api_calls` audit row per
  call. Defense-in-depth assertions on channel/video ↔ connection
  membership; YouTube channel-id is parsed from `channel_url` since
  the `channels` table doesn't (yet) carry a dedicated column.
- `app/services/youtube/active_video_classifier.rb` — pure module:
  `active?(video)` and `active_for(connection)`. Inclusive 90-day
  boundary, strict `> 100` views threshold per master-agent decision
  6.
- `app/services/backfill/analytics_range.rb` — out-of-band wrapper
  enqueueing `ChannelAnalyticsSync` and `VideoAnalyticsSync`.
  Returns the count of enqueued jobs. Refuses `needs_reauth`
  connections; refuses inverted date ranges.
- `app/jobs/youtube_analytics_sync.rb` — top-level orchestrator.
  Iterates `YoutubeConnection.active`, dispatches
  `ChannelAnalyticsSync` per channel + `VideoAnalyticsSync` per
  video. `retention_only: true` mode dispatches only
  `VideoRetentionSync`.
- `app/jobs/video_retention_sync_orchestrator.rb` — thin wrapper
  the weekly cron entry fires; delegates to
  `YoutubeAnalyticsSync.new.perform(retention_only: true)`.
- `app/jobs/channel_analytics_sync.rb` — per-channel job. C1
  (`channel_daily`, refresh last 3 days), C2 (`channel_window_summary`
  for each of `7d`/`28d`/`90d`/`lifetime`), C3 (`top_videos`,
  delete-then-insert by `(channel_id, window)` so leaderboard
  membership shrinkage isn't sticky). Idempotent via composite-key
  `upsert_all`. Bails early when the connection's `needs_reauth`
  flips during the run.
- `app/jobs/video_analytics_sync.rb` — per-video job. Active videos
  run V1, V2 (×4 windows), V3, V4-device, V4-os, V5, V6, V8.
  Inactive videos run V1 only. Same idempotency pattern.
- `app/jobs/video_retention_sync.rb` — V7 retention curve. Per
  the table's "recomputed-in-place" contract, the job deletes the
  existing rows for the video and re-inserts, so a falling-off
  bucket isn't sticky.
- `app/models/youtube_connection.rb` — `scope :active` added.
- `app/models/youtube_api_call.rb` — extended `CLIENT_KINDS` with
  `analytics_v2`; extended `OUTCOMES` with `succeeded` and `failed`
  to honor the master-agent copy decisions while preserving the
  Phase 7 `success` outcome the OAuth client uses. Added named
  constants `KIND_DATA_V3`, `KIND_PUBLIC`, `KIND_ANALYTICS_V2`.
- `config/sidekiq.yml` — added `analytics` queue.
- `config/sidekiq_cron.yml` — added `youtube_analytics_sync_nightly`
  (`0 4 * * *`) and `youtube_analytics_retention_weekly`
  (`0 5 * * 1`), both on the `analytics` queue.
- `db/seeds.rb` — idempotent insert seeds `monetization_enabled =
  "no"` (master-agent decision 8: AppSetting-backed flag, not a
  credential). The yes/no-string convention crosses the AppSetting
  key/value boundary as required.
- `lib/tasks/analytics.rake` — `analytics:backfill[connection_id,
  from, to]` rake task wrapping `Backfill::AnalyticsRange.call`.

### Files (specs)

- `spec/services/youtube/analytics_query_builder_spec.rb` — 40
  cases (vs spec's enumerated 38; small surplus from natural
  grouping). Asserts every metric set, dimension, filter, sort,
  max_results cap, the 4-window enum, mutual-exclusion guards.
- `spec/services/youtube/analytics_client_spec.rb` — 34 cases.
  Construction; happy path for each public method; sad-path for
  401 / 429 / 5xx / 4xx-other / network timeout / malformed
  response; PT day handling; token refresh on expired
  connection; audit-row content (kind, outcome, payload-with-
  dimensions/metrics, latency).
- `spec/services/youtube/active_video_classifier_spec.rb` — 8
  cases. Boundary tests for both rules.
- `spec/services/backfill/analytics_range_spec.rb` — 7 cases.
- `spec/services/youtube/analytics_client_flaw_spec.rb` — 4 cases
  (smuggle / source-of-truth / cross-connection rejection).
- `spec/jobs/youtube_analytics_sync_spec.rb` — 8 cases.
- `spec/jobs/channel_analytics_sync_spec.rb` — 10 cases.
- `spec/jobs/video_analytics_sync_spec.rb` — 17 cases.
- `spec/jobs/video_retention_sync_spec.rb` — 5 cases.
- `spec/jobs/concurrent_sync_spec.rb` — 2 cases.
- `spec/integration/analytics_full_sync_spec.rb` — 7 cases. Full
  Sidekiq inline-mode walk through the orchestrator → child-job
  chain with a stubbed `Youtube::AnalyticsClient`.

Total new test cases: **142** (vs the spec's enumerated 139). The
small surplus is natural variance — a couple of enumerated cases
expanded into 2 atomic `it` blocks for readability.

### Locked decisions honored verbatim

- Audit-log keys: `youtube_analytics.query.{succeeded,
  rate_limited, auth_failed, failed}` — defined as constants on
  `Youtube::AnalyticsClient`.
- Logger templates:
  `[analytics-sync] starting nightly run; <N> active connections`,
  `[analytics-sync] complete; <duration>s`,
  `[analytics-sync] connection <id> failed auth; marking
  needs_reauth`.
- Sidekiq cron names: `youtube_analytics_sync_nightly` +
  `youtube_analytics_retention_weekly`.
- `analytics:backfill[connection_id, from, to]` rake.
- C4/C5 channel-level slices: `NotImplementedError` stubs.
- Active-video classification: pure function, no schema column.
- No app-side throttle on `Backfill::AnalyticsRange`.
- Logger: `info` for orchestrator, `warn` for auth failures.
  Per-API-call logs land at `debug` only via the audit row's
  `error_message` payload field (not via `Rails.logger.debug`).
- `analytics` queue in `config/sidekiq.yml`.
- 90-day inclusive boundary; strict `> 100` view threshold.
- `Youtube::OauthRefresh` shared module included by
  `Youtube::AnalyticsClient`. Reusing it from the existing
  `Youtube::Client` is queued as a follow-up (re-extraction would
  touch every Phase 7 client spec; out of this dispatch's scope).
- `monetization_enabled` AppSetting seeded via `db/seeds.rb`
  idempotent insert with default `"no"`.

### Quality gates

- `bundle exec rspec` over the 11 new spec files → 142 examples,
  0 failures.
- Full suite: 3532 examples, 2 pre-existing failures (calendar
  month + composites — both pre-existed at `cd2b482`; unrelated
  to analytics).
- `bundle exec rubocop` over the 25 changed/new files → no
  offenses.
- `bundle exec brakeman -q -w2` → 0 warnings.

### Notes & follow-ups

- **YouTube channel-id derivation.** `Channel` doesn't yet carry
  a `youtube_channel_id` column (only `channel_url`). The client
  parses the ID from the URL's `/channel/UC<22-chars>` suffix.
  Once a Phase 11/12 surface lands a dedicated column, the parse
  step folds into a model accessor.
- **`Youtube::Client` OAuth refresh.** Re-extracting the existing
  Phase 7 client to use `Youtube::OauthRefresh` is queued as a
  follow-up. The existing `ensure_token_fresh!` /
  `build_oauth_credentials` private methods stay in
  `Youtube::Client`; the new `Youtube::AnalyticsClient` uses the
  module. Both share `Youtube::TokenRefresher`.
- **Audit-row payload field.** The analytics audit row stores the
  query label + dimensions + metrics + filters + start_date +
  end_date as a JSON-encoded blob in the existing
  `error_message` text column. No migration; no schema change.
  When a failure occurs, the `error` key joins the same JSON
  payload. Spec 03 / a future audit-viewer can decode it.
- **`docs/architecture.md` + `CLAUDE.md`.** Note the analytics
  sync engine + the two cron entries. Out of this dispatch's
  scope; queued for the docs-keeper agent.
- **Spec 03 (analytics-dashboard.md) — DEFERRED** to a separate
  dispatch (~118 enumerated test cases; routes, controllers,
  views, helpers, decorators, Stimulus controllers).
