# Phase 13 — Analytics — Closed (2026-05-10)

## Goal

Daily nightly sync engine pulling YouTube Analytics v2 metrics into 12
timeseries tables; per-channel + per-video dashboards; backfill rake task;
window summaries (7d/28d/90d/lifetime); monetization-strip-on-release.

## Status

DONE. All 3 specs in main + reviewer + security audit + F1+F2+F3 fix-forward.

## Links

- Specs: `docs/plans/beta/13-analytics-sync-engine/specs/{01,02,03}-*.md`
- Reviewer playbook:
  `docs/orchestration/playbooks/2026-05-10-phase-13-analytics.md`
- Security playbook:
  `docs/orchestration/playbooks/security-2026-05-10-phase-13-analytics.md`
- Phase log: `docs/plans/beta/13-analytics-sync-engine/log.md`

## Key changes

- 12 analytics tables (channel/video × daily/window-summary ×
  growth/retention/revenue)
- `Youtube::AnalyticsClient` routed through `Youtube::ServiceFactory` (timeouts
  inherited)
- Sidekiq orchestrator (`AnalyticsSync`) + child jobs (Channel/Video/Retention)
- 18 chart partials (chartkick + groupdate)
- `analytics:backfill` rake task
- 3 refresh POST endpoints (channel / video / retention) with per-resource Redis
  cache locks

## Validation

Walk reviewer playbook (24 steps); manually trigger refresh from
/channels/:id/analytics; verify lock blocks rapid repeats; verify monetization
revenue columns absent when flag = "no".

## Open follow-ups

- F4 (rake task input narrowing) — minor; queued
- F5 (per-user scoping) — pre-existing pattern; lands with multi-user phase
- F6 (TokenRefresher timeouts) — minor; queued
- analytics_window_picker_controller.js no-op marker — drop or wire
