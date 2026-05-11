# 01f — Analytics architecture + tz update (docs-only)

> **Documentation-only sub-spec.** No production code, no migrations, no tests.
> Updates `docs/architecture.md` with two new sections that pin the tz-rendering
> rule and the viewer-time aggregation design. Parallel-safe with every other
> sub-spec in Phase 26. Implementation agent: `pito-docs`.

## Goal

Add two sections to `docs/architecture.md`:

1. **Timezone rendering rule.** Codifies UTC-storage / user-tz-render as the
   app-wide contract for analytics. Defines what "a day" means (user-local day),
   what "this week" means (Monday–Sunday in user-tz, configurable later), and
   how rollup queries apply the tz offset at query time.
2. **Viewer-time aggregation.** Pins the storage schema, query patterns, refresh
   cadence, and rendering rule for the viewer-time analytics surface (01g).
   Cross-references 01a for tz rendering.

These sections become the durable architecture reference any future analytics
work reads first. Without them, future agents re-derive the rules from the
Mobile note + sub-specs each time — error-prone and slow.

## Files touched

### Edited

- `docs/architecture.md` — add two new top-level sections (or sub- sections
  under an existing "Analytics" header, depending on the doc's current shape;
  pito-docs picks the right anchor on dispatch).

### New

- None. Docs-only.

### Read-only inputs

- `docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md` —
  source of truth, especially §2 "User timezone support" and §3 "Viewer- time
  analytics."
- `docs/realignment-2026-05-09.md` — confirms YouTube Analytics work unit 6 is
  the home of viewer-time analytics.
- 01a + 01g sub-specs in this phase — the architecture sections must be
  consistent with the implementation they describe.

## Acceptance — section 1: Timezone rendering rule

The section must spec:

- [ ] Storage rule: every time / datetime / timestamp column in the schema is
      UTC. No exceptions. Validate by enumerating: `created_at`, `updated_at`,
      `last_synced_at`, `last_digest_run_at`, every `*_at` column added by 01a /
      01e / 01g / 01h.
- [ ] Render rule: every user-facing time value passes through `l_user_tz`
      (helper from 01a) or its CLI / MCP equivalent. Render layer is the sole
      conversion site.
- [ ] "Day" definition: a day in the analytics layer is a user-local day,
      bounded by `00:00:00` to `23:59:59.999999` in the user's tz. Rolled up
      from UTC-stored raw rows.
- [ ] "Week" definition: Monday–Sunday in the user's tz by default. Configurable
      later via a future user preference (out of scope for v1). Document the
      future hook.
- [ ] "Month" / "year" definitions: calendar month / year in the user's tz.
      Cross-references the calendar surface (Phase 16+).
- [ ] Rollup query pattern:
      `GROUP BY date_trunc('day', utc_ts AT TIME     ZONE user_tz)` (or
      equivalent). Document the SQL snippet.
- [ ] Edge cases: DST spring-forward (one day has 23 hours), fall-back (one day
      has 25 hours), half-hour offsets (`Asia/Kolkata`), quarter-hour offsets
      (`Asia/Kathmandu`, `Pacific/Chatham`).
- [ ] Cross-reference 01a for the render helper, 01e for the digest scheduler
      example, 01g for the viewer-time bucket query pattern.

## Acceptance — section 2: Viewer-time aggregation

The section must spec:

- [ ] Source endpoint: YouTube Analytics API v2 — verify the exact endpoint and
      granularity available (the Mobile note says "hourly viewership or close to
      it — verify exact granularity"). v1 assumes hourly buckets per video per
      day. If the API only exposes daily buckets, document the fallback (e.g.,
      approximate via traffic-source hourly slice).
- [ ] Storage schema: `video_viewer_time_buckets` table with
      `id, video_id, hour_of_day_utc (0-23), day_of_week_utc (0-6),     view_count, watch_time_seconds, last_synced_at, created_at,     updated_at`.
      Composite unique index on
      `(video_id,     day_of_week_utc, hour_of_day_utc)`. UTC at storage; never
      rolled to user-tz at write time.
- [ ] Rollup at query time: every read query rolls up via the user-tz offset.
      SQL pattern:
      `SELECT extract(dow FROM utc_hour AT TIME ZONE user_tz) AS dow,     extract(hour FROM utc_hour AT TIME ZONE user_tz) AS hod,     SUM(view_count), SUM(watch_time_seconds) FROM ... GROUP BY 1, 2`.
- [ ] Refresh cadence: daily refresh job per owned video (or per channel with a
      per-video inner loop), scheduled at 03:00 server time. v1 refreshes one
      day's worth (T-1 to T) per run. Backfill via a one-shot rake task
      (`pito:backfill_viewer_time_buckets`) over a rolling window (default 90
      days). **Open question: refresh cadence locked.**
- [ ] Query patterns: 1. Per-video heatmap:
      `WHERE video_id = ? GROUP BY dow, hod`. 2. Per-channel heatmap:
      `JOIN videos ON video_id = videos.id WHERE        videos.channel_id = ? GROUP BY dow, hod`. 3.
      Rolling window (7d / 28d / 90d):
      `WHERE last_synced_at >= NOW()        - INTERVAL N days` (approximate —
      exact filter depends on the API's data granularity).
- [ ] Cross-reference §1 (timezone rendering rule) for the user-tz conversion.
      Cross-reference 01g for the heatmap component + implementation.
- [ ] Document the source-of-truth note:
      `docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md`.
- [ ] Document the locked decisions from `../plan.md` so future readers don't
      re-litigate them.

## Manual test recipe

No manual test for this sub-spec — docs-only. The user reads the two new
sections in `docs/architecture.md`, confirms they accurately describe the
intended implementation per 01a + 01g, and validates the close-out.

Smoke check during dispatch:

1. `pito-docs` makes the edits.
2. User opens `docs/architecture.md` in a browser (or rendered Markdown viewer)
   and reads both new sections.
3. User cross-references against the Mobile note and the 01a + 01g sub-specs;
   everything is consistent.
4. `prettier --write docs/architecture.md` reflows to 80-char wrap.

## Cross-stack scope

| Surface | Status | Note                                                |
| ------- | ------ | --------------------------------------------------- |
| Web     | out    | Docs-only.                                          |
| MCP     | out    | Docs-only. (Future MCP analytics tool surfaces will |
|         |        | read this architecture section for the contract.)   |
| CLI     | out    | Docs-only.                                          |
| Website | out    | No change.                                          |

## Open questions

1. **Section placement in `docs/architecture.md`.** Current doc may not have an
   "Analytics" header yet. v1 leans on adding two new top-level sections;
   pito-docs picks the right anchor on dispatch. **Confirm with user.**
2. **Week-start default.** Monday per the Mobile note. Configurable later via a
   future user preference. Captured in §1. **Confirm.**
3. **YouTube Analytics granularity.** The Mobile note says "verify exact
   granularity." Until the spec is verified against the API docs, v1 assumes
   hourly buckets per video per day. **Confirm with user once the API quota /
   data shape is known.**
4. **Refresh cadence — daily vs more frequent.** v1 locks daily refresh at 03:00
   server time. **Confirm with user once Phase 7 quota tracking surfaces real
   numbers.**
