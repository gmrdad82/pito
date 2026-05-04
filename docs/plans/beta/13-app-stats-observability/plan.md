# Phase 13 — App Stats / Observability

> **Goal:** Add an in-app observability surface — health of the stack, both Puma
> processes tracked separately, database usage, embedding cost, YouTube quota,
> Sidekiq queue health, audit log summaries. Keep the user informed of what Pito
> is doing and what it's costing without ever leaving the app or relying on
> external dashboards.

**Depends on:** Phase 11 (workflow features producing diverse data and quota
burn worth observing), Phase 12 (auth model lets observability scope by tenant +
restrict to owner-role).

**Unblocks:** Confidence to deploy to Hetzner (Phase 16) — you can't operate
what you can't see. Phase 14 (backup status surfaces in the same observability
layer).

---

## Why Phase 13 is now

Pito's footprint by Phase 12 includes: Postgres + pgvector, Meilisearch, Redis,
Sidekiq, Voyage API calls, YouTube API calls, KB filesystem reads/writes, OAuth
identities, sessions, ApiTokens, Doorkeeper applications, Slack interactions (if
survived), terminal app sessions. **Two Puma processes** serve two domains with
potentially different load characteristics. None of that is visible at a glance
today. Phase 13 fixes that.

This is the first phase with no major new feature surface — it's pure
operational maturity. By placing it before backups (Phase 14) and security
hardening (Phase 15), the observability layer has two more phases of features to
feed it before Hetzner cutover.

The phase is also the smallest "real" phase remaining — single page, multiple
sections, lots of read-only aggregations. No new external services. No new
dependencies that aren't already in the stack.

---

## In scope

### Single observability page

`/stats` (or Settings → Stats; pick one — recommend `/stats` as a top-level
route since it's an operational tool, not a configuration screen). Single page,
multiple sections rendered as bracketed-table aesthetic per
`pito/docs/design.md`. Owner-role only (visible to users with `role: 'owner'`).

No external APM, no Grafana, no DataDog. Beta keeps observability native and
in-app.

### Stack health section

Quick "is everything alive" view, refreshed on page load (cached 30s server-side
to avoid hammering on rapid refresh):

- **Postgres** — connection status, version, database size, top 10 tables by
  size, pgvector index health
- **Meilisearch** — connection status, version, index sizes, document counts,
  hybrid embedder status
- **Redis** — connection status, memory usage, Sidekiq queue lengths
- **Disk** — free space on the configured KB roots (`PITO_DEV_KB_PATH`,
  `PITO_WEBSITE_PATH`, plus any project-notes roots from Phase 4 — Project
  Workspace). The original list also included `PITO_YT_KB_PATH`; the YouTube KB
  repo has been dropped and channel-level notes will reuse the project-notes
  pattern from Phase 4.
- **Web Puma** — process info, worker count, thread count, current request rate
  (last minute), p50/p95 response time
- **MCP Puma** — same metrics, tracked independently. The two Pumas have
  different load profiles (humans vs AI clients, HTML responses vs JSON tool
  calls), so showing them side by side surfaces if one is starved while the
  other is idle.

### Database section

- Per-table row counts and storage size
- Slowest queries from `pg_stat_statements` if the extension is enabled
  (degrades gracefully if not — show a "extension not enabled, see setup.md"
  note)
- Connection pool usage per Puma process (Web Puma pool, MCP Puma pool, Sidekiq
  pool)
- Connection limit headroom

### API quota & cost section

This is the most actionable section for the user. Three primary cost/quota
concerns:

- **YouTube quota** — today's usage, this month's usage, breakdown by endpoint,
  projection to month-end. Read from `youtube_api_calls` audit table (Phase 7).
- **YouTube public API quota** (separate pool) — same view for public-key-driven
  calls
- **Voyage cost** — today's tokens, this month's tokens, dollar estimate based
  on a pricing constant. Read from `voyage_api_calls` audit table (Phase 10).

Charts use Chartkick (already in the stack from Alpha). 30-day rolling line
charts plus current-day big-number tiles.

### Sidekiq summary section

Embedded summary using Sidekiq's API directly (`Sidekiq::Stats.new`):

- Jobs processed today
- Failures today
- Retry queue depth
- Dead set count
- Per-queue length (default, mailers, embeddings — Phase 10's dedicated queue,
  etc.)
- Link to the full Sidekiq web UI (mounted at `/sidekiq` for owner-role)

### Audit log section

Tail of recent activity from the dedicated audit log files:

- `log/mcp_dev_audit.log` (Phase 1)
- `log/mcp_yt_audit.log` (Phase 3 + Phase 9 — both relational and KB tools log
  here)
- `log/mcp_website_audit.log` (Phase 6)
- `log/auth_audit.log` (Phase 3 — token creation, revocation, login events)

Filter UI: namespace dropdown, date range, free-text search within the tailed
window. Pagination via offset. Download full log button (chmod-aware; only
owner-role; the download itself audited to a separate operational log).

### MCP usage section

Reads from a `mcp_call_log` table introduced in this phase:

- Tool call counts (which tools are most used) over the last 7 / 30 days
- Per-token activity (which token does what) — name, last call, total calls,
  scope set
- Recent calls table (last 100, with status, duration, tool name, token name)
- Slowest tool calls (helps identify which MCP tools need optimization)

### Channel sync health section

Per-channel:

- Last successful sync (per type: metadata, videos, stats, analytics)
- Last attempted sync
- Sync errors today
- Days since last successful sync
- Quick "Sync now" button (already built in Phase 8; surfaced again here for
  convenience)

### Embedding coverage section

- Channels embedded / total channels
- Videos embedded / total videos
- KB files embedded / total KB files
- Channels/videos/KB files with stale `content_hash` (re-embedding pending)
- "Backfill missing" buttons per type (re-uses Phase 10's backfill jobs)

### Alert thresholds section (lightweight)

The user can set thresholds; warnings appear as banners on `/stats` and `/`:

- Examples: "warn if YouTube quota > 80% of daily budget", "warn if Voyage cost
  today > $1", "warn if Sidekiq retry queue > 10", "warn if any Puma has no
  available workers"
- Schema: `alert_thresholds` table with `metric`, `threshold`, `direction`
  (above/below), `enabled`
- Thresholds evaluated server-side on page load (not real-time push). Banners
  render conditionally.
- **No email/SMS alerts in Beta.** Visual only. Phase 16 adds external pinger
  (UptimeRobot or similar) for true uptime monitoring, but that's about
  availability, not internal thresholds.

### `mcp_call_log` table

Introduced in this phase to feed the MCP usage section:

- `id`
- `tenant_id`
- `user_id` (resolved from token)
- `token_id` (the `ApiToken` or Doorkeeper token used)
- `puma` (string: `web` or `mcp` — identifies which Puma served the request)
- `tool_name`
- `outcome` (string: `success`, `scope_denied`, `sandbox_denied`, `error`)
- `duration_ms`
- `created_at`

Populated by an `MCP::CallLogger` middleware/wrapper applied to all MCP tool
dispatches. Heavy logging is fine here — a few hundred MCP calls per day
produces tiny table growth.

### Out of scope

- External APM / DataDog / Sentry integration (Phase 16 adds Sentry-style error
  tracking for production; Beta keeps simple)
- Email/SMS/Slack alerts on threshold breaches (visual only in Beta)
- Historical metrics retention beyond 90 days (Postgres for short-term;
  long-term archival is Theta)
- User-customizable dashboards (one fixed page; bespoke views are Theta)
- Performance optimization based on observed data (this phase observes; future
  phases optimize where the data points)
- Real-time streaming metrics (page-load refresh is sufficient for single-user)

---

## Plan checklist

### Schema

- [ ] Migration: `mcp_call_log` table per the schema above
- [ ] Migration: `alert_thresholds` table — `id`, `tenant_id`, `metric`,
      `threshold`, `direction`, `enabled`, timestamps
- [ ] Confirm `voyage_api_calls` (Phase 10) and `youtube_api_calls` (Phase 7)
      exist; reference them
- [ ] Optional: materialized view for daily summary aggregates if the live
      aggregation is too slow at scale (probably not needed in Beta)

### Stack health

- [ ] `Health::Postgres` service: connection check, version, DB size, table
      sizes, vector extension info
- [ ] `Health::Meilisearch` service: connection, version, index info, embedder
      status
- [ ] `Health::Redis` service: connection, memory info, Sidekiq stats
- [ ] `Health::Disk` service: free space on KB roots
- [ ] `Health::Puma` service: per-Puma metrics. Web Puma reports its own; MCP
      Puma reports its own; the page aggregates and displays both.
- [ ] All cached for 30s server-side via Rails low-level cache
- [ ] Each `Health::*` returns gracefully on failure — section shows
      "unavailable" rather than crashing the page

### Stats page

- [ ] `/stats` route and controller (owner-role only via Phase 12 role check)
- [ ] At-a-glance cards section at the top: today's API calls, today's costs,
      queue depth, alert count
- [ ] Section partials: stack health, database, API quota & cost, Sidekiq, audit
      logs, MCP usage, channel sync, embedding coverage, alert thresholds
- [ ] Each section is a Turbo Frame so failures in one section don't break the
      page
- [ ] Each partial cached briefly (5-30s depending on data freshness needs)

### MCP call logging

- [ ] `MCP::CallLogger` wrapper applied to every MCP tool dispatch
- [ ] Records every invocation to `mcp_call_log` with timing, outcome, Puma
      identifier
- [ ] Specs covering happy path, scope-denied, sandbox-denied, error path;
      verify Web Puma vs MCP Puma identification

### Quota & cost decorators

- [ ] `Stats::YoutubeQuota` decorator: today's usage, monthly usage, by
      endpoint, projection
- [ ] `Stats::VoyageCost` decorator: today's tokens, monthly tokens, dollar
      estimate from pricing constant
- [ ] Pricing constants in `config/pricing.rb` with comments documenting source
      URL and last-checked date
- [ ] Specs verify aggregations against fixture data

### Sidekiq summary

- [ ] Use `Sidekiq::Stats.new` and `Sidekiq::Queue` API directly
- [ ] Show per-queue lengths (default + named queues like `embeddings`)
- [ ] Link to `/sidekiq` (already mounted from Alpha; verify owner-role gating)

### Audit log section

- [ ] `LogTailer` service: reads last N lines from each audit log file
- [ ] Pagination via byte offset (efficient for large logs)
- [ ] Filter UI: namespace dropdown, date range picker, free-text search
- [ ] Download full log action; chmod-aware; logs the download to
      `log/operational_audit.log`

### Channel sync health

- [ ] Reads `Channel.last_synced_at` and Sidekiq retry/dead set entries by job
      class name
- [ ] Per-channel rows with last-success, last-attempt, error count,
      days-since-success
- [ ] Re-uses the existing "Sync now" button from Phase 8

### Embedding coverage

- [ ] Counts of embedded vs not-embedded for `Channel`, `Video`,
      `KbFileEmbedding`
- [ ] Stale records (where `content_hash` doesn't match current source
      composition; computed on demand)
- [ ] "Backfill missing" buttons that enqueue Phase 10's backfill jobs

### Alert thresholds

- [ ] Settings → Alert Thresholds page: form to set thresholds per metric
- [ ] Default seeded thresholds: YouTube quota > 80%, Voyage daily > $1, Sidekiq
      retry > 10, Puma worker exhaustion
- [ ] Banner component on `/stats` and `/` showing active warnings
- [ ] Specs for threshold evaluation, banner rendering

### Documentation

- [ ] `pito/docs/observability.md` (new): what's tracked, where to look, how to
      interpret
- [ ] Update `pito/docs/architecture.md`: observability layer, dual-Puma
      metrics, audit log file references
- [ ] Update `pito/docs/design.md`: stats page layout, alert banner pattern

### Validation

- [ ] Manual: visit `/stats`; all sections render within 2s
- [ ] Manual: stop Meilisearch (`docker stop meilisearch`); refresh; Meili
      section shows red, rest of page works
- [ ] Manual: induce high YouTube usage (test mode); verify chart updates and
      threshold warning fires
- [ ] Manual: trigger embedding backfill from the coverage section; jobs run;
      coverage updates on next refresh
- [ ] Manual: filter audit log by tool name; correct entries shown
- [ ] Manual: confirm Web Puma and MCP Puma metrics differ when one is under
      load and the other idle (induce by hitting one with load)
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- `Health::*` specs: connection success, connection failure (exception caught
  and reported gracefully), version detection, edge cases (Postgres without
  `pg_stat_statements`, Meilisearch with no indices).
- Audit log tailer specs: handles missing files, large files, multiple files,
  byte-offset pagination.
- `MCP::CallLogger` specs: middleware records correctly; doesn't double-record
  on retries; correctly identifies Web Puma vs MCP Puma source.
- Stats decorator specs: aggregations correct against fixture data with
  controlled timestamps.
- Threshold evaluation specs: above/below thresholds, no thresholds set, missing
  metric data handled gracefully.
- Page-level spec: `/stats` renders for owner; rejected for non-owner; rejected
  for unauthenticated.

## Security requirements

- `/stats` accessible only to authenticated users with `role: 'owner'`
  (single-user Beta means this is just the user themselves; future multi-user
  keeps it owner-only).
- Audit log downloads require owner role and add an entry to
  `log/operational_audit.log` ("X downloaded log file Y at Z").
- Stats data tenant-scoped — even though there's one tenant in production,
  queries explicitly use `Current.tenant`.
- No third-party services receive observability data.
- The `/sidekiq` web UI mounted from Alpha gets verified for owner-role gating
  in this phase if not already.
- Brakeman: review file-tail code for shell injection risk (uses Ruby IO, not
  shell — should be fine).
- bundler-audit: clean.
- Dependabot: review.
- `pito/docs/design.md`: stats page layout, alert banner pattern, threshold form
  documented.

## Manual testing checklist

The user runs through this before commit:

1. Visit `/stats` — page renders within 2s; all sections show data (some may
   show zero — that's fine for a fresh install)
2. All section headers render with bracketed labels per design.md
3. Stop Meilisearch (`docker stop meilisearch`) — refresh — Meili section shows
   error banner; rest of page still works
4. Restart Meilisearch — green next refresh
5. Inspect a known-working channel; click "Sync now" → triggers Phase 8 job;
   visible in Sidekiq summary
6. Set Voyage threshold to a low number (e.g., $0.01); trigger an embedding job;
   threshold warning appears as banner on `/stats` and `/`
7. Audit log section: filter by `yt:write_kb_file`; shows only those entries
8. Embedding coverage shows 100% if Phase 10 backfill ran successfully;
   otherwise shows gaps with "Backfill missing" buttons
9. Compare Web Puma and MCP Puma metrics — if one was idle and the other busy
   during the day, the metrics differ
10. Visit `/sidekiq` — full Sidekiq UI loads (owner-role gated)
11. As a non-owner user (if multi-user is enabled in dev): visit `/stats` → 403
    or redirect
12. `bundle exec rspec` — green

---

## Challenges to anticipate

- **`pg_stat_statements` extension not enabled by default.** Adding it requires
  `shared_preload_libraries` config and a Postgres restart. If user doesn't
  enable, gracefully omit the slow-query subsection with a note pointing at
  `setup.md` for instructions.
- **Sidekiq stats are global, not per-tenant.** For single-tenant Beta this is
  fine. Document the caveat for Theta — multi-tenant Pito would need either
  separate Sidekiq instances or per-tenant queue tagging.
- **Cost projections are noisy mid-month.** Monthly cost projections based on
  partial-month data are unreliable in the first 5-7 days. Show a "low
  confidence" annotation when the month is < 25% complete.
- **Audit log file growth.** Logs grow indefinitely if not rotated. This phase
  configures `logrotate` (or Ruby's `Logger.new(file, 'daily')` rotation) — keep
  90 days, gzipped past 7 days.
- **Stats page performance.** If any aggregate query is slow, it slows the whole
  page. The Turbo Frame approach isolates failures; the 30s cache prevents
  thrashing. If aggregations get too slow at scale, run them as nightly
  background jobs into a `daily_stats` table — but probably not needed in Beta.
- **Dual-Puma metric collection.** Each Puma process knows its own metrics.
  Showing both side-by-side requires either (a) each Puma writes metrics to a
  shared store (Redis is convenient — already in the stack) or (b) the page
  makes a side-channel HTTP request to the other Puma's `/healthz` endpoint.
  Option (a) is cleaner; both Pumas push their stats to a Redis hash on a
  periodic timer (e.g., every 10s).
- **Alert banner fatigue.** If too many thresholds are tripped, the banner
  becomes noise. Default thresholds should be conservative; the user can dial
  them in.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user is OK with the stats page being basic, in-app, single page (no
   external APM in Beta).
2. Threshold warnings are visual-only in Beta. External pinger comes in
   Phase 16. Confirm.
3. `pg_stat_statements` extension acceptable to enable in Postgres? (Requires
   Postgres config change + restart.) If not, slow-query subsection is omitted
   gracefully.
4. Audit log retention policy: 90 days with gzip past 7 days. Confirm or adjust.
5. Both Pumas push metrics to Redis (single-source-of-truth approach) vs
   side-channel HTTP. Recommend Redis approach.
6. The `/stats` route is a top-level route (not nested under Settings). Confirm.
