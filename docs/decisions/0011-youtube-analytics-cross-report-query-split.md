# ADR 0011 — Split YouTube Analytics queries to avoid cross-report metric combinations

## Status

Accepted, 2026-05-12. [skipci]

## Context

Phase 13 (Analytics sync engine) wired pito to the YouTube Analytics v2 API via
`reports.query`. The sync pipeline issues a small number of named report queries
per channel + video, each combining a set of metrics with a set of dimensions.
Two of the named queries surfaced cross-report-metric rejection errors during
the beta2 polish wave:

- **C1 / V1 (daily metrics).** The original `DAILY_METRICS` constant bundled
  basic-stats metrics (`views`, `estimatedMinutesWatched`,
  `averageViewDuration`, etc.) with engagement metrics (`likes`, `comments`,
  `shares`, `subscribersGained`) AND impression / card metrics
  (`cardImpressions`, `cardClickRate`, `cardTeaserImpressions`,
  `cardTeaserClickRate`, `videoThumbnailImpressionsClickRate`).
- **C2 / V2 (window summary).** `WINDOW_RATIO_METRICS` bundled
  `averageViewPercentage` (a basic-stats ratio) with three click-rate ratios
  (`cardClickRate`, `cardTeaserClickRate`,
  `videoThumbnailImpressionsClickRate`).

The API rejected both combined queries with
`400 badRequest: The query is not supported.`. Investigation surfaced the
underlying rule: the YouTube Analytics API splits metrics across distinct named
reports (basic stats, engagement, card performance, thumbnail impressions,
audience retention, geography, traffic sources, etc.). Combining metrics that
belong to different reports in a single `reports.query` call is rejected; each
combination has to go through the specific report endpoint that owns it.

The Phase 13.2 fix-forward (2026-05-11) resolved the immediate breakage by
slimming both metric sets to the basic-stats subset that one report accepts,
leaving the missing metrics' DB columns to stay `NULL` until a follow-up spec
adds the additional report calls and merges the rows.

## Decision

Split the metric constants in `app/services/youtube/analytics_query_builder.rb`
to keep every `reports.query` call within a single report's accepted metric
list. Drop the cross-report metrics from the constants today; reserve the
multi-call merge for a future architect spec.

Concretely:

- **`DAILY_BASIC_METRICS`** — what `DAILY_METRICS` becomes after the split.
  Carries only basic-stats metrics: `views`, `estimatedMinutesWatched`,
  `averageViewDuration`, `redViews`, `estimatedRedMinutesWatched`,
  `averageViewPercentage`. Stays on C1 (channel daily) + V1 (video daily).
- **`DAILY_ENGAGEMENT_METRICS`** — reserved constant for a future second call to
  the engagement report. Carries `likes`, `dislikes` (where available),
  `comments`, `shares`, `subscribersGained`, `subscribersLost`. Not used today;
  the constant is declared and inlined in a comment block as the contract for
  the future architect spec.
- **`WINDOW_RATIO_METRICS`** — slimmed to `averageViewPercentage` only. The
  three click-rate ratios (`cardClickRate`, `cardTeaserClickRate`,
  `videoThumbnailImpressionsClickRate`) are dropped from this constant and
  reserved for the future impressions-report + card-performance-report calls. C2
  / V2 (window summary) issue the slimmed call today.
- **DB columns stay in place.** `channel_window_summaries`,
  `video_window_summaries`, and `video_daily_by_traffic_sources` still carry the
  click-rate ratio columns. They write `NULL` until the future spec merges the
  dedicated-report calls into the upsert.

The architect spec for the multi-call + merge work is reserved as a future
dispatch. The split today is the minimum-surface fix that unblocks Phase 13 sync
without dropping the columns or losing the contract.

## Consequences

- **Phase 13 sync runs cleanly.** C1, V1, C2, V2 all go through. The rejected
  metrics are absent from the query, not "queried then ignored."
- **Some columns stay `NULL` until the follow-up ships.** Consumers that expect
  those click-rate ratios on the dashboard render a `—` placeholder for the
  field rather than a misleading zero.
- **The future spec is bounded.** The reserved constant
  `DAILY_ENGAGEMENT_METRICS` and the three click-rate ratios sit in a comment
  block above the live constants, so the future architect spec starts with an
  already-named target: "add a second `reports.query` call per channel + video
  per window for each reserved constant, merge the rows into the same upsert
  before persistence."
- **Documented in `follow-ups.md`.** The dedicated follow-up entry under
  "Analytics window-summary click-rate ratios via dedicated impressions /
  card-performance reports" carries the action plan for the future spec.

## Open questions (deferred)

- **Should the engagement-report call ride the same Sidekiq job as the
  basic-stats call, or split into a sibling job?** A sibling job is more
  resilient (a 4xx on engagement doesn't roll back basic stats) but adds
  scheduling complexity. Defer to the architect spec; lean toward "same job,
  separate begin/rescue blocks so a failure in one report doesn't strand the
  other."
- **What's the right retry posture for cross-report calls?** If the basic-stats
  call succeeds but the engagement call 5xx's, today's upsert layer would write
  basic stats and leave engagement columns null. Whether that's a permanent null
  (until next sync) or a retry- with-backoff is open. Defer.

## Alternatives considered

- **Drop the click-rate ratio columns from the schema entirely.** Rejected. The
  columns hold real product value (operator wants the click-rate ratios in the
  dashboard); dropping the schema would retire a planned feature, not just
  postpone it.
- **Issue one combined query and absorb the 400 in the sync layer.** Rejected.
  The API rejection is per-call, so absorbing it would return zero rows across
  all metrics, not just the cross-report ones. The split is the only path that
  returns rows for the accepted metrics.
- **Move to YouTube Analytics v1 or a different API surface.** Not realistic —
  v2 is the live surface; v1 is deprecated.

## Date

2026-05-12. [skipci]

## Related

- `app/services/youtube/analytics_query_builder.rb` — the metric constants
  table; tracking note for `WINDOW_RATIO_METRICS` lives inline at the constant
  declaration.
- `app/services/youtube/channel_analytics_sync.rb` / `video_analytics_sync.rb` —
  the consumers of the metric constants.
- `docs/plans/beta/13-analytics-sync-engine/` — Phase 13 plan + log.
- `docs/orchestration/follow-ups.md` → "Analytics window-summary click-rate
  ratios via dedicated impressions / card-performance reports" — the durable
  follow-up entry for the future merge spec.
- `db/schema.rb` — `channel_window_summaries`, `video_window_summaries`,
  `video_daily_by_traffic_sources` carry the reserved-null columns.
