# Phase 22 — Video Import Flow

> Introduce a first-class `[import]` affordance on `/videos` that selects
> channels, enqueues per-channel `ImportJob` records + Sidekiq jobs, surfaces
> live progress, and lets the user keep/reject newly-imported videos with a
> durable tombstone so daily syncs never re-import rejected YouTube IDs.

Source of truth: B6 of
`docs/notes/2026-05-10-22-29-58-reply-to-keybindings-and-future-development.md`.

---

## Status

- [x] Spec drafted (`specs/01-video-import-modal-and-importjob.md`).
- [x] Open questions locked (master agent, 2026-05-11): see decisions summary in
      the log entry.
- [x] Rails implementation landed: ImportJob + RejectedVideoImport models,
      `Channels::VideoImporter` service, `Channel::ImportVideosJob` Sidekiq
      worker, `Imports::ChannelsController` (HTML + JSON), `[import]` button on
      `/videos`, channel-show in-flight badge, completion notifications.
      Awaiting manual validation before commit.

## Dependencies

- Phase 4 (Project Workspace) — turbo-frame modal pattern, pane primitives,
  bracketed-link convention.
- Phase 11 (videos.title) — required column already present.
- Phase 16 (Notifications pipeline) — used for ImportJob completion events.
- Phase 21 (CLI/MCP JSON branch pattern) — mirrored by this phase's controllers.

This phase does NOT depend on the Google OAuth / YouTube API foundation work
shipping in production; the import service is structured so the real
`playlistItems.list` call is the only seam between fixture-driven tests and live
API behavior. When OAuth lands, the seam swaps; the model + UI + tombstone
mechanics stand on their own.

## Sub-specs

- `specs/01-video-import-modal-and-importjob.md` — full spec for the `[import]`
  modal, `ImportJob` model, `RejectedVideoImport` tombstone table, per-channel
  Sidekiq job, progress streaming, post-import keep/reject table, and the JSON
  branch for CLI/MCP parity.

Additional sub-specs may be added as scope is split out (e.g. a dedicated
notification-wiring spec, a CLI/MCP parity spec) but for now the work fits in
one buildable unit.

## Open questions (resolve before dispatch)

These come straight out of the B6 section of the Mobile note and must be
answered by the user before any implementation agent is spawned.

1. **Re-enqueue policy.** When a channel already has a `running` or `queued`
   `ImportJob` and the user re-confirms `[start import]` against that same
   channel, do we:
   - (a) refuse with an explanatory inline message and surface the existing
     job's progress instead, OR
   - (b) queue a second `ImportJob` that picks up wherever the first leaves off?
     The spec leans toward (a) — single in-flight job per channel — but it is
     the user's call.
2. **Confirmation table scope.** The keep/reject confirmation table is shown:
   - (a) per-channel, as each `ImportJob` completes (separate table for each),
     OR
   - (b) aggregated, only after every selected channel's job finishes (one
     unified table). (a) is more responsive when jobs complete at different
     times; (b) is simpler UX. Spec leans toward (a).
3. **ImportJob retention.** Keep `ImportJob` rows forever as an audit trail, or
   expire after N days? The note leans toward keep forever. Confirm so we know
   whether to add a cron sweep.
4. **Sort/filter on the confirmation table.** Defer until the `f`/`s` keybinding
   schema lands (per the A-section keybinding revisions in the same Mobile
   note)? The spec excludes it for now.
5. **Tombstone reversal UX.** If the user later wants to un-tombstone a
   `RejectedVideoImport` row and let the daily sync pull the video back in,
   what's the surface — manual edit, rake task, future Settings page? Probably a
   follow-up rather than in-scope for this spec.

## Manual gate

Standard per-phase quality gates from `docs/plans/beta/beta.md` apply: RSpec
green, Brakeman clean, bundler-audit clean, design alignment (`docs/design.md`
touched if any new component pattern lands), manual test recipe followed by the
user before commit.
