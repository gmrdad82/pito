# Phase 26 — Overview (umbrella spec)

> Umbrella for Phase 26. Reads top-down. Each sub-spec listed below is the
> dispatch unit for a single implementation agent. This file does not dispatch
> on its own — it is the routing map and the source-of-truth pin for the locked
> decisions and the open questions.

## Goal

Land three feature areas that touch each other:

1. Two new Settings panes (Slack + Discord) writing to the existing
   `notification_delivery_channels` table with provider-specific URL validation,
   a mandatory test ping, and per-provider `everything` + `daily_digest`
   booleans.
2. A `User.time_zone` foundation that pins UTC-storage / user-tz-render as the
   app-wide contract for every time value across web, MCP, and CLI surfaces.
3. A viewer-time analytics surface (best-time-to-publish heatmap) on per-video
   and per-channel analytics tabs, sourced from YouTube Analytics hourly data,
   stored UTC, rolled up to user-tz at query time.

The three areas bundle because the timezone foundation blocks the digest
scheduler and the analytics rollup. Shipping them in one phase keeps the
contract consistent and avoids retrofit.

## Files touched

This umbrella spec writes nothing. The sub-specs below own all file changes.

### Sub-specs in this phase

- `specs/01a-timezone-foundation.md` — User.time_zone column + render layer.
- `specs/01b-slack-webhook-pane-and-validation.md` — Slack pane.
- `specs/01c-discord-webhook-pane-and-validation.md` — Discord pane.
- `specs/01d-help-modal-markdown-guides.md` — beginner Markdown guides.
- `specs/01e-daily-digest-scheduler.md` — hourly cron + cross-tz delivery.
- `specs/01f-analytics-architecture-tz-update.md` — docs-only architecture
  update.
- `specs/01g-viewer-time-analytics-implementation.md` — heatmap + ingestion.
- `specs/01h-video-scheduled-publish-tz-wiring.md` — existing scheduler through
  user-tz.

### Cross-cutting reference docs (read-only inputs)

- `docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md` —
  Mobile drop, source of truth.
- `docs/realignment-2026-05-09.md` — confirms webhook delivery is in scope and
  pins notification-channel reuse.
- `CLAUDE.md` — hard rules (no JS `confirm`, yes/no boundary, bulk-as-
  foundation, Rails credentials for secrets).
- `docs/design.md` — bracketed-link convention, monospace font, color tokens,
  no-red rule for charts.
- `docs/agents/architect.md` — spec pyramid mandate, pane primitives.

## Acceptance

This umbrella is "accepted" when:

- [ ] All eight sub-spec files exist under
      `docs/plans/beta/26-webhooks-timezone-viewer-analytics/specs/`.
- [ ] Each sub-spec carries: Goal, Files touched, Acceptance checkboxes, Manual
      test recipe, Cross-stack scope, and Open questions.
- [ ] Each sub-spec encodes the locked decisions from `plan.md` verbatim (does
      not re-derive them).
- [ ] Each sub-spec lists every spec-pyramid layer required for its surface
      (model + service + job + component + helper + validator + lib + MCP tool +
      request + view + system + routing as applicable).
- [ ] Each sub-spec enumerates yes / no boundary conversion points for any
      external Boolean.
- [ ] The phase plan (`../plan.md`) lists the dispatch order and dependency
      graph.
- [ ] Open questions are surfaced to the user before the first implementation
      agent is dispatched.

## Manual test recipe

No manual test for this umbrella — it is docs-only. The per-sub-spec recipes are
run by the user when each implementation lands.

End-to-end smoke once all sub-specs ship:

1. Open `bin/dev`. Visit `/settings`. The Slack and Discord panes render with
   empty URL inputs, both checkboxes unchecked.
2. Paste a valid Slack webhook URL (from a test Slack workspace), tick
   `daily digest`, click `[update]`. A test message appears in the chosen Slack
   channel. The form persists URL + checkbox state on reload.
3. Repeat for Discord with the matching pane.
4. Visit `/settings` and change the timezone dropdown to `Pacific/Kiritimati`.
   Reload the page; the current-time display in the header (if any) shows the
   new tz. The next time the digest cron fires at minute 0, the digest hits both
   webhooks at the new local-09:00 instant.
5. Visit a video's analytics tab. The viewer-time heatmap renders with the
   day-of-week × hour-of-day grid in the user's tz. Hover a cell; the tooltip
   shows the local hour + view count + watch time. Visit the channel's analytics
   tab; the aggregate heatmap renders.

## Cross-stack scope

| Surface | Status  | Note                                               |
| ------- | ------- | -------------------------------------------------- |
| Web     | in      | All sub-specs primary surface.                     |
| MCP     | partial | 01a tz update via existing settings tool; webhook  |
|         |         | config is web-only.                                |
| CLI     | partial | 01a tz parity in `pito settings`; webhooks server- |
|         |         | only; analytics surface deferred.                  |
| Website | out     | No marketing-site changes.                         |

## Open questions

The full list of open questions is in `../plan.md` "Open questions" section.
This umbrella does not duplicate them; each sub-spec restates the questions
relevant to its scope so the implementation agent has them at hand.

Cross-referenced for convenience (resolve order matters):

1. Webhook autosave vs `[update]` — answer before 01b + 01c dispatch.
2. Digest content shape per provider — answer before 01e dispatch.
3. Viewer-time refresh cadence — answer before 01g dispatch.
4. Start-of-week default — answer before 01f + 01g dispatch (Monday default per
   Mobile note).
5. Heatmap palette — answer before 01g dispatch.
6. YouTube channel tz field — answer before 01a dispatch.
7. Cross-tz diff dialog copy — answer before 01a dispatch.
8. DST transition policy — answer before 01e dispatch.
9. 2FA gate on webhook URL changes — answer before 01b + 01c dispatch.
