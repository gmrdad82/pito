# Phase 8 — YouTube Data Sync

> **Goal:** Replace fake seed data with real YouTube data. Auto-sync owned
> channels via OAuth on a schedule. Sync external (non-owned) channels on demand
> via the public API key. Track quota usage against the audit table from
> Phase 7. Build resilient, idempotent sync jobs that don't burn quota on no-ops
> or duplicate records.

**Depends on:** Phase 7 (OAuth + `YouTube::Client` + quota tracking via
`YoutubeApiCall`).

**Unblocks:** Phase 9 (KB notes attach to real videos), Phase 10 (embeddings
have real content to embed), Phase 11 (workflow features against real data),
Phase 13 (observability charts have real metrics to display).

---

## Why Phase 8 is now

Phase 7 proved the connection works. Phase 8 industrializes it. By the end of
this phase, the user's actual YouTube data lives in Pito and refreshes
automatically. Every later phase assumes real data.

The phase splits cleanly into two paths with different operational
characteristics:

1. **Owned channel sync** — uses OAuth identities, runs on schedule (daily for
   stats, on-demand for manifest changes), can use deeper data (Analytics API)
2. **External channel sync** — uses public API key, on-demand only (user pastes
   a channel URL or video URL; Pito fetches public-only data), shallower data
   set

Different quota pools, different schedules, same `Channel` / `Video` /
`VideoStat` data shape. The sync jobs are the same shape too — just instantiated
with `YouTube::Client` (OAuth) or `YouTube::PublicClient` (API key).

This is also the phase where seed data deprecation begins. Real data and seeds
coexist (each record carries a `seeded` flag). The user can purge fake data when
ready, or keep them around for reproducible specs.

---

## In scope

### Schema additions

- Add `external` boolean (default `false`), `last_synced_at` timestamp to
  `Channel`. The Phase 7 column `connected` already exists.
- Add `seeded` boolean (default `false`) to all data tables — `Channel`,
  `Video`, `VideoStat`, `Playlist`, `PlaylistItem`, etc. Existing seeded rows
  get backfilled to `true`.
- Add `last_synced_at`, `seeded` to `Video`. Plus any YouTube-specific columns
  that Alpha didn't establish or that are incomplete: `published_at`,
  `duration_seconds`, `definition` (`hd`/`sd`), `caption_status`,
  `licensed_content` (verify against current schema; add what's missing).
- Verify `VideoStat` has `recorded_on` (date) with a `(video_id, recorded_on)`
  unique index. Time-series rows; one per video per day.
- For external channels: extend `Channel` with `youtube_channel_id` (string,
  unique within `external: true` scope), `external_url` (the URL the user
  pasted, for traceability).

### Owned channel sync jobs (Sidekiq)

Each job uses `YouTube::Client` from Phase 7, scoped to a specific
`GoogleIdentity` and `Channel`. Each respects the daily quota budget; if a job's
projected cost would exceed remaining quota, it skips and reschedules for the
next day with a clear log entry.

- **`Sync::OwnedChannelMetadataJob(channel_id)`** — fetches channel snippet,
  statistics, contentDetails, branding settings; updates the `Channel` record
- **`Sync::OwnedChannelVideosJob(channel_id, since: nil)`** — fetches the
  uploads playlist, paginates through video IDs, batches `videos.list` calls (50
  IDs per call), upserts `Video` records
- **`Sync::OwnedVideoStatsJob(video_id_batch)`** — accepts a batch of video IDs,
  calls `videos.list?part=statistics`, records a `VideoStat` row per video per
  day (idempotent on `(video_id, recorded_on)`)
- **`Sync::OwnedAnalyticsJob(channel_id, date_range)`** — fetches YouTube
  Analytics (deeper data: watch time, retention, traffic sources, audience
  demographics if available)

All jobs:

- Scope by `Current.tenant` (Phase 3 pattern)
- Idempotent on re-run — `find_or_initialize_by` + assign + save
- Retry on transient errors via Sidekiq's built-in retry; surface in
  `YoutubeApiCall.outcome` for audit

### External sync jobs

External channels and videos use the public API key path sketched in Phase 7 and
finished here.

- **`Sync::ExternalChannelJob(youtube_channel_id_or_url)`** — accepts a YouTube
  channel URL or ID, parses it via a `YoutubeUrl` parser, fetches public data
  via `YouTube::PublicClient`, upserts `Channel` with `external: true`,
  `connected: false`, `oauth_identity_id: nil`
- **`Sync::ExternalVideoJob(youtube_video_id_or_url)`** — same shape but for
  individual videos. Creates the parent `Channel` record (also as external) if
  it doesn't exist.

The `YoutubeUrl` parser handles common forms: `youtube.com/channel/UC...`,
`/c/Name`, `/@handle`, `youtu.be/VIDEO_ID`, `/watch?v=VIDEO_ID`, plain IDs.
Tested edge cases documented in `challenges.md`.

External records are tagged `external: true` so the dashboard, search, and other
UI surfaces can filter or label them appropriately.

### Schedules

Use `sidekiq-cron` (or `sidekiq-scheduler` — pick one and document):

- **Owned channel metadata:** daily at 03:00 UTC
- **Owned channel videos:** daily at 03:15 UTC (after metadata is fresh)
- **Owned video stats:** daily at 04:00 UTC for "active" videos (uploaded in
  last 90 days); weekly (Sunday) for older videos to save quota
- **Owned analytics:** daily at 05:00 UTC for the last 28 days
- **External:** never scheduled. Always on-demand.

Schedules visible in Sidekiq web UI. Each scheduled job tagged so observability
(Phase 13) can group them.

### Quota awareness

- Each sync job uses `YouTube::Client` (Phase 7), which records every call to
  `YoutubeApiCall`
- Pre-job: `Quota::DailyBudget.remaining(google_identity)` returns units left
  for today; jobs check before starting
- If insufficient: skip, log "quota budget low, rescheduled for tomorrow,"
  reschedule via Sidekiq for the next day
- External jobs use a separate quota pool tracked by `YoutubeApiCall` rows where
  `google_identity_id IS NULL` (Phase 7 sentinel; consider promoting to a
  dedicated column if cleanliness demands it)

### External channel/video tracking UI

- Settings → YouTube → "Track external channel" form: URL or handle input, fetch
  button → enqueues `Sync::ExternalChannelJob`, redirects to the Channel record
  once created
- Settings → YouTube → "Track external video" form: same shape for videos
- Visible in `/channels` index with a clear `external` indicator (per the design
  language locked in Phase 4)

### Sync now buttons

- Per-channel "Sync now" button in Settings → YouTube enqueues the appropriate
  sync jobs immediately
- Per-channel show page (in the existing channel detail UI) gets a "Sync
  metadata" button
- Per-video show page gets a "Sync stats" button
- All trigger the same Sidekiq jobs that the schedules use; no separate code
  path

### Initial real-data sync command

- CLI: `bin/rails sync:full` — kicks off all owned channel syncs in sequence
  (metadata → videos → stats → analytics)
- CLI: `bin/rails sync:status` — shows per-channel sync state (last successful,
  last attempted, errors today)
- These are operational tools, not user-facing UI

### Seed data deprecation

- Existing seed records get backfilled with `seeded: true` (single migration)
- All future seed scripts also set `seeded: true` explicitly
- CLI: `bin/rails seed:purge_fake_data` — deletes all records where
  `seeded: true`. Document the flag and the cleanup command in
  `pito/docs/setup.md`.
- Settings → YouTube info banner: "You have N seed records. [Purge fake data]" —
  only shown when seeded records exist
- Real data and seeded data can coexist (e.g., during dev, the user might want
  fake records for spec reproducibility alongside their real channels). Purge is
  opt-in.

### Out of scope

- Comments / replies sync (out of Beta scope; potential Theta)
- Subscribers list (not exposed via API anyway)
- Live stream data (out of Beta)
- Sync history UI / detailed queue management (Phase 13's observability covers
  operational visibility)
- Real-time webhooks (YouTube doesn't offer them; polling only)
- YouTube Shorts-specific handling (treated as regular videos in this phase;
  differentiation can come later if useful)

---

## Plan checklist

### Schema

- [ ] Migration: add `external`, `last_synced_at` to `channels`
- [ ] Migration: add `seeded` to all data tables; backfill existing rows
- [ ] Migration: add `last_synced_at`, `seeded` to `videos`; verify
      YouTube-specific columns exist (`published_at`, `duration_seconds`,
      `definition`, `caption_status`, `licensed_content`); add what's missing
- [ ] Migration: ensure `video_stats` has `recorded_on` (date) with
      `(video_id, recorded_on)` unique index; add if missing
- [ ] Migration: extend `channels` with `youtube_channel_id`, `external_url` for
      external tracking; partial unique index on `youtube_channel_id` where
      `external: true`

### Sync jobs

- [ ] Implement `Sync::OwnedChannelMetadataJob` with VCR-backed specs covering
      metadata fetch, idempotent re-run, quota check, error paths
- [ ] Implement `Sync::OwnedChannelVideosJob` with pagination over uploads
      playlist, batched `videos.list` (50 IDs/call), idempotency, quota tracking
- [ ] Implement `Sync::OwnedVideoStatsJob` with batch input (50 video IDs/call),
      `(video_id, recorded_on)` upsert pattern
- [ ] Implement `Sync::OwnedAnalyticsJob` with Analytics API specifics; test
      with VCR cassette covering watch time, retention, traffic sources
- [ ] Implement `Sync::ExternalChannelJob` using `YouTube::PublicClient`; tag
      records as external
- [ ] Implement `Sync::ExternalVideoJob` similarly; create parent Channel as
      external if not present
- [ ] Implement `YoutubeUrl` parser with specs covering all common URL forms and
      ID-only input

### Scheduling

- [ ] Add `sidekiq-cron` to the Gemfile (pick over `sidekiq-scheduler` for
      simpler config; document choice)
- [ ] Configure schedules in `config/sidekiq_cron.yml` per the times listed
      above
- [ ] Verify schedules visible in Sidekiq web UI
- [ ] Tag scheduled jobs for observability filtering

### Quota integration

- [ ] Implement `Quota::DailyBudget` service: `.remaining(google_identity)`
      returns units left today; `.exceeded?(google_identity, projected_cost)`
      returns boolean
- [ ] Sync jobs check budget at start; skip + reschedule on insufficient
- [ ] External jobs check the separate public-key pool budget
- [ ] Specs covering pre-call check, skip-and-reschedule, budget reset at
      midnight UTC

### UI

- [ ] Settings → YouTube → "Track external channel" form (URL/handle input)
- [ ] Settings → YouTube → "Track external video" form (URL input)
- [ ] Per-channel "Sync now" buttons (Settings, channel show page)
- [ ] Per-video "Sync stats" button
- [ ] `/channels` index displays `external` indicator
- [ ] Settings → YouTube banner for seeded records with "[Purge fake data]"
      action

### CLI tooling

- [ ] `bin/rails sync:full` — kicks off all owned syncs in sequence
- [ ] `bin/rails sync:status` — per-channel sync state report
- [ ] `bin/rails seed:purge_fake_data` — destroys `seeded: true` records (with
      confirmation prompt)

### Documentation

- [ ] `pito/docs/architecture.md`: sync architecture, OAuth + public-key paths,
      schedule overview
- [ ] `pito/docs/youtube_quota.md`: update with sync-time costs, daily
      projections per channel
- [ ] `pito/docs/sync.md` (new): manual sync triggers, schedule reference,
      troubleshooting, the seeded flag and purge command
- [ ] `pito/docs/setup.md`: brief mention of `sync:full` and
      `seed:purge_fake_data` commands

### Validation

- [ ] Manual: trigger `bin/rails sync:full` for a connected owned channel —
      channels and videos populate with real data
- [ ] Manual: track an external channel via UI — public data appears,
      `external: true`, no `oauth_identity_id`
- [ ] Manual: track an external video URL — channel created if absent, video
      record created
- [ ] Manual: wait one day — auto-sync runs at 03:00 UTC; `last_synced_at`
      updates
- [ ] Manual: dashboard charts show daily time-series progression from real
      `VideoStat` records
- [ ] Manual: simulate quota exhaustion (override budget to a small value in
      dev) — sync skips with clear log entry, reschedules
- [ ] Manual: `bin/rails seed:purge_fake_data` removes only `seeded: true`
      records; real data unaffected
- [ ] All RSpec specs pass; sync specs covered with VCR
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- One spec file per sync job. VCR cassettes recorded against the user's real
  channel data once, anonymized to fixtures (titles, descriptions, IDs scrubbed
  where possible).
- Idempotency specs: each job runs twice in succession; second run produces no
  extra API calls (or only conditional ones, like `If-None-Match` if
  implemented), no duplicate records.
- Quota-exhaustion spec: pre-populate `YoutubeApiCall` near the daily budget;
  assert the job skips and reschedules.
- External job specs: URL parsing edge cases (handles, channel IDs, video IDs,
  malformed input).
- Schedule specs: `sidekiq-cron` config registers all jobs at expected cadence.
- `YoutubeUrl` parser specs: comprehensive coverage of URL forms, edge cases,
  malformed input rejection.

## Security requirements

- API keys (`YOUTUBE_PUBLIC_API_KEY`) stored in Rails credentials, never in
  repo.
- OAuth tokens (encrypted from Phase 7) used in jobs without leaking to logs.
- Sidekiq jobs scoped by `Current.tenant`; verify no cross-tenant data leakage
  in queries.
- VCR cassettes scrubbed of bearer tokens, refresh tokens, public API keys, any
  PII (channel owner emails if leaked) before commit.
- External channel tracking: validate the user-pasted URL at parse time; reject
  malformed input with clear error rather than silently failing.
- Quota enforcement is defensive (we don't want unexpected bills or being
  throttled); Google enforces hard limits regardless.
- Brakeman: no new warnings.
- bundler-audit: clean.
- Dependabot: review.
- `pito/docs/design.md`: external indicator in `/channels` index, sync-now
  buttons, seeded purge banner.

## Manual testing checklist

The user runs through this before commit:

1. Connect at least one owned YouTube channel (Phase 7 work)
2. Run `bin/rails sync:full` — completes without error within reasonable time
3. Visit `/channels` — see real channel(s) with real metadata; no seed indicator
   on real ones
4. Visit a real channel's videos — see real videos with thumbnails, titles,
   durations
5. Open Sidekiq web UI — confirm scheduled jobs registered; no failed jobs in
   retry/dead sets
6. Settings → YouTube → "Track external channel" → paste a competitor's channel
   URL → wait — appears in `/channels` with `external: true`
7. Settings → YouTube → "Track external video" → paste a YouTube video URL →
   wait — appears with parent channel auto-created if not present
8. Wait until 03:00 UTC (or fast-forward via
   `Sidekiq::Cron::Job.find('owned-channel-metadata').enque` for testing) —
   verify scheduled sync runs and `last_synced_at` updates
9. Dashboard charts show real time-series data progressing day over day
10. Manually trigger quota exhaustion: override `Quota::DailyBudget` constant to
    5 in dev → trigger a sync → observe skip + reschedule log
11. `bin/rails seed:purge_fake_data` — confirm only `seeded: true` records
    destroyed; real data preserved
12. `bundle exec rspec` — green

---

## Challenges to anticipate

- **Uploads playlist size on large channels.** YouTube returns the uploads
  playlist in chronological order; channels with thousands of videos require
  many paginated requests. Batch `videos.list` calls (50 IDs each) to stay
  efficient. Document the worst-case quota cost in `youtube_quota.md`.
- **Deleted or private videos.** Videos may be deleted, made private, or
  otherwise become inaccessible after Pito has indexed them. The sync should
  detect missing videos in `videos.list` responses and mark them `unavailable`
  rather than deleting from Pito (preserves history; the user might want to know
  what was there).
- **Quota cost variation by `part` parameter.**
  `part=snippet,statistics,contentDetails` costs more than `part=snippet`.
  Document and use minimal `part` values for routine syncs; expand only when
  needed. The cost map in Phase 7's `youtube_quota.md` is the source of truth.
- **Analytics API quota separate from Data API.** YouTube Analytics has its own
  rate limits and cost structure. Track separately in the audit table; the cost
  map distinguishes them.
- **External channels lack analytics.** The public API doesn't expose Analytics
  data; only public stats from `videos.list`. UI must communicate this clearly
  so the user doesn't expect retention or watch-time data on external channels.
- **Webhook-style efficiency unavailable.** YouTube doesn't push notifications.
  Polling is the only path. Daily for routine; user can trigger ad-hoc via "Sync
  now" buttons.
- **`YoutubeUrl` parser edge cases.** YouTube's URL forms have evolved over
  years: `/user/<handle>`, `/c/<custom>`, `/@<handle>`, `/channel/UC...`, mobile
  redirects (`m.youtube.com`), shortened (`youtu.be`), embedded (`/embed/`). The
  parser should accept the common ones and reject ambiguous input clearly (don't
  try to be clever; better to fail loud than guess wrong).
- **Time zone handling for schedules.** `sidekiq-cron` schedules run in the
  server's time zone. Use UTC explicitly in the cron expressions to avoid
  surprises across DST transitions or future deploys to different zones.
- **Both Pumas and the sync workload.** Sync jobs run in Sidekiq, not Puma. Web
  Puma triggers sync jobs (via UI buttons); MCP Puma also triggers them (if a
  `yt:write` tool says "sync now"). Both Pumas need access to the sync job
  classes; standard Rails autoload handles this.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has applied for or has the default 10,000-unit quota (sufficient for
   a single channel during Beta).
2. The user has at least one real YouTube channel connected (Phase 7
   prerequisite).
3. The user is OK with seeded data being preserved alongside real data until
   manually purged.
4. The user is OK with VCR cassettes containing real channel metadata being
   committed (titles, descriptions are public; bearer tokens scrubbed).
5. The schedule cadence (daily metadata, daily videos, daily stats for active
   videos, weekly stats for older, daily analytics) is acceptable. Adjust if the
   user prefers different timing.
6. `sidekiq-cron` is the chosen scheduler. Alternative is `sidekiq-scheduler`.
   Pick one and document.
