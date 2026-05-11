# Phase 23 — Video Sync with Diff Dialog

Widens the **diff-dialog reconciliation pattern** locked for channels in Step
11's sub-spec 11i to **videos**. Sync — whether daily background or
user-triggered — NEVER overwrites Pito state and NEVER pushes to YouTube
silently. Every divergence between Pito and YouTube produces a **diff dialog**
the user resolves field-by-field, with bidirectional resolution (`accept pito` /
`accept youtube`) per row.

This is the **video sibling** of channel-diff. Where logic is shareable with 11i
(diff page renderer, apply-changes controller flow, per-field decision form
helpers), the implementation extracts shared partials / components so both
surfaces use the same code.

## Source of truth

- B2 + B3 sections of
  `docs/notes/2026-05-10-22-29-58-reply-to-keybindings-and-future-development.md`
  — daily sync produces diffs + notifications; sync never overwrites silently;
  per-field granularity; bidirectional resolution.
- Step 11's sub-spec 11i (channel diff) — the precedent shape we're widening.
- `docs/youtube_api_capabilities.md` "Video level capability matrix" — the
  writable + display-only field set the diff page reconciles.

## Critical principle

**Sync never overwrites Pito state AND never pushes to YouTube without user
confirmation.** Both daily background sync and user-triggered sync (the `[sync]`
button on `/videos/:slug`) produce a **diff dialog** for reconciliation. Default
radio selection on every field row is `accept youtube` (preserves
YouTube-as-source-of-truth posture, matches Step 11 D20). The user can flip any
row to `accept pito` to push that field out to YouTube instead.

## Sub-specs

This phase fans out into four sub-specs. They're declared up front so the master
agent can dispatch the rails-impl lanes in parallel where the file sets don't
collide.

- **23a — schema + `VideoDiffCheckJob` foundation.** Migrations for the new
  Video columns + `video_change_logs` + `video_diffs` tables; the job skeleton
  that walks connected channels' videos, calls `videos.list`, and persists diff
  results. No UI yet.
- **23b — diff page + decision UI.** `/videos/:slug/diff` route, view,
  three-column layout (`Pito` | `YouTube` | `decision`), per-field radio
  buttons. Reuses 11i's shared partials where they exist; extracts new shared
  partials where they don't.
- **23c — bidirectional apply.** `[apply changes]` controller action that
  consumes the per-field decisions, runs Pito-side updates + YouTube-side pushes
  in a single transaction, logs Pito-wins pushes to `video_change_logs`. Extends
  `Youtube::Client#update_video` with the partial-update read-modify-write
  pattern.
- **23d — daily cron + notification wiring.** Sidekiq-cron schedule for
  `VideoDiffCheckJob`, Phase 16 notification kind (`video_diff_detected`,
  severity `info`), flash banner on `/videos/:slug` when a diff is open.

## Open questions

The architect-spec doc enumerates these in §"Open questions"; the master agent
answers them before dispatching 23a. Summary here for fast scan:

1. 14-day rate limit on **video** title changes — does YouTube enforce this for
   videos the same way it does for channels? Verify against live API before
   locking the `title_changed_at` column semantics.
2. Video-diff retention — keep all resolved diffs as audit trail, or expire
   after N days? Recommend keep all.
3. Diff page UX at scale — paginated diff index when N videos have open diffs,
   or one diff page per video only? Recommend per-video for v1.
4. Field-level overrides (e.g., "always accept YouTube for `view_count`" per
   channel) — auto-resolve a subset of fields without dialog? Recommend NO for
   v1; revisit after dogfooding.
5. Daily cron schedule — separate from channel diff cron, or combined? Recommend
   separate (different quota budgets, independent failure surfaces).

Full text in
`docs/plans/beta/23-video-sync-diff-dialog/specs/01-video-sync-and-diff-dialog.md`.

## Coordination with Step 11

Step 11's 11i covers channel diff. Where logic is shareable, the implementation
extracts to shared components / partials so channels and videos use the same
code:

- Diff page renderer (three-column table, per-field decision form).
- Apply-changes controller flow (collect decisions, transactional apply, audit
  log writes).
- Per-field decision form helpers (radio button group, default-to-youtube
  selection, disabled state for non-writable fields).

The spec calls out each shared touch-point explicitly so the rails-impl agent
knows when to refactor vs. when to write fresh code.
