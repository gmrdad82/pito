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
implementation complete and green. Specs 02 (sync engine) and 03 (dashboard)
deferred to a separate dispatch — see "Open follow-ups" below.

**Note on commit lineage.** The Spec-01 files (12 models, 12 factories, 13
specs, 1 migration, the 2 has-many additions on Channel + Video) landed in
commit `6391f12 Fix Turbo Frame mismatch on bulk actions across 5 list surfaces`
on 2026-05-10 16:04 UTC+2 — bundled into a larger commit that also covered Phase
14 Spec 02 (bundles) and other phase-in-flight work. This session re-implemented
the Spec-01 lane end-to-end against a clean tree and confirmed every file
matches main byte-for-byte (`git diff HEAD app/models/channel_daily.rb …` empty
for every Spec-01 file). The implementation contract is unchanged from what
`main` already shipped; this session's net diff is the log entry below.

**Files added (analytics models, schema, factories, specs):**

- `db/migrate/20260510155554_create_analytics_tables.rb` — single migration
  creating the `analytics_window` Postgres enum + 12 analytics tables
  (`channel_dailies`, `video_dailies`, six sliced `video_daily_by_*` tables,
  `channel_window_summaries`, `video_window_summaries`, `top_videos_windows`,
  `video_retentions`).
- `app/models/channel_daily.rb`, `app/models/video_daily.rb`, six
  `app/models/video_daily_by_*.rb` files,
  `app/models/channel_window_summary.rb`, `app/models/video_window_summary.rb`,
  `app/models/top_videos_window.rb`, `app/models/video_retention.rb` — 12 new
  model files.
- `spec/factories/{channel_dailies,video_dailies,video_daily_by_countries,video_daily_by_device_types,video_daily_by_operating_systems,video_daily_by_traffic_sources,video_daily_by_subscribed_statuses,video_daily_by_age_group_genders,channel_window_summaries,video_window_summaries,top_videos_windows,video_retentions}.rb`
  — 12 new factory files.
- `spec/models/{channel_daily,video_daily,video_daily_by_country,video_daily_by_device_type,video_daily_by_operating_system,video_daily_by_traffic_source,video_daily_by_subscribed_status,video_daily_by_age_group_gender,channel_window_summary,video_window_summary,top_videos_window,video_retention,analytics_associations}_spec.rb`
  — 13 model specs.
- `spec/db/analytics_schema_spec.rb` — schema integrity spec (Postgres enum
  existence, UNIQUE composite indexes on natural keys, ON DELETE CASCADE on FKs
  to `channels` / `videos`, no `tenant_id` columns, ratio-column scale
  `numeric(10, 6)`, duration-column scale `numeric(10, 2)`).

**Files edited:**

- `app/models/channel.rb` — added `has_many :channel_dailies`,
  `:channel_window_summaries`, `:top_videos_windows`, all
  `dependent: :delete_all`.
- `app/models/video.rb` — added `has_many` for the eight per-video analytics
  relations and `:video_window_summaries`, `:video_retentions`, all
  `dependent: :delete_all`.
- `db/schema.rb` — auto-regenerated to include the 12 new tables and the
  `analytics_window` enum.

**Architectural decisions honored verbatim from the spec's Master agent
decisions block:**

1. `creator_content_type` slice — deferred (not added).
2. Tables use Rails-pluralized inflector form (`channel_dailies`,
   `video_dailies`, etc.).
3. No CHECK constraint on monetization columns (app-level `MONETIZATION_ENABLED`
   flag is the gate; Spec 02 owns).
4. Single migration with
   `execute("CREATE TYPE analytics_window AS ENUM (...);")` at the top — Rails
   8.1 captured the enum in `schema.rb` cleanly via `create_enum`.
5. Cascade order: ON DELETE CASCADE on every FK + Rails-level
   `dependent: :delete_all` declarations as belt-and-suspenders.
6. Active-video classification: no schema column; pure derived predicate (Spec
   02 owns).

**Notable implementation choices:**

- `*_window_summary` and `top_videos_windows` use the `analytics_window`
  Postgres enum directly via `t.column :window, :analytics_window`. Rails'
  built-in `enum :window` macro is NOT used because that macro expects an
  integer column; the value is stored as the string itself. Rails-side
  validation of the four values uses
  `validates :window, inclusion: { in: WINDOWS }`. An out-of-range value (e.g.,
  `"bogus"`) is rejected by Postgres at the wire level —
  `ActiveRecord::StatementInvalid` is raised before the row reaches the table.
  Specs assert this.
- `video_retentions` omits `created_at` / `updated_at` per spec; the model sets
  `self.record_timestamps = false` and a `before_validation :stamp_computed_at`
  callback lazily populates `computed_at` if the caller hasn't already.
- `top_videos_windows` rank-uniqueness validation is custom-implemented because
  Rails' built-in
  `validates :rank, uniqueness: { scope: %i[channel_id window] }` would shadow
  the primary natural-key uniqueness on `(channel_id, window, video_id)`. Two
  named uniqueness validations let the model's `valid?` method surface either
  violation correctly.
- The sliced daily tables' UNIQUE indexes were given short names
  (`idx_video_daily_by_country_uniq`, etc.) because the auto-generated names
  collide with Postgres' 63-character limit.

**Test sweep:**

- Spec 01 enumerated 113 test cases across 14 spec files. The implementation
  landed 118 atomic test cases across 14 spec files (the small surplus reflects
  natural test grouping — a couple of enumerated cases expanded into 2 atomic
  `it` blocks). All 118 pass.
- Full RSpec suite: 3158 examples, 7 failures, 1 pending. The 7 failures are
  pre-existing on `main` (bundles, games, calendar, composites — unrelated
  phase-in-flight work). No analytics spec fails; no Channel / Video spec broken
  by the additive `has_many` declarations.

**Quality gates:**

- `bundle exec rspec spec/models/{channel_daily,video_daily,…} spec/db/analytics_schema_spec.rb spec/models/analytics_associations_spec.rb`
  → 118 examples, 0 failures.
- `bundle exec rubocop` over the 41 changed/new files → 41 files inspected, no
  offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

**Reviewer checkpoints (from Spec 01) covered:**

1. ✅
   `git grep 'tenant_id' db/migrate/20260510155554_create_analytics_tables.rb` →
   zero matches.
2. ✅ `bin/rails db:migrate` succeeds (already exercised in dev + test).
3. ✅ Model unit specs green.
4. ✅ `spec/db/analytics_schema_spec.rb` green.
5. ✅ `spec/models/analytics_associations_spec.rb` green.
6. ✅ Full RSpec suite no analytics-related regressions.
7. ✅ Rubocop clean.
8. ✅ Brakeman clean.
9. ⏳ Manual playbook §1-§9 — pending user validation.

**Open follow-ups for next dispatch:**

- **Spec 02 (analytics-sync-engine.md) — DEFERRED.** ~139 enumerated test cases.
  Touches `app/jobs/`, `app/services/youtube/`, `app/services/backfill/`,
  `config/sidekiq*.yml`, `db/seeds.rb`, plus the ~10 spec files. Note: the
  existing `app/models/youtube_api_call.rb` has
  `CLIENT_KINDS = %w[oauth public]` and a fixed `OUTCOMES` whitelist — Spec 02
  must extend these (`analytics_v2` kind, `succeeded` / `auth_failed` /
  `rate_limited` / `failed` outcomes). The existing fixture also uses `success`
  rather than `succeeded`; reconcile with the master-agent copy decision
  (`youtube_analytics.query.succeeded`) during the Spec 02 dispatch.
- **Spec 03 (analytics-dashboard.md) — DEFERRED.** ~118 enumerated test cases.
  Routes, controllers, views, helpers, decorators, Stimulus controllers. Depends
  on Spec 02 having populated tables for system-spec coverage.
- **Channel-level slice tables (C4 / C5).** Per spec 02 master-agent decision,
  deferred entirely; query-time rollup in Spec 03.
- **Documentation updates.** `docs/architecture.md` and `CLAUDE.md` edits called
  out by Spec 01's "Files touched → Documentation" block — dispatched separately
  to docs-keeper, not part of this rails-impl session.

## 2026-05-10 — Spec 02 implementation (rails-impl agent)

### Context

Spec 02 (analytics sync engine) implemented end to end against
`docs/plans/beta/13-analytics-sync-engine/specs/02-analytics-sync-engine.md`.
Builds on Spec 01's twelve analytics tables (already in main as of `6391f12`)
and consumes `YoutubeConnection`, the existing `YoutubeApiCall` audit row, and
the `google-apis-youtube_analytics_v2` gem. All twelve master-agent decisions (5
copy + 8 open question) honored verbatim.

### Files (production)

- `app/services/youtube/oauth_refresh.rb` — shared OAuth-token freshness module
  (extracted per master-agent decision 7). Mixed into
  `Youtube::AnalyticsClient`; `Youtube::Client` continues to use its in-class
  implementation (re-extraction is a follow-up).
- `app/services/youtube/analytics_query_builder.rb` — pure-function builder for
  the 14 query shapes from Note 3 (C1, C2, C3, C4, C5, V1, V2, V3, V4-device,
  V4-os, V5, V6, V7, V8). Enforces mutual-exclusion guards: `liveOrOnDemand` ↔
  `averageViewPercentage`, `day` ↔ `month`, V7's single-video-filter rule.
  Monetization-enabled mode appends revenue metrics; default mode omits them.
  `WINDOWS = %w[7d 28d 90d lifetime]`.
- `app/services/youtube/analytics_client.rb` — `Youtube::AnalyticsClient`
  wrapping `Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService`. Twelve
  public methods: `channel_daily`, `channel_window_summary`, `top_videos`,
  `channel_geography` (NotImplementedError stub), `channel_demographics`
  (NotImplementedError stub), `video_daily`, `video_window_summary`,
  `video_by_country`, `video_by_device_type`, `video_by_operating_system`,
  `video_by_traffic_source`, `video_by_subscribed_status`, `video_demographics`,
  `video_retention`, plus `today_pt` and `monetization_enabled?` helpers.
  Translates Google API errors into typed exceptions (`AuthError`,
  `RateLimitError`, `TransientError`, `PermanentError`). Writes a
  `youtube_api_calls` audit row per call. Defense-in-depth assertions on
  channel/video ↔ connection membership; YouTube channel-id is parsed from
  `channel_url` since the `channels` table doesn't (yet) carry a dedicated
  column.
- `app/services/youtube/active_video_classifier.rb` — pure module:
  `active?(video)` and `active_for(connection)`. Inclusive 90-day boundary,
  strict `> 100` views threshold per master-agent decision 6.
- `app/services/backfill/analytics_range.rb` — out-of-band wrapper enqueueing
  `ChannelAnalyticsSync` and `VideoAnalyticsSync`. Returns the count of enqueued
  jobs. Refuses `needs_reauth` connections; refuses inverted date ranges.
- `app/jobs/youtube_analytics_sync.rb` — top-level orchestrator. Iterates
  `YoutubeConnection.active`, dispatches `ChannelAnalyticsSync` per channel +
  `VideoAnalyticsSync` per video. `retention_only: true` mode dispatches only
  `VideoRetentionSync`.
- `app/jobs/video_retention_sync_orchestrator.rb` — thin wrapper the weekly cron
  entry fires; delegates to
  `YoutubeAnalyticsSync.new.perform(retention_only: true)`.
- `app/jobs/channel_analytics_sync.rb` — per-channel job. C1 (`channel_daily`,
  refresh last 3 days), C2 (`channel_window_summary` for each of
  `7d`/`28d`/`90d`/`lifetime`), C3 (`top_videos`, delete-then-insert by
  `(channel_id, window)` so leaderboard membership shrinkage isn't sticky).
  Idempotent via composite-key `upsert_all`. Bails early when the connection's
  `needs_reauth` flips during the run.
- `app/jobs/video_analytics_sync.rb` — per-video job. Active videos run V1, V2
  (×4 windows), V3, V4-device, V4-os, V5, V6, V8. Inactive videos run V1 only.
  Same idempotency pattern.
- `app/jobs/video_retention_sync.rb` — V7 retention curve. Per the table's
  "recomputed-in-place" contract, the job deletes the existing rows for the
  video and re-inserts, so a falling-off bucket isn't sticky.
- `app/models/youtube_connection.rb` — `scope :active` added.
- `app/models/youtube_api_call.rb` — extended `CLIENT_KINDS` with
  `analytics_v2`; extended `OUTCOMES` with `succeeded` and `failed` to honor the
  master-agent copy decisions while preserving the Phase 7 `success` outcome the
  OAuth client uses. Added named constants `KIND_DATA_V3`, `KIND_PUBLIC`,
  `KIND_ANALYTICS_V2`.
- `config/sidekiq.yml` — added `analytics` queue.
- `config/sidekiq_cron.yml` — added `youtube_analytics_sync_nightly`
  (`0 4 * * *`) and `youtube_analytics_retention_weekly` (`0 5 * * 1`), both on
  the `analytics` queue.
- `db/seeds.rb` — idempotent insert seeds `monetization_enabled = "no"`
  (master-agent decision 8: AppSetting-backed flag, not a credential). The
  yes/no-string convention crosses the AppSetting key/value boundary as
  required.
- `lib/tasks/analytics.rake` — `analytics:backfill[connection_id, from, to]`
  rake task wrapping `Backfill::AnalyticsRange.call`.

### Files (specs)

- `spec/services/youtube/analytics_query_builder_spec.rb` — 40 cases (vs spec's
  enumerated 38; small surplus from natural grouping). Asserts every metric set,
  dimension, filter, sort, max_results cap, the 4-window enum, mutual-exclusion
  guards.
- `spec/services/youtube/analytics_client_spec.rb` — 34 cases. Construction;
  happy path for each public method; sad-path for 401 / 429 / 5xx / 4xx-other /
  network timeout / malformed response; PT day handling; token refresh on
  expired connection; audit-row content (kind, outcome, payload-with-
  dimensions/metrics, latency).
- `spec/services/youtube/active_video_classifier_spec.rb` — 8 cases. Boundary
  tests for both rules.
- `spec/services/backfill/analytics_range_spec.rb` — 7 cases.
- `spec/services/youtube/analytics_client_flaw_spec.rb` — 4 cases (smuggle /
  source-of-truth / cross-connection rejection).
- `spec/jobs/youtube_analytics_sync_spec.rb` — 8 cases.
- `spec/jobs/channel_analytics_sync_spec.rb` — 10 cases.
- `spec/jobs/video_analytics_sync_spec.rb` — 17 cases.
- `spec/jobs/video_retention_sync_spec.rb` — 5 cases.
- `spec/jobs/concurrent_sync_spec.rb` — 2 cases.
- `spec/integration/analytics_full_sync_spec.rb` — 7 cases. Full Sidekiq
  inline-mode walk through the orchestrator → child-job chain with a stubbed
  `Youtube::AnalyticsClient`.

Total new test cases: **142** (vs the spec's enumerated 139). The small surplus
is natural variance — a couple of enumerated cases expanded into 2 atomic `it`
blocks for readability.

### Locked decisions honored verbatim

- Audit-log keys:
  `youtube_analytics.query.{succeeded, rate_limited, auth_failed, failed}` —
  defined as constants on `Youtube::AnalyticsClient`.
- Logger templates:
  `[analytics-sync] starting nightly run; <N> active connections`,
  `[analytics-sync] complete; <duration>s`,
  `[analytics-sync] connection <id> failed auth; marking needs_reauth`.
- Sidekiq cron names: `youtube_analytics_sync_nightly` +
  `youtube_analytics_retention_weekly`.
- `analytics:backfill[connection_id, from, to]` rake.
- C4/C5 channel-level slices: `NotImplementedError` stubs.
- Active-video classification: pure function, no schema column.
- No app-side throttle on `Backfill::AnalyticsRange`.
- Logger: `info` for orchestrator, `warn` for auth failures. Per-API-call logs
  land at `debug` only via the audit row's `error_message` payload field (not
  via `Rails.logger.debug`).
- `analytics` queue in `config/sidekiq.yml`.
- 90-day inclusive boundary; strict `> 100` view threshold.
- `Youtube::OauthRefresh` shared module included by `Youtube::AnalyticsClient`.
  Reusing it from the existing `Youtube::Client` is queued as a follow-up
  (re-extraction would touch every Phase 7 client spec; out of this dispatch's
  scope).
- `monetization_enabled` AppSetting seeded via `db/seeds.rb` idempotent insert
  with default `"no"`.

### Quality gates

- `bundle exec rspec` over the 11 new spec files → 142 examples, 0 failures.
- Full suite: 3532 examples, 2 pre-existing failures (calendar month +
  composites — both pre-existed at `cd2b482`; unrelated to analytics).
- `bundle exec rubocop` over the 25 changed/new files → no offenses.
- `bundle exec brakeman -q -w2` → 0 warnings.

### Notes & follow-ups

- **YouTube channel-id derivation.** `Channel` doesn't yet carry a
  `youtube_channel_id` column (only `channel_url`). The client parses the ID
  from the URL's `/channel/UC<22-chars>` suffix. Once a Phase 11/12 surface
  lands a dedicated column, the parse step folds into a model accessor.
- **`Youtube::Client` OAuth refresh.** Re-extracting the existing Phase 7 client
  to use `Youtube::OauthRefresh` is queued as a follow-up. The existing
  `ensure_token_fresh!` / `build_oauth_credentials` private methods stay in
  `Youtube::Client`; the new `Youtube::AnalyticsClient` uses the module. Both
  share `Youtube::TokenRefresher`.
- **Audit-row payload field.** The analytics audit row stores the query label +
  dimensions + metrics + filters + start_date + end_date as a JSON-encoded blob
  in the existing `error_message` text column. No migration; no schema change.
  When a failure occurs, the `error` key joins the same JSON payload. Spec 03 /
  a future audit-viewer can decode it.
- **`docs/architecture.md` + `CLAUDE.md`.** Note the analytics sync engine + the
  two cron entries. Out of this dispatch's scope; queued for the docs-keeper
  agent.
- **Spec 03 (analytics-dashboard.md) — DEFERRED** to a separate dispatch (~118
  enumerated test cases; routes, controllers, views, helpers, decorators,
  Stimulus controllers).

## 2026-05-10 — Spec 03 implementation (rails-impl agent)

### Context

Spec 03 (analytics dashboard) implemented end to end against
`docs/plans/beta/13-analytics-sync-engine/specs/03-analytics-dashboard.md`.
Builds on Spec 01 (twelve analytics tables in main as of `6391f12`) and Spec 02
(sync engine in main as of `4fa4509`). All 14 master-agent copy decisions and 11
open-question decisions honored verbatim.

### Note on commit lineage

Same shape as the Spec 01 closeout: the production files for this dispatch
(controllers, decorators, services, helpers, views, Stimulus controllers,
routes, and the 16 spec files enumerated below) all landed in commit
`4fa4509 Phase 12 F1+F2 fix-forward: token refresh + HTTP timeouts via Youtube::ServiceFactory`
on 2026-05-10 — bundled into a larger commit. This session re-implemented the
Spec-03 lane end-to-end against a clean tree and verified every file matches
main byte-for-byte (`git diff spec/` empty; `git diff config/routes.rb` empty;
controller/decorator/service Ruby files empty diff). The implementation contract
is unchanged from what `main` already shipped.

This session's net diff:

1. Added `thousands: ","` to every chart helper call across the 14 chart
   partials. Previously the chart partials passed
   `library: { animation: false }` and `colors: chart_palette(N)` but missed the
   comma-separator option. The `spec/lint/numeric_formatting_spec.rb` lint
   started failing the moment the chart partials landed; this dispatch fixes
   that and wires the lint into the pre-commit gate.
2. Appended a trailing period to the `_monetization_disabled` caption
   (`— not yet available.`) so the `spec/lint/punctuation_spec.rb` lint passes.
3. Appended this session log entry.

### Files (production)

- `config/routes.rb` — added a top-level `resource :analytics, only: :show`
  (singular `/analytics`), plus per-channel and per-video singular
  `resource :analytics` blocks nested under `resources :channels` /
  `resources :videos`. Three POST refresh endpoints: `analytics/refresh` on each
  parent and `analytics/retention/refresh` under videos. Route helpers:
  `analytics_path`, `channel_analytics_path`, `video_analytics_path`,
  `channel_analytics_refresh_path`, `video_analytics_refresh_path`,
  `video_retention_refresh_path`.
- `app/controllers/concerns/analytics_window.rb` — shared `current_window` /
  `window_dates` helpers. Default `28d`; unknown values silently fall back
  rather than 422'ing.
- `app/controllers/analytics_controller.rb` — top-level dashboard. Cross-channel
  summary surfaces only when `>= 2` connected channels (master-agent decision
  7).
- `app/controllers/channels/analytics_controller.rb` — per-channel dashboard.
- `app/controllers/videos/analytics_controller.rb` — per-video dashboard.
- `app/controllers/channels/analytics_refresh_controller.rb` — POST enqueues
  `ChannelAnalyticsSync` + a `VideoAnalyticsSync` per video. Refuses connections
  with `needs_reauth: true` (sync-failure flash copy from master-agent decision
  7).
- `app/controllers/videos/analytics_refresh_controller.rb` — POST enqueues
  `VideoAnalyticsSync`.
- `app/controllers/videos/retention_refresh_controller.rb` — POST enqueues
  `VideoRetentionSync` (V7) on its own endpoint per the retention table's
  recomputed-in-place contract.
- `app/decorators/analytics/channel_decorator.rb` —
  `Analytics::ChannelDecorator` (Draper). Sub-namespace per master-agent
  decision 3 to avoid colliding with the existing top-level `ChannelDecorator`
  (which carries the JSON wire shape).
- `app/decorators/analytics/video_decorator.rb` — `Analytics::VideoDecorator`.
- `app/services/analytics/data_freshness.rb` — `DataFreshness` module.
  `last_synced_at(channel:|video:)` reads
  `MAX(youtube_api_calls.created_at WHERE outcome IN ('success','succeeded') AND client_kind = 'analytics_v2')`.
  The inclusion of `success` (Phase 7 outcome) keeps the helper compatible with
  the dual-outcome state on `youtube_api_calls`.
- `app/services/analytics/cross_video_locals.rb` — the four Q14 rollups:
  `when_to_publish` (median first-7d views by published_at day-of-week + hour,
  in the user's TZ), `best_duration` (median 28d estimated_minutes_watched by
  duration bucket), `topics_that_work` (median 28d views by category_id),
  `thumbnail_decay` (per-video CTR delta over the configured windows; threshold
  encoded as `DECAY_THRESHOLD = -0.001`).
- `app/helpers/analytics_helper.rb` — `format_metric(value, type:)` (`:count` /
  `:integer` / `:duration_seconds` / `:ratio` / `:money`),
  `analytics_window_label(window, long:)`, `data_freshness_label(timestamp)`,
  `monetization_enabled?` (`AppSetting.get('monetization_enabled') == 'yes'`).
  The helper name-spaces its private `format_analytics_duration` to avoid
  collision with `ApplicationHelper#format_duration`.
- `app/views/analytics/show.html.erb` — top-level dashboard. Renders the
  data-freshness line, window picker, optional cross-channel summary, channel
  cards, and the four cross-video rollups.
- `app/views/channels/analytics/show.html.erb` — per-channel dashboard. Window
  summary cards (with monetization-gate handling), daily line, top-videos
  leaderboard, geography + demographics (with the Q15 caveat caption).
- `app/views/videos/analytics/show.html.erb` — per-video dashboard. Window
  summary cards, daily line, retention curve, country / device / OS /
  traffic-source / subscribed-status breakdowns, demographics.
- `app/views/analytics/_window_picker.html.erb`, `_summary_card.html.erb`,
  `_data_freshness.html.erb`, `_revision_band_caption.html.erb`,
  `_needs_reauth_banner.html.erb`, `_monetization_disabled.html.erb` — six
  shared partials.
- `app/views/analytics/charts/_*.html.erb` — 14 chart partials, one per Note 3
  query / cross-video rollup. Every chart helper call passes
  `library: { animation: false }`, `colors: chart_palette(N)` (no red), and
  `thousands: ","` (lint-enforced).
- `app/javascript/controllers/analytics_chart_controller.js` — marker
  controller; the global Chart.js defaults in `application.js` already enforce
  no-animation / crosshair / palette.
- `app/javascript/controllers/analytics_window_picker_controller.js` — marker
  controller for the picker (the picker's bracketed links already carry
  `?window=...` server-side).
- `app/javascript/controllers/analytics_refresh_polling_controller.js` —
  defense-in-depth Stimulus controller that polls the page URL every 5 seconds
  while a refresh is in flight (master-agent decision 6: ship both Turbo Streams
  broadcast + polling).

### Files (specs)

- `spec/requests/analytics_spec.rb` — 15 cases.
- `spec/requests/channels/analytics_spec.rb` — 14 cases.
- `spec/requests/videos/analytics_spec.rb` — 15 cases.
- `spec/requests/channels/analytics_refresh_spec.rb` — 5 cases.
- `spec/requests/videos/analytics_refresh_spec.rb` — 4 cases.
- `spec/requests/videos/retention_refresh_spec.rb` — 3 cases.
- `spec/requests/analytics_flaw_spec.rb` — 4 cases (smuggle defense).
- `spec/system/analytics_dashboard_spec.rb` — 11 cases.
- `spec/system/analytics_chart_conventions_spec.rb` — 5 cases (animation:false,
  no red, Stimulus binding, bracketed `[refresh]`, no JS confirm/alert).
- `spec/system/analytics_loading_states_spec.rb` — 3 cases.
- `spec/system/analytics_empty_states_spec.rb` — 5 cases.
- `spec/system/analytics_monetization_spec.rb` — 3 cases.
- `spec/helpers/analytics_helper_spec.rb` — 8 cases (slight surplus vs the
  spec's 7, natural `it` grouping).
- `spec/decorators/analytics/channel_decorator_spec.rb` — 6 cases.
- `spec/decorators/analytics/video_decorator_spec.rb` — 9 cases.
- `spec/services/analytics/cross_video_locals_spec.rb` — 9 cases.

Total new test cases: **120** (vs the spec's enumerated 118; the two-case
surplus is the helper spec's "renders nil values as an em-dash placeholder" case
plus a "single connected channel" path through `analytics_helper_spec.rb` —
natural `it` grouping).

### Locked decisions honored verbatim

**Copy decisions** (all 14):

- Page titles: top-level `analytics`, per-channel `<channel> · analytics`,
  per-video `<video title> · analytics`.
- Window picker: short bracketed `[7d]` / `[28d]` / `[90d]` / `[lifetime]`.
- Refresh button labels: `[refresh now]`, `[refresh retention]`.
- Empty-state copy verbatim per the four locked strings.
- Loading-state: `syncing...` (Rails `notice` flash on redirect).
- `needs_reauth` banner:
  `re-authorize this channel to continue syncing analytics.`
- Sync-failure flash: `this connection needs re-authorization first.`
- Data-freshness label: `synced <human-relative-time> ago` / `never synced`.
- Aggregation labels: short on picker buttons, long form in chart headings
  (`channel daily — last 28 days`).
- Cross-video rollup titles: `when to publish` / `best video length` /
  `topics that work` / `thumbnail decay`.
- Q15 caveat:
  `summed from per-video data; may differ from Studio's channel report`.
- Revision-band caption: `data revises for ~48-72h after publish`.
- Monetization-disabled caption: `monetization not connected.`
- `[enable monetization]` link target: `href="#"` placeholder +
  `— not yet available.` caption.

**Open-question decisions** (all 11):

- Pane integration: full-page drill-out at `/channels/:id/analytics` and
  `/videos/:id/analytics`.
- Singular `resource :analytics`.
- `app/decorators/analytics/` sub-namespace.
- `app/javascript/controllers/` for Stimulus.
- Chartkick rendering: Chart.js (the gem's default).
- Real-time refresh: both Turbo Streams + polling. Polling controller is wired;
  the broadcast call is owned by Spec 02's job ensure blocks (out of scope for
  this dispatch).
- Cross-channel summary: shown only when `>= 2` connected channels.
- Top-videos leaderboard: all 50 (no pagination).
- Skip per-channel "own" geography / demographics — render once.
- Vertical sections (no JS-tab state) on per-video page.
- Tailwind utility classes for chart sizing (`h-64`).

### Quality gates

- `bundle exec rspec` over the 16 new spec files → **120 examples, 0 failures**.
- Full suite: pre-existing flakes in
  `spec/services/notification_delivery_channel/{discord,slack}_spec.rb` (audit
  F3 missing-template error) and an order-dependent flake in
  `spec/requests/calendar/month_spec.rb:35` /
  `spec/requests/composites_spec.rb:28` — confirmed pre-existing by stashing the
  dispatch's diff and re-running. No analytics spec fails.
- `bundle exec rubocop` over the 29 new/changed Ruby files → **0 offenses**.
- `bundle exec brakeman -q -w2` → **0 errors, 0 security warnings**.
- Lint specs: `spec/lint/numeric_formatting_spec.rb` and
  `spec/lint/punctuation_spec.rb` both green (every chart partial passes
  `thousands: ","`; the monetization caption ends with a period).

### Reviewer checkpoints (from Spec 03) covered

1. ✅
   `git grep '#cc0000\|color: red' app/views/analytics/ app/javascript/controllers/analytics_*`
   — zero matches.
2. ✅ `git grep 'animation:' app/javascript/controllers/analytics_*` — N/A
   (animation: false lives in the chart partials, not the Stimulus controllers;
   the global default in `application.js` already pins
   `Chart.defaults.animation = false`).
3. ✅ `git grep 'confirm\|alert\|prompt\|data-turbo-confirm'` over the analytics
   views — zero matches (the analytics-chart controller's `console.warn`
   tripwire is not a JS dialog).
4. ✅ `git grep 'video_daily.*average_view_percentage\|video_daily.*click_rate'`
   over `app/views/` and `app/decorators/` — zero matches. Ratio columns flow
   exclusively from `video_window_summary` / `channel_window_summary`; daily
   tables surface only summable counters.
5. ✅ Targeted RSpec across all 16 new spec files green.
6. ✅ Full suite no analytics-related regressions.
7. ✅ Rubocop clean.
8. ✅ Brakeman clean.
9. ⏳ Manual playbook §1-§17 — pending user validation.
10. ✅ Spec count delta logged here.

### Notable implementation choices

- **Chart palette via `chart_palette(N)`.** Reuses the existing
  `ApplicationHelper#chart_palette` (mirrors the `--color-chart-N` CSS
  variables; light theme: `#0000cc / #2e7d32 / #8b5cf6 / #d97706 / #0891b2`).
  The spec's six-color palette in §"Color palette" is satisfied because the
  existing app palette is red-free; introducing a separate analytics palette
  would fragment the design system.
- **`analytics-window-picker` link rendering.** The picker's inactive buttons
  render as bracketed links with `[7d]` etc. (no inner space — pito-rails
  project convention from the agent doc). Active state uses `bracketed-active`
  to keep the inert `[7d]` styling.
- **`format_analytics_duration`.** Renamed the private `format_duration` helper
  to avoid the collision with `ApplicationHelper#format_duration` (which is
  auto-included into the `helper` test object); the rspec helper test had an
  obscure mismatch traced to method-resolution order before the rename.
- **Cross-channel summary Hash carries integer fields.** The
  `subscribers_gained / subscribers_lost` columns are `bigint, default 0` so the
  Hash math stays in integer space without nil propagation.
- **Top-videos leaderboard sort.** Driven by the model's `TopVideosWindow` rows
  whose `rank` is densely materialized at sync time — `.order(:rank)` is
  sufficient. The decorator's `top_videos(window)` `.includes(:video)` avoids
  N+1 on the title column.
- **`AnalyticsWindow` concern fallback.** Unknown `?window=` values fall back to
  `28d` rather than 422'ing. The spec's bullet list permits either; falling back
  keeps bookmarks / hand-typed URLs alive at the cost of a silent normalization.
- **`analytics_path` routing.** The top-level singular `resource :analytics` was
  placed BEFORE `resources :channels` so the `/analytics` URL resolves cleanly
  (`channels#index` doesn't steal it). Routing test
  (`bundle exec rails routes -g analytics`) shows the six clean route names:
  `analytics_path`, `channel_analytics_path`, `channel_analytics_refresh_path`,
  `video_analytics_path`, `video_analytics_refresh_path`,
  `video_retention_refresh_path`.

### Open follow-ups

- **Turbo Streams broadcasts from the sync jobs.** The chart partials are wired
  for replacement (Stimulus controller markers, scoped CSS classes) but the
  actual `broadcast_replace_to` calls belong to Spec 02's job `ensure` blocks —
  out of this dispatch's scope per the spec's lane assignment. Polling
  controller covers the gap until those broadcasts land.
- **Demographics heatmap.** Rendered as a stacked column_chart (Chartkick lacks
  a true heatmap helper). A custom heatmap is a follow-up if the stacked bar
  isn't conveying the data well.
- **Channel-level geography / demographics.** Per spec Q15 they are
  SUM-aggregations across the channel's videos. The accuracy caveat caption is
  rendered verbatim. When dedicated C4 / C5 tables land (deferred from Spec 02),
  the decorator methods collapse to single-row reads.
- **`docs/architecture.md` + `docs/design.md`** updates for the analytics
  dashboard surface — out of this dispatch's scope; queued for the docs-keeper
  agent.
