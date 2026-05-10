# Phase 13.2 — Analytics Sync Engine

> **Status:** dispatched 2026-05-10. Single-lane: **rails**. Second of three
> specs in Phase 13. Builds on spec 01 (data model) which is assumed landed.
> Dashboard (spec 03) consumes the rows this engine writes.
>
> **Cross-references:**
>
> - `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — query
>   shapes (C1-C5, V1-V9), windowing rules, sync schedule, mutual-exclusion
>   gotchas, monetization posture.
> - `docs/realignment-2026-05-09.md` — work unit 5.
> - `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
>   `YoutubeConnection` is the OAuth grant the engine iterates.
> - `docs/plans/beta/13-analytics-sync-engine/specs/01-analytics-data-model.md`
>   — defines every table this engine writes.
> - `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
>   — `YoutubeConnection` model, `needs_reauth` flag, encrypted tokens.
> - `docs/plans/beta/12-video-schema-expansion/` — Video schema with
>   `youtube_video_id`, `published_at`.
> - `app/jobs/channel_sync.rb` — existing placeholder job pattern.
> - `app/services/youtube/client.rb` — existing OAuth-aware client; analytics
>   client follows the same construction pattern.
> - `Gemfile` — `google-apis-youtube_analytics_v2` already vendored.
> - `CLAUDE.md` — top-level rules (yes/no boundary, secrets in credentials,
>   monospace 13px, no JS confirm).

## Goal

The engine that turns the empty analytics tables (spec 01) into populated ones.
Six surfaces:

1. **Top-level orchestrator** (`YoutubeAnalyticsSync`) — Sidekiq job. Iterates
   every active `YoutubeConnection`; dispatches per-connection work.
2. **Per-connection child jobs** — one per channel (`ChannelAnalyticsSync`), one
   per video (`VideoAnalyticsSync`), one per active video for retention
   (`VideoRetentionSync`).
3. **Analytics API client** (`Youtube::AnalyticsClient`) — wraps
   `google-apis-youtube_analytics_v2`; centralizes the query builder; handles
   retries / backoff; surfaces token-expiry as a typed exception.
4. **Active-video classifier** — `Youtube::ActiveVideoClassifier` — pure
   function deriving the active set per Note 3's "uploaded in last 90 days OR >
   100 views in last 7 days."
5. **Backfill mode** — `Backfill::AnalyticsRange.call(connection, from:, to:)` —
   for catching gaps after a connection re-authorizes or when filling in initial
   history.
6. **Sidekiq cron schedule** — `config/sidekiq.yml` (or sidekiq-cron config)
   wires the nightly + weekly cadences per Note 3 §"Sync schedule."

The engine is the load-bearing logic of the analytics surface. The data model is
mechanical; this spec is where the YouTube API quirks (Pacific Time day
boundaries, 3-day revision lag, mutually-exclusive dimensions, rate limits,
token expiry, 100-row retention responses) get codified.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                      |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Sync schedule.** Daily at 04:00 UTC. Weekly retention refresh at 05:00 UTC every Monday. On-demand "refresh this video" launches V1-V8 inline. Backfill runs out-of-band via `Backfill::AnalyticsRange.call`.                                                                                                                               |
| Q2  | **Retention.** All-time. No purging.                                                                                                                                                                                                                                                                                                          |
| Q3  | **Per-connection orchestration.** The orchestrator iterates `YoutubeConnection.active` (active = `needs_reauth: false`). Each connection's channels are synced in sequence. Connections are processed in parallel (Sidekiq queues).                                                                                                           |
| Q4  | **Storage.** Postgres only. No TSDB.                                                                                                                                                                                                                                                                                                          |
| Q5  | **Sync triggering.** Cron + on-demand. The Sidekiq cron entry runs nightly; the dashboard (spec 03) exposes a "refresh this video" button that enqueues `VideoAnalyticsSync` immediately.                                                                                                                                                     |
| Q6  | **Refresh window.** 3 days. Per Note 3 §"Storage strategy" — "Daily sync writes new rows for 'yesterday' and rewrites the last 3 days." The fetch range every nightly run = `[today_pt - 3, today_pt - 1]`. Backfill targets arbitrary ranges.                                                                                                |
| Q7  | **Active-video classification.** Pure function, no schema column. `ActiveVideoClassifier.active?(video)` returns true if `video.published_at >= 90.days.ago` OR `video.video_dailies.where(date: 7.days.ago..).sum(:views) > 100`. Recomputed on every nightly run.                                                                           |
| Q8  | **Retry / backoff.** Exponential backoff for HTTP 5xx, 429, network timeouts. Base delay 30s; max 5 retries; max delay 30 minutes. Sidekiq's `retry: true` handles the queueing; the analytics client's job-side wrapper translates Google API errors to retry-or-fail decisions.                                                             |
| Q9  | **Token expiry handling.** On HTTP 401 from the Analytics API, set `connection.update!(needs_reauth: true)`, write an audit row to `youtube_api_calls`, log a `Rails.logger.warn`, and SKIP the connection's remaining channels for this cycle. Other connections continue.                                                                   |
| Q10 | **Monetization.** Schema-ready, sync-disabled. `MONETIZATION_ENABLED` is read from `Rails.application.credentials.youtube&.dig(:monetization_enabled)` (or AppSetting; agent picks). When false, the query builder omits the revenue metrics. When true, appends them.                                                                        |
| Q11 | **Pacific Time day handling.** The orchestrator computes `today_pt = Time.now.in_time_zone("Pacific Time (US & Canada)").to_date`. Every API call uses `(today_pt - 3, today_pt - 1)` as the fetch range. The DB stores the PT date verbatim per spec 01 Q9.                                                                                  |
| Q12 | **Rate-limiting / parallelism.** Per Note 3 §"Quota" — Analytics v2 has its own quota separate from Data API v3. Each `reports.query` is 1 quota unit. Bottleneck is wall-clock. Use 4 parallel Sidekiq workers per connection (matches Note 3's "3-5 parallel workers"). The "default" queue handles every analytics job; no separate queue. |
| Q13 | **Idempotency.** Every job is idempotent by composite-key upsert (spec 01's UNIQUE indexes). Re-running a sync for the same date range overwrites the previous values. No row-skipping. The 3-day refresh window relies on this.                                                                                                              |
| Q14 | **Audit row per API call.** Every `reports.query` writes a `youtube_api_calls` row with `client_kind: 'analytics_v2'`, `youtube_connection_id`, `outcome` (`'ok'` / `'rate_limited'` / `'auth_failed'` / `'failed'`), `query_dimensions`, `query_metrics`, `latency_ms`. Reuses the existing `youtube_api_calls` table (Phase 7 surface).     |
| Q15 | **Audit kind enum.** `client_kind` is currently a string column; the existing values are `'data_v3'` (Phase 7). Add `'analytics_v2'`. No enum migration; just a new string value. The audit-row schema can absorb new kinds without a migration.                                                                                              |
| Q16 | **First-sync history.** When a `YoutubeConnection` is freshly authorized, its lifetime `*_window_summary` row is empty. The first nightly run computes lifetime in addition to 7d/28d/90d. Subsequent runs recompute lifetime daily (cheap — one query per channel + one per active video).                                                   |
| Q17 | **Mutually-exclusive dimensions.** `liveOrOnDemand` + `averageViewPercentage` cannot coexist (Note 3 §"Mutual-exclusion gotchas" §1). C1/V1 do not include `liveOrOnDemand`. C2/V2 do not include `liveOrOnDemand`. The query builder enforces this; spec 03's dashboard handles the absence.                                                 |
| Q18 | **Live-broadcast metrics (V9).** Out of scope. Note 3 §V9 covers `averageConcurrentViewers` / `peakConcurrentViewers` for live broadcasts only. No table in spec 01 holds these (Note 3 lists no table for V9 explicitly). Defer to a future "live broadcast analytics" spec.                                                                 |

## Migration posture (LOCKED)

**Code-only.** This spec adds no migrations. Spec 01 owns the schema; this spec
writes against it. The `youtube_api_calls` table already exists (Phase 7) and
absorbs the new `'analytics_v2'` kind value via the existing string column.

## Files touched

### Jobs (new)

- `app/jobs/youtube_analytics_sync.rb` — top-level orchestrator. Cron-triggered.
- `app/jobs/channel_analytics_sync.rb` — per-channel job. Runs C1-C5 for one
  channel.
- `app/jobs/video_analytics_sync.rb` — per-video job. Runs V1-V6, V8 for one
  video.
- `app/jobs/video_retention_sync.rb` — per-video V7 job. Cron-triggered weekly.

Each is a `Sidekiq::Job` with `sidekiq_options queue: "default", retry: true`.
Each job's `perform` accepts the row's `id` (not the AR object) per the project
convention (see `ChannelSync` shape).

### Services (new)

- `app/services/youtube/analytics_client.rb` — wraps
  `Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService`. Public surface:
  - `initialize(connection:)` — accepts a `YoutubeConnection`.
  - `#channel_daily(channel:, from:, to:)` — runs C1; returns a parsed array of
    attribute-hashes ready for `ChannelDaily.upsert_all`.
  - `#channel_window_summary(channel:, window:)` — runs C2 for the given window
    enum value.
  - `#top_videos(channel:, window:, limit: 50)` — runs C3.
  - `#channel_geography(channel:, from:, to:)` — runs C4 (note: the data model
    in spec 01 does not yet hold a `channel_daily_by_country` table; C4 is
    currently consumed by the dashboard via on-the-fly query of
    `video_daily_by_country` summed across the channel's videos. This method is
    a no-op stub raising `NotImplementedError`; surface as an open question —
    should the data model gain a per-channel geography table in spec 01?).
  - `#channel_demographics(channel:, from:, to:)` — runs C5; returns parsed
    rows. Note 3's V8 demographics table on spec 01 covers per-video
    demographics; channel demographics has no table. **Same issue as C4** —
    no-op stub. Open question on data model coverage.
  - `#video_daily(video:, from:, to:)` — runs V1.
  - `#video_window_summary(video:, window:)` — runs V2.
  - `#video_by_country(video:, from:, to:)` — runs V3 →
    `video_daily_by_country`.
  - `#video_by_device_type(video:, from:, to:)` — runs V4 (deviceType only).
  - `#video_by_operating_system(video:, from:, to:)` — runs V4 (operatingSystem
    only).
  - `#video_by_traffic_source(video:, from:, to:)` — runs V5 →
    `video_daily_by_traffic_source`.
  - `#video_by_subscribed_status(video:, from:, to:)` — runs V6 →
    `video_daily_by_subscribed_status`.
  - `#video_demographics(video:, from:, to:)` — runs V8 →
    `video_daily_by_age_group_gender`.
  - `#video_retention(video:)` — runs V7.

  The class internally uses `Youtube::AnalyticsQueryBuilder` (below) to shape
  the `reports.query` parameter. Every public method does:
  - Build the params via the query builder.
  - Issue the `reports.query` call with timing instrumentation.
  - Catch known error classes (`Google::Apis::AuthorizationError`,
    `Google::Apis::RateLimitError`, `Google::Apis::ServerError`,
    `Google::Apis::ClientError`, `Errno::ETIMEDOUT`, `Faraday::TimeoutError`).
  - Translate to typed exceptions (`Youtube::AnalyticsClient::AuthError`,
    `RateLimitError`, `TransientError`, `PermanentError`).
  - Write a `youtube_api_calls` audit row (success or failure).
  - Return parsed attribute-hashes for the caller to upsert.

- `app/services/youtube/analytics_query_builder.rb` — pure function; no DB / no
  network. Public:
  - `.channel_daily_params(channel_youtube_id:, from:, to:, monetization_enabled: false)`
    → params hash for `reports.query`.
  - One method per query (C1, C2, C3, C4, C5, V1, V2, V3, V4-device, V4-os, V5,
    V6, V7, V8) — 14 methods total.
  - Each method enforces the mutual-exclusion rules from Note 3
    §"Mutual-exclusion gotchas":
    - §1: `liveOrOnDemand` + `averageViewPercentage` never coexist.
    - §2: `day` + `month` never coexist.
    - §3: V7 (audience retention) requires a single video filter.
    - §6: `top_videos` / `traffic_source_detail` need `sort` + `maxResults`
      caps.
  - Monetization-enabled mode appends the revenue metrics; otherwise omits.
  - Returns a hash matching the `google-apis-youtube_analytics_v2` gem's
    `query_report` parameter shape (`ids:`, `start_date:`, `end_date:`,
    `metrics:`, `dimensions:`, `filters:`, `sort:`, `max_results:`).

- `app/services/youtube/active_video_classifier.rb` — pure module:
  - `.active?(video)` — boolean per Note 3's rule.
  - `.active_for(connection)` — returns the `Video` relation for the
    connection's channels filtered by the rule.

- `app/services/backfill/analytics_range.rb` — module:
  - `.call(connection:, from:, to:, channels: nil, videos: nil)` — enqueues
    `ChannelAnalyticsSync` / `VideoAnalyticsSync` jobs covering the date range,
    scoped to the given channels / videos (or all under the connection if not
    specified). Returns the count of jobs enqueued.

### Models (edit)

- `app/models/youtube_connection.rb`:
  - Add a class scope `scope :active, -> { where(needs_reauth: false) }` — used
    by the orchestrator iteration.
  - No new instance methods.
- `app/models/youtube_api_call.rb`:
  - No schema change. Add a class constant `KIND_ANALYTICS_V2 = "analytics_v2"`
    for clarity (the audit calls reference it). The existing `KIND_DATA_V3`
    (Phase 7) lives next to it.

### Configuration

- `config/sidekiq.yml` (or `config/initializers/sidekiq.rb` — agent picks per
  existing pattern):
  - Add cron entry: `youtube_analytics_sync_nightly` — schedule `"0 4 * * *"`
    (UTC) — class `YoutubeAnalyticsSync` — args `[]`.
  - Add cron entry: `youtube_analytics_retention_weekly` — schedule
    `"0 5 * * 1"` (UTC, Monday) — class `VideoRetentionSyncOrchestrator` — args
    `[]`. (See note below — orchestrator for retention-only run is a thin
    wrapper around `YoutubeAnalyticsSync.perform_async(retention_only: true)`.)
- The cron entries land under sidekiq-cron's existing config surface.
  Implementation agent verifies the project already has sidekiq-cron wired (it
  does; `Gemfile` has `gem "sidekiq-cron"`).

### Tests (new — see Test sweep below)

Per the test sweep section below.

### Documentation (post-implementation; dispatched separately to docs-keeper)

- `docs/architecture.md` — add an "Analytics sync engine" section pointing at
  this spec; describe the orchestrator → child-job topology.
- `CLAUDE.md` — note the new sidekiq-cron entries in the Architecture-notes
  section if/when entries-list documentation is appropriate. The agent drafts;
  user reviews.

These edits are NOT part of the rails-impl dispatch's file scope.

## Job topology

```
YoutubeAnalyticsSync (cron 04:00 UTC)
  └─ for each YoutubeConnection.active:
       ChannelAnalyticsSync(channel_id) ── for each channel under the connection
         ├─ C1 channel daily (refresh last 3 days)
         ├─ C2 channel window summary (4 windows)
         ├─ C3 top videos (4 windows × 50 videos each)
         ├─ C4 channel geography  ← currently no-op (open question)
         └─ C5 channel demographics ← currently no-op (open question)
       VideoAnalyticsSync(video_id) ── for each ACTIVE video under the connection
         ├─ V1 video daily (refresh last 3 days)
         ├─ V2 video window summary (4 windows)
         ├─ V3 video by country
         ├─ V4 video by device + OS (two API calls)
         ├─ V5 video by traffic source
         ├─ V6 video by subscribed status
         └─ V8 video demographics
       VideoAnalyticsSync(video_id) ── for each INACTIVE video
         └─ V1 only

VideoRetentionSyncOrchestrator (cron 05:00 UTC Monday)
  └─ for each YoutubeConnection.active:
       VideoRetentionSync(video_id) ── for each ACTIVE video
         └─ V7 retention curve

On-demand (button on dashboard):
  VideoAnalyticsSync.perform_async(video_id)  -- runs V1-V8 inline
  VideoRetentionSync.perform_async(video_id)  -- if retention is also requested

Backfill (Rails console / rake):
  Backfill::AnalyticsRange.call(connection: ..., from: ..., to: ...)
    → enqueues N ChannelAnalyticsSync + M VideoAnalyticsSync jobs
```

## Error handling matrix

| Error class                                          | Translated to    | Action                                                                                         |
| ---------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------- |
| `Google::Apis::AuthorizationError` (401)             | `AuthError`      | Set `connection.needs_reauth = true`. Audit `outcome: 'auth_failed'`. SKIP rest of connection. |
| `Google::Apis::RateLimitError` (429)                 | `RateLimitError` | Sidekiq retry with exponential backoff (Q8 schedule). Audit `outcome: 'rate_limited'`.         |
| `Google::Apis::ServerError` (5xx)                    | `TransientError` | Sidekiq retry. Audit `outcome: 'failed'` with `error_class`.                                   |
| `Google::Apis::ClientError` (4xx other than 401/429) | `PermanentError` | NO retry. Log + audit + raise. Sidekiq dead-letter.                                            |
| `Errno::ETIMEDOUT`, `Faraday::TimeoutError`          | `TransientError` | Sidekiq retry.                                                                                 |
| Malformed JSON / unexpected response shape           | `PermanentError` | NO retry. Log + audit + raise.                                                                 |

The job-level `perform` rescues `AuthError` to skip the rest of the connection's
work without failing the job (other connections proceed). All other typed
exceptions bubble up so Sidekiq retry logic applies.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies:

### Files

- [ ] `app/jobs/youtube_analytics_sync.rb` exists with the orchestrator.
- [ ] `app/jobs/channel_analytics_sync.rb` exists.
- [ ] `app/jobs/video_analytics_sync.rb` exists.
- [ ] `app/jobs/video_retention_sync.rb` exists.
- [ ] `app/services/youtube/analytics_client.rb` exists with all 13 public
      methods listed in **Files touched**.
- [ ] `app/services/youtube/analytics_query_builder.rb` exists with 14
      pure-function methods (one per Note 3 query).
- [ ] `app/services/youtube/active_video_classifier.rb` exists.
- [ ] `app/services/backfill/analytics_range.rb` exists.

### Models

- [ ] `YoutubeConnection.active` scope returns connections with
      `needs_reauth: false`.

### Configuration

- [ ] `config/sidekiq.yml` (or sidekiq-cron config file) declares
      `youtube_analytics_sync_nightly` at `"0 4 * * *"`.
- [ ] Same file declares `youtube_analytics_retention_weekly` at `"0 5 * * 1"`.
- [ ] Loading the Rails app does NOT enqueue any jobs at boot (the cron schedule
      is registered, not triggered).
- [ ] `Sidekiq::Cron::Job.find("youtube_analytics_sync_nightly")` returns a
      registered job after boot.

### Behavior

- [ ] On nightly run, the orchestrator iterates every `YoutubeConnection.active`
      and enqueues a `ChannelAnalyticsSync` per channel under each connection.
- [ ] `ChannelAnalyticsSync` issues the C1-C3 calls and writes `channel_daily` /
      `channel_window_summary` / `top_videos_window` rows.
- [ ] `VideoAnalyticsSync` for an active video issues V1, V2 (×4 windows), V3,
      V4-device, V4-os, V5, V6, V8 — eight API calls — and writes rows to the
      corresponding tables.
- [ ] `VideoAnalyticsSync` for an inactive video issues V1 only.
- [ ] `VideoRetentionSync` issues V7 and writes `video_retention` rows.
- [ ] On HTTP 401, `connection.needs_reauth` flips to `true` and an audit row is
      written with `outcome: 'auth_failed'`.
- [ ] On HTTP 429, the job retries with backoff per Q8.
- [ ] On HTTP 5xx, the job retries with backoff.
- [ ] On other HTTP 4xx, the job dead-letters (no retry).
- [ ] An audit row writes for every API call, success or failure, with
      `client_kind: 'analytics_v2'`.
- [ ] Idempotency: re-running the orchestrator for the same date range does NOT
      create duplicate rows; existing rows update via `upsert_all`.
- [ ] Active-video classifier returns true for a video published 60 days ago,
      false for one published 100 days ago with no recent views.
- [ ] Active-video classifier returns true for a video with > 100 views in the
      last 7 days even if published 1 year ago.

### Cross-cutting

- [ ] No `Current.tenant` reference. (Phase 8 already excised; this spec
      verifies.)
- [ ] No `tenant_id` parameter on any service method.
- [ ] Every external boundary uses `"yes"` / `"no"` for booleans where booleans
      cross the boundary (per CLAUDE.md hard rule). Internal Booleans stay
      Boolean.
- [ ] Secrets (`monetization_enabled` flag, OAuth client secret used by the
      underlying Google client) live in `Rails.application.credentials`.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] All test cases enumerated below pass.
- [ ] No real network calls in the test suite (WebMock stubs every
      `youtubeanalytics.googleapis.com/v2/reports` endpoint).

## Test sweep

Exhaustive coverage. The implementation agent owns the full sweep. Total
enumerated test cases counted at the end.

### Specs to add

#### `spec/services/youtube/analytics_query_builder_spec.rb`

Pure function. No fixtures beyond plain strings + dates.

- **C1 channel daily:**
  - `it "builds C1 params with the documented metric set"` — assert every metric
    name in Note 3's C1 list appears.
  - `it "uses dimensions=day"`.
  - `it "uses ids=channel==<youtube_channel_id>"`.
  - `it "formats start_date / end_date as YYYY-MM-DD"`.
  - `it "omits non-summable metrics"` — assert `averageViewPercentage` is NOT in
    the metric list.
  - `it "omits revenue metrics when monetization disabled"`.
  - `it "appends revenue metrics when monetization enabled"`.

- **C2 channel window summary:**
  - `it "builds C2 params with no dimensions"`.
  - `it "appends the four non-summable ratios"` — `averageViewPercentage`,
    `videoThumbnailImpressionsClickRate`, `cardClickRate`,
    `cardTeaserClickRate`.
  - `it "appends revenue ratios when monetization enabled"` (`cpm`,
    `playbackBasedCpm`).
  - `it "computes window_start from window value"` — for each of the four
    windows, assert the start date is correct.
  - `it "rejects unknown window value"` — passing `'14d'` raises.

- **C3 top videos:**
  - `it "uses dimensions=video"`.
  - `it "appends sort=-estimatedMinutesWatched"`.
  - `it "caps maxResults to 50 by default"`.
  - `it "respects a custom limit up to 200"` — Note 3's max.
  - `it "rejects limit > 200"`.

- **C4 channel geography (no-op stub today, but the builder method exists):**
  - `it "builds C4 params with dimensions=country"`.
  - `it "uses ids=channel==<id>"`.

- **C5 channel demographics:**
  - `it "builds C5 params with dimensions=ageGroup,gender"`.
  - `it "uses metrics=viewerPercentage"`.

- **V1 video daily:**
  - `it "appends filters=video==<youtube_video_id>"`.
  - `it "shares the C1 metric / dimension shape"`.

- **V2 video window summary:**
  - `it "appends filters=video==<id>"`.
  - `it "shares the C2 metric shape"`.

- **V3 video by country:**
  - `it "appends filters=video==<id>"`.
  - `it "uses dimensions=country"`.
  - `it "uses metrics=views,estimatedMinutesWatched, averageViewDuration,averageViewPercentage"`.

- **V4 video by device:**
  - `it "uses dimensions=deviceType (single)"`.
  - `it "uses dimensions=operatingSystem (single)"` — separate method.

- **V5 video by traffic source:**
  - `it "uses dimensions=insightTrafficSourceType"`.

- **V6 video by subscribed status:**
  - `it "uses dimensions=subscribedStatus"`.

- **V7 retention:**
  - `it "uses dimensions=elapsedVideoTimeRatio"`.
  - `it "uses metrics=audienceWatchRatio,relativeRetentionPerformance, startedWatching,stoppedWatching,totalSegmentImpressions"`.
  - `it "rejects multiple video IDs"` — V7 accepts a single video filter only
    (Note 3 §"Mutual-exclusion gotchas" §3).

- **V8 video demographics:**
  - `it "uses dimensions=ageGroup,gender"`.
  - `it "uses metrics=viewerPercentage"`.

- **Mutual-exclusion enforcement:**
  - `it "raises when liveOrOnDemand + averageViewPercentage are both requested"`
    — Note 3 §1.
  - `it "raises when day + month are both requested as time dimensions"` — Note
    3 §2.

Total: **38** test cases.

#### `spec/services/youtube/analytics_client_spec.rb`

Use WebMock to stub `youtubeanalytics.googleapis.com`. Or use the gem's test
double helpers if `google-apis-youtube_analytics_v2` ships them. The
implementation agent picks; the spec encodes the assertions.

- **Construction:**
  - `it "accepts a YoutubeConnection"`.
  - `it "uses the connection's encrypted access_token"` — assert the request's
    `Authorization: Bearer <token>` header.
  - `it "refreshes the token when the access_token has expired"` — follows the
    existing `Youtube::Client` pattern.

- **Happy path — channel_daily:**
  - `it "returns parsed attribute-hashes for ChannelDaily upsert"`.
  - `it "writes a youtube_api_calls audit row with outcome: 'ok'"`.
  - `it "writes the row with client_kind: 'analytics_v2'"`.
  - `it "writes the request's dimensions and metrics into the audit row"`.
  - `it "captures latency_ms"`.

- **Happy path — every method:** one case per `analytics_client` public method
  (13 methods minus the two no-op stubs C4 / C5 = 11 happy-path cases). Each:
  - `it "<method> returns parsed rows on a 200 response"` — agent picks
    representative fixtures.

- **Sad path — auth failure:**
  - `it "raises AuthError on HTTP 401"`.
  - `it "flips connection.needs_reauth to true on AuthError"`.
  - `it "writes an audit row with outcome: 'auth_failed'"`.
  - `it "does not retry on AuthError"` — assert sidekiq does not requeue
    (job-level test).

- **Sad path — rate limit:**
  - `it "raises RateLimitError on HTTP 429"`.
  - `it "writes an audit row with outcome: 'rate_limited'"`.
  - `it "Sidekiq retries on RateLimitError"`.

- **Sad path — server error:**
  - `it "raises TransientError on HTTP 5xx"`.
  - `it "writes an audit row with outcome: 'failed'"`.
  - `it "Sidekiq retries on TransientError"`.

- **Sad path — client error other than 401/429:**
  - `it "raises PermanentError on HTTP 400"`.
  - `it "Sidekiq does NOT retry on PermanentError"`.

- **Sad path — network timeout:**
  - `it "raises TransientError on Faraday::TimeoutError"`.
  - `it "writes an audit row with outcome: 'failed'"`.

- **Sad path — malformed response:**
  - `it "raises PermanentError on a response missing the rows key"`.
  - `it "raises PermanentError on a response with mismatched columnHeaders / rows shape"`.

- **No-op stubs (C4 / C5):**
  - `it "channel_geography raises NotImplementedError"`.
  - `it "channel_demographics raises NotImplementedError"`.

- **Pacific Time handling:**
  - `it "formats start_date / end_date in YYYY-MM-DD against PT day boundaries"`
    — pass `from = today_pt - 3, to = today_pt - 1`; assert the request's
    `startDate` / `endDate` strings match.

Total: **34** test cases (11 happy-path + the variants above).

#### `spec/services/youtube/active_video_classifier_spec.rb`

- `it "active? is true for a video published within 90 days"`.
- `it "active? is false for a video published > 90 days ago and no recent views"`.
- `it "active? is true for a video with > 100 views in the last 7 days regardless of age"`.
- `it "active? at the boundary — exactly 100 views in 7 days"`.
- `it "active? at the boundary — exactly 90 days old"` — inclusive vs exclusive
  boundary; spec encodes the choice (recommendation: inclusive —
  `published_at >= 90.days.ago` passes for exactly-90-days).
- `it "active_for(connection) returns videos belonging to the connection's channels"`.
- `it "active_for(connection) excludes videos under other connections"`.
- `it "active_for(connection) does not return non-Active videos"`.

Total: **8** test cases.

#### `spec/services/backfill/analytics_range_spec.rb`

- `it "enqueues ChannelAnalyticsSync for every channel under the connection in the date range"`.
- `it "enqueues VideoAnalyticsSync for every active video under the connection"`.
- `it "respects the channels: scope filter"` — only enqueue for the named
  channels.
- `it "respects the videos: scope filter"`.
- `it "returns the count of enqueued jobs"`.
- `it "raises when from > to"` — date range invariant.
- `it "raises when connection is not active"` — refuse to backfill a
  reauth-needed connection.

Total: **7** test cases.

#### `spec/jobs/youtube_analytics_sync_spec.rb`

- **Iteration:**
  - `it "iterates every YoutubeConnection.active"`.
  - `it "skips connections with needs_reauth: true"`.
- **Dispatch:**
  - `it "enqueues a ChannelAnalyticsSync per channel under each active connection"`.
  - `it "enqueues a VideoAnalyticsSync per active video under each active connection"`.
- **Retention-only mode:**
  - `it "when called with retention_only: true, enqueues only VideoRetentionSync jobs"`.
- **Concurrency safety:**
  - `it "is idempotent on a re-run"` — running the orchestrator twice for the
    same wall-clock day enqueues the same set; downstream job upserts
    deduplicate.
- **Audit:**
  - `it "logs the start and finish to Rails.logger"`.

Total: **8** test cases.

#### `spec/jobs/channel_analytics_sync_spec.rb`

- **Happy:**
  - `it "fetches C1 for the channel and upserts ChannelDaily rows"`.
  - `it "fetches C2 for each window and upserts ChannelWindowSummary rows"`.
  - `it "fetches C3 for each window and upserts TopVideosWindow rows"`.
  - `it "uses today_pt - 3 to today_pt - 1 as the C1 fetch range"`.
- **Sad:**
  - `it "skips remaining channels when AuthError is raised mid-run"` — the job
    rescues, sets needs_reauth, continues silently within the job (the
    orchestrator is responsible for aborting).
  - Wait — re-read this. The orchestrator dispatches per-channel jobs; each is
    independent. When a per-channel job hits AuthError, the job sets
    `needs_reauth: true` and exits cleanly (the orchestrator has already
    enqueued every channel; subsequent per-channel jobs for the same connection
    see `needs_reauth: true` and exit early).
  - Restate: `it "exits early when the connection's needs_reauth is true"`.
  - `it "sets connection.needs_reauth on AuthError and exits the job cleanly"`.
- **Idempotency:**
  - `it "does not duplicate ChannelDaily rows on a re-run"`.
  - `it "does not duplicate ChannelWindowSummary rows on a re-run"`.
  - `it "does not duplicate TopVideosWindow rows on a re-run"`.
  - `it "rebuilds TopVideosWindow rows correctly when the leaderboard membership changes"`
    — rank values are recomputed; old rows for fallen-off videos are deleted.

Total: **9** test cases.

#### `spec/jobs/video_analytics_sync_spec.rb`

- **Happy — active video:**
  - `it "fetches V1 and upserts VideoDaily rows"`.
  - `it "fetches V2 for each window and upserts VideoWindowSummary rows"`.
  - `it "fetches V3 and upserts VideoDailyByCountry rows"`.
  - `it "fetches V4 (deviceType) and upserts VideoDailyByDeviceType rows"`.
  - `it "fetches V4 (operatingSystem) and upserts VideoDailyByOperatingSystem rows"`.
  - `it "fetches V5 and upserts VideoDailyByTrafficSource rows"`.
  - `it "fetches V6 and upserts VideoDailyBySubscribedStatus rows"`.
  - `it "fetches V8 and upserts VideoDailyByAgeGroupGender rows"`.
- **Happy — inactive video:**
  - `it "fetches V1 only and skips V2-V8 for inactive videos"`.
- **Sad:**
  - `it "exits early when the connection's needs_reauth is true"`.
  - `it "sets connection.needs_reauth on AuthError and exits cleanly"`.
- **Idempotency:** one case per slice table.
- **Edge — empty response:**
  - `it "writes no rows when the API returns no data for a date range"`.

Total: **17** test cases (8 slices + 1 inactive + 2 sad + 5 idempotency

- 1 empty).

#### `spec/jobs/video_retention_sync_spec.rb`

- `it "fetches V7 for the video and upserts VideoRetention rows"`.
- `it "writes computed_at to the current time"`.
- `it "rejects multiple-video filters at the query-builder level"` — inherits
  from query builder; this spec asserts the integration.
- `it "exits early when the connection's needs_reauth is true"`.
- `it "is idempotent on a re-run for the same video"` — old rows update; no
  duplicates.
- `it "does NOT run V7 when the video has < 100 segment_impressions in prior runs"`
  — open question; if the user wants this guard, encode it; if not, skip the
  case. **Architect recommendation: skip this guard; V7 always runs for active
  videos.**

Total: **5** test cases (excluding the open-question case).

#### `spec/integration/analytics_full_sync_spec.rb` (request-style integration)

End-to-end against WebMock-stubbed Google API:

- `it "from empty state, runs the orchestrator and populates every analytics table for one connection / one channel / two videos (one active, one inactive)"`
  — single big integration test that exercises every per-row write.
- `it "on a second nightly run, only updates rows for the 3-day refresh window; older rows untouched"`.
- `it "when one connection's token expires mid-run, that connection's channels stop syncing but other connections proceed"`.
- `it "when the API returns 429 on one query, the job retries and succeeds on the second attempt"`
  — uses Sidekiq inline mode + WebMock sequencing (`to_return` with
  `[429-response, 200-response]`).
- `it "writes a youtube_api_calls audit row for every API call (happy AND sad)"`
  — count assertions.
- `it "monetization-disabled mode: revenue columns stay NULL on every row"` —
  assert `channel_daily.estimated_revenue.nil?` after a sync.
- `it "monetization-enabled mode: revenue columns get values"` — flip the flag,
  re-run, assert non-nil.

Total: **7** test cases.

### Flaw / smuggle tests

#### `spec/services/youtube/analytics_client_flaw_spec.rb`

- `it "ignores a smuggled connection_id parameter"` — call
  `analytics_client.channel_daily(channel: c)` with extra params; the client's
  request uses only the constructor's connection.
- `it "uses only the constructor's connection.access_token, never a cached one"`.
- `it "rejects a channel that does not belong to the constructor's connection"`
  — assertion: passing a foreign channel raises `ArgumentError`. The
  connection-channel relationship is implicit via
  `Channel.youtube_connection_id`; the analytics client validates.
- `it "writes audit rows under the constructor's connection_id, not the channel's connection_id (defense-in-depth — they should match, but the audit honors the source-of-truth)"`.

Total: **4** test cases.

#### `spec/jobs/concurrent_sync_spec.rb`

- `it "two concurrent ChannelAnalyticsSync jobs for the same channel do not deadlock"`
  — `upsert_all` handles concurrent writes via Postgres' uniqueness conflict
  resolution.
- `it "two concurrent VideoAnalyticsSync jobs for the same video do not duplicate rows"`.

Total: **2** test cases.

### Test count summary

| Spec file                                               | New cases |
| ------------------------------------------------------- | --------- |
| `spec/services/youtube/analytics_query_builder_spec.rb` | 38        |
| `spec/services/youtube/analytics_client_spec.rb`        | 34        |
| `spec/services/youtube/active_video_classifier_spec.rb` | 8         |
| `spec/services/backfill/analytics_range_spec.rb`        | 7         |
| `spec/jobs/youtube_analytics_sync_spec.rb`              | 8         |
| `spec/jobs/channel_analytics_sync_spec.rb`              | 9         |
| `spec/jobs/video_analytics_sync_spec.rb`                | 17        |
| `spec/jobs/video_retention_sync_spec.rb`                | 5         |
| `spec/integration/analytics_full_sync_spec.rb`          | 7         |
| `spec/services/youtube/analytics_client_flaw_spec.rb`   | 4         |
| `spec/jobs/concurrent_sync_spec.rb`                     | 2         |
| **Total NEW test cases**                                | **139**   |

## Manual playbook (post-implementation)

Architect outlines; reviewer fills in remaining steps after spec lands.

1. **Confirm the data model is in place.** Per spec 01's playbook, every
   analytics table exists, every model loads.
2. **Confirm credentials.**
   `bin/rails credentials:edit --environment development`. Verify the YouTube
   OAuth client_id / client_secret are set (Phase 7 surface — already done if
   Phase 7 lands). Verify `youtube.monetization_enabled` is unset (or `false`).
3. **Connect a YouTube channel.** Visit `/settings/youtube`. Run the OAuth dance
   (Phase 9 surface). Confirm `YoutubeConnection.count >= 1` and the connection
   has `needs_reauth: false`.
4. **Trigger a manual analytics sync.**
   ```bash
   bin/rails runner 'YoutubeAnalyticsSync.perform_async'
   ```
   Or:
   ```bash
   bin/rails runner 'YoutubeAnalyticsSync.new.perform'
   ```
   (synchronous mode for visibility). Watch the Sidekiq log; expect a chain of
   `ChannelAnalyticsSync` + `VideoAnalyticsSync` enqueues.
5. **Confirm rows wrote.** `psql` into the development DB:
   ```sql
   SELECT count(*) FROM channel_daily;
   SELECT count(*) FROM video_daily;
   SELECT count(*) FROM video_daily_by_country;
   SELECT count(*) FROM channel_window_summary;
   SELECT count(*) FROM video_window_summary;
   SELECT count(*) FROM top_videos_window;
   ```
   Each non-zero. Counts depend on the channel's data.
6. **Confirm audit rows.**
   ```sql
   SELECT client_kind, outcome, count(*) FROM youtube_api_calls
   GROUP BY client_kind, outcome;
   ```
   Expect rows with `client_kind = 'analytics_v2'` and `outcome = 'ok'`.
7. **Test the on-demand refresh path.**
   ```bash
   bin/rails runner 'VideoAnalyticsSync.perform_async(Video.first.id)'
   ```
   Watch the log; confirm V1-V8 fire for that one video.
8. **Test the retention sync.**
   ```bash
   bin/rails runner 'VideoRetentionSync.perform_async(Video.first.id)'
   ```
   Confirm `video_retention.where(video_id: <id>).count` is roughly 100 (Note
   3's expected ~100 buckets per video).
9. **Test backfill.**
   ```bash
   bin/rails runner 'Backfill::AnalyticsRange.call(connection:
     YoutubeConnection.first, from: 30.days.ago.to_date, to:
     1.day.ago.to_date)'
   ```
   Watch Sidekiq enqueue jobs; let them run; confirm 30 days of rows land in
   `channel_daily`.
10. **Test the auth-failure path.** Manually flip a connection's `access_token`
    to garbage:
    ```bash
    bin/rails runner 'YoutubeConnection.first.update!(access_token:
      "invalid")'
    ```
    Run the orchestrator. Confirm:
    - `needs_reauth = true` after the run.
    - Audit rows include `outcome = 'auth_failed'`.
    - Other connections (if any) processed normally. Then re-OAuth via Settings
      → YouTube to restore.
11. **Confirm sidekiq-cron entries.** Visit `/sidekiq/cron` (HTTP basic auth).
    Confirm two entries:
    - `youtube_analytics_sync_nightly` at `0 4 * * *`.
    - `youtube_analytics_retention_weekly` at `0 5 * * 1`. Both `enabled: true`.
12. **Run the full RSpec suite.**
    ```bash
    bundle exec rspec
    ```
    Confirm green.
13. **Run rubocop / brakeman.** Both clean (or no new violations).

## Cross-stack scope

| Surface           | Status                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane. Jobs, services, configuration.                                                                                            |
| MCP rack app      | **Skipped.** No MCP tools for analytics in this dispatch. A future spec adds `analytics_*` tools (per the master agent's MCP catalog expansion plan). |
| Doorkeeper        | **N/A.**                                                                                                                                              |
| `pito` CLI (Rust) | **Skipped.** CLI parity for the on-demand "refresh this video" button is a deferred follow-up.                                                        |
| Astro / website   | **N/A.**                                                                                                                                              |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Audit log event keys for analytics calls.** New keys land for the audit
   rows:
   - `youtube_analytics.query.succeeded`
   - `youtube_analytics.query.rate_limited`
   - `youtube_analytics.query.auth_failed`
   - `youtube_analytics.query.failed` User confirms or picks alternatives.
2. **Logger output format.** When the orchestrator runs, what should it log?
   Suggested:
   - Start: `"[analytics-sync] starting nightly run; <N> active connections"`.
   - Finish: `"[analytics-sync] complete; <duration>s"`.
   - Auth failure:
     `"[analytics-sync] connection <id> failed auth;   marking needs_reauth"`.
     User confirms.
3. **Sidekiq cron job names.** Picked:
   - `youtube_analytics_sync_nightly`
   - `youtube_analytics_retention_weekly` User confirms.
4. **Backfill rake task name.** If a rake wrapper around
   `Backfill::AnalyticsRange.call` is wanted (so a developer can run
   `bin/rails analytics:backfill[connection_id, from, to]` from the shell), name
   it. Suggested: `analytics:backfill`. User confirms or skips the rake wrapper
   entirely.
5. **`needs_reauth` user-facing copy.** When the dashboard surfaces "this
   connection failed authentication on the last analytics run," the message
   wording is a spec-03 question. Surfaced here for completeness; spec 03 is the
   consumer.

## Open questions (architect cannot decide; master agent surfaces to

user)

1. **C4 channel geography + C5 channel demographics — should spec 01 gain
   dedicated tables?** Today, no `channel_daily_by_country` /
   `channel_daily_by_age_group_gender` exist. The dashboard (spec 03) can
   compute channel-level rollups by SUM-aggregating across the channel's videos'
   slice tables. Tradeoff: per-channel slice tables are extra schema and extra
   sync but give Studio-faithful values (the channel-level Analytics API
   endpoint may slightly differ from summing video-level slices).
   Recommendation: defer; rollup at query time in spec 03; if
   Studio-faithfulness becomes a problem, add the tables in a follow-up. The
   analytics client's C4 / C5 methods stay as `NotImplementedError` stubs in
   this spec. User confirms.
2. **Active-video classification should it cache the result on the `videos`
   row?** Pure-function classification is recomputed on every nightly
   orchestrator pass. For a 1000-video channel that's 1000
   `EXISTS (SELECT 1 FROM video_daily ...)` queries. Negligible at pito's scale.
   Recommendation: stay pure; do not add a column. User confirms.
3. **Backfill concurrency.** `Backfill::AnalyticsRange.call` enqueues N jobs in
   one shot. For a 5-year backfill on a 1000-video channel that's 5000+ jobs.
   Sidekiq handles the queue volume; the YouTube Analytics API has its own
   quota. Recommendation: rely on the existing rate-limit retry logic; do NOT
   throttle from the application side. User confirms.
4. **Logging verbosity.** Per-API-call logs at info or debug? At pito's scale (1
   connection × 200 active videos × 8 calls/video = 1600 calls/night) info-level
   is noisy. Recommendation: debug for each call; info for orchestrator
   start/finish; warn for auth failures. User confirms.
5. **Sidekiq queue separation.** Should analytics jobs land on a dedicated
   `analytics` queue rather than `default`? Pros: isolates the bulk of nightly
   load from interactive jobs (channel sync, footage imports). Cons: another
   queue to monitor. Recommendation: separate queue named `analytics`; processed
   alongside `default` by the same Sidekiq workers (no concurrency limit
   difference). User confirms.
6. **Active-video boundary inclusivity.** Note 3 says "uploaded in last 90 days
   OR > 100 views in last 7 days." Does "last 90 days" include today, day 90, or
   only days < 90? Recommendation: inclusive of day 90
   (`published_at >= 90.days.ago`); >100 views means strictly >100, not ≥100.
   User confirms.
7. **`Youtube::AnalyticsClient` vs `Youtube::Client` reuse.** The existing
   `Youtube::Client` (Phase 7) wraps the Data API v3. The analytics client is a
   separate concern (different API endpoint, different rate limit). Question:
   share the OAuth-token-refresh plumbing or duplicate. Recommendation: extract
   a shared module (`Youtube::OauthRefresh` or similar) and include it in both
   clients. The implementation agent owns the extraction; surface as a follow-up
   if more refactor than feasible in this dispatch.
8. **`Rails.application.credentials.youtube.monetization_enabled` vs
   AppSetting.** AppSetting is the existing surface for runtime-flippable flags
   (`max_panes`, `pane_title_length`, `theme`). Credentials is for secrets.
   Monetization-enabled is a flag, not a secret. Recommendation: AppSetting.
   User confirms; if AppSetting, the spec adds a small migration to seed the row
   with `false`. Per "Migration posture (LOCKED)", this spec is code-only — so
   the AppSetting row gets seeded in `db/seeds.rb` (idempotent insert), not via
   a migration.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. **Audit log event keys.** Architect's four keys verbatim:
   - `youtube_analytics.query.succeeded`
   - `youtube_analytics.query.rate_limited`
   - `youtube_analytics.query.auth_failed`
   - `youtube_analytics.query.failed`
2. **Logger output format.** Architect's templates verbatim:
   - Start: `[analytics-sync] starting nightly run; <N> active connections`
   - Finish: `[analytics-sync] complete; <duration>s`
   - Auth failure:
     `[analytics-sync] connection <id> failed auth; marking needs_reauth`
3. **Sidekiq cron job names.** `youtube_analytics_sync_nightly` and
   `youtube_analytics_retention_weekly`.
4. **Backfill rake task.** Yes, ship
   `analytics:backfill[connection_id, from, to]`. Useful for manual recovery
   after a connection re-authorization.
5. **`needs_reauth` dashboard copy.** Deferred to Spec 03 (the consumer).

### Open-question decisions

1. **C4 + C5 channel-level slice tables.** Defer. Rollup happens at query time
   in Spec 03. The analytics client's C4 / C5 methods stay as
   `NotImplementedError` stubs in this spec.
2. **Active-video classification — cache the result?** No cache. Pure function
   recomputed each pass.
3. **Backfill concurrency.** No app-side throttle. Rely on the rate-limit retry
   logic.
4. **Logging verbosity.** `debug` per-API-call; `info` for orchestrator
   start/finish; `warn` for auth failures.
5. **Sidekiq queue separation.** Yes — dedicated `analytics` queue, processed by
   the same workers as `default` (no concurrency-limit difference).
6. **Active-video boundary.** Inclusive: `published_at >= 90.days.ago`. Views
   threshold is strictly `> 100`, not `>= 100`.
7. **`Youtube::AnalyticsClient` + `Youtube::Client` shared OAuth refresh.**
   Extract a `Youtube::OauthRefresh` shared module; include it in both clients.
8. **Monetization flag location.** AppSetting (not credentials). Seed via
   `db/seeds.rb` idempotent insert (the seed creates the row with
   `monetization_enabled: false` if missing).

## Non-goals (explicit)

- **Data model.** Spec 01.
- **Dashboard views.** Spec 03.
- **MCP tools for analytics.** Future spec.
- **CLI parity.** Future follow-up.
- **Channel sync (Data API v3 channel metadata).** Phase 11 surface.
- **Video sync (Data API v3 video metadata).** Phase 12 surface.
- **Live broadcast analytics (V9).** Per Q18; future spec.
- **Playlist analytics.** YouTube revision-history dependency.
- **Game analytics attribution (`video_game_link`).** Future spec; the game
  model itself is unfinished.
- **Notifications when a sync fails.** Calendar / notifications phase (work unit
  8 in the realignment doc).
- **Custom user-picked windows beyond 7d / 28d / 90d / lifetime.** Per Note 3
  §"Windowing" — the dashboard can compute custom windows from `video_daily`
  SUMs but the windowed-summary tables stay locked to the four canonical
  windows.

## Implementation lane assignment

Single lane: **rails-impl**. Touches:

- `app/jobs/`
- `app/services/youtube/`
- `app/services/backfill/`
- `app/models/youtube_connection.rb` (scope add)
- `app/models/youtube_api_call.rb` (constant add)
- `config/sidekiq.yml` (or `config/initializers/sidekiq.rb`)
- `db/seeds.rb` (if Q8 / monetization AppSetting wins — agent confirms)
- `spec/services/`, `spec/jobs/`, `spec/integration/`

No `extras/cli/`, no `extras/website/`, no `app/controllers/`, no `app/views/`,
no `db/migrate/`, no `docs/`.

## Reviewer checkpoints (post-implementation)

1. `git grep 'tenant_id\|Current\.tenant' app/jobs/ app/services/youtube/ app/services/backfill/`
   → zero matches.
2. `git grep 'YoutubeConnection\|youtube_connection' app/jobs/ app/services/youtube/`
   → many matches, all canonical.
3. `bin/rails runner 'puts Sidekiq::Cron::Job.all.map(&:name).sort'` → includes
   `youtube_analytics_sync_nightly` and `youtube_analytics_retention_weekly`.
4. `bundle exec rspec spec/services/youtube/ spec/services/backfill/ spec/jobs/ spec/integration/analytics_full_sync_spec.rb`
   → green.
5. `bundle exec rspec` → full suite green.
6. `bundle exec rubocop` → clean.
7. `bundle exec brakeman -q` → clean.
8. Manual playbook §1-§13.
9. Spec count delta logged in `docs/plans/beta/13-analytics-sync-engine/log.md`.
