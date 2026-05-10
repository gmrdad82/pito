# Phase 13 — Analytics Sync Engine + Tables + Dashboard

> **Status:** specs in flight as of 2026-05-10. No implementation yet.
> Phase folder created during the architect-spec dispatch that wrote the
> three specs under `specs/`.

## Plan

Per realignment work unit 5 + Mobile note 3 (`docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md`).
Big work unit; split into three specs landing in this order:

1. `specs/01-analytics-data-model.md` — schema for every analytics table
   enumerated in Note 3. Migrations only. No API client. No views.
2. `specs/02-analytics-sync-engine.md` — Sidekiq orchestrator + per-channel
   / per-video child jobs + `Youtube::AnalyticsClient` wrapper around
   `google-apis-youtube_analytics_v2` + retry/backoff + token-expiry +
   backfill mode + sidekiq-cron schedule. Builds on spec 01.
3. `specs/03-analytics-dashboard.md` — Hotwire / Chartkick views for every
   dashboard surface enumerated in Note 3. Builds on specs 01 + 02.

## Cross-references

- `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — source
  of truth for the data model + query shapes.
- `docs/realignment-2026-05-09.md` — work unit 5 ("Analytics sync engine
  + tables + dashboard"); marked "very big — split into sub-units."
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
  `tenant_id` on any analytics table.
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
  `YoutubeConnection` is the OAuth grant holder used by the sync engine.
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — Phase 8 prerequisite (analytics tables shed `tenant_id`).
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  — Phase 9 prerequisite (`YoutubeConnection` rename).
- `docs/plans/beta/12-video-schema-expansion/` — Phase 12 prerequisite
  (Video schema with `youtube_video_id`, `published_at`, `category_id`,
  `duration`, `tags`).

## Sessions

(empty — to be appended after each rails-impl / docs-keeper landing)
