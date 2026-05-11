# Phase 24 — Google management on Channels + per-channel revoke flow (umbrella)

## Goal

Move every Google / YouTube OAuth management surface off `/settings` and onto
`/channels`, and ship a per-channel `[revoke]` action that cascades the full
data footprint of a channel (videos, analytics, diffs, change-logs, links,
rejected-imports, plus the `YoutubeConnection` itself when this channel was its
last). Settings goes back to its lane (app-wide preferences only); channels
becomes the single source of truth for everything channel-shaped — including the
OAuth grants that authorize them.

This file is the umbrella spec. Five sub-specs carry the implementation surface
each; they are independently dispatchable.

Source-of-truth note (verbatim, read first):
`docs/notes/2026-05-11-02-08-34-google-section-move-to-channels-revoke-flow.md`.

## Sub-spec index

| Slug                                   | Surface in scope                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| `01a-drop-google-from-settings.md`     | Remove Google card from `/settings`; remove `/settings/youtube`; redirect.            |
| `01b-google-management-on-channels.md` | Banner on `/channels`; per-channel inline Google panel on `/channels/:slug`.          |
| `01c-per-channel-revoke-modal.md`      | `[revoke]` action on channel show; wide-modal confirmation; controller wiring.        |
| `01d-delete-channel-data-job.md`       | `DeleteChannelDataJob` Sidekiq job; cascading deletion + YoutubeConnection lifecycle. |
| `01e-bulk-revoke-on-channels-index.md` | Bulk-select + `[revoke N]` on `/channels` index, ported from `/settings/youtube`.     |

## Files touched (umbrella view)

Each sub-spec carries its own per-lane file list. The aggregate footprint is:

- `app/controllers/settings_controller.rb` (drop Google card data + tests).
- `app/controllers/settings/youtube_controller.rb` (DELETE the file).
- `app/views/settings/index.html.erb` (drop Google fieldset).
- `app/views/settings/youtube/show.html.erb` (DELETE the file).
- `app/controllers/channels_controller.rb` (banner data; revoke action +
  wiring).
- `app/views/channels/index.html.erb` (banner; bulk `[revoke N]`).
- `app/views/channels/show.html.erb` (per-channel Google panel; `[revoke]`
  link).
- `app/views/channels/_google_banner.html.erb` (NEW).
- `app/views/channels/_google_panel.html.erb` (NEW).
- `app/views/channels/_revoke_modal.html.erb` (NEW).
- `app/controllers/channel_revokes_controller.rb` (NEW; show modal + confirm
  endpoint).
- `app/jobs/delete_channel_data_job.rb` (NEW).
- `config/routes.rb` (drop `/settings/youtube` routes; add
  `/channels/:id/revoke` + `/channels/revokes/:ids`; add 301 redirect for
  back-compat).
- `app/components/keyboard_shortcuts_modal_component.{rb,html.erb}` (if any
  shortcut referenced the old Settings → YouTube target — verify and adjust).
- `spec/requests/settings_spec.rb`.
- `spec/requests/channels_spec.rb`.
- `spec/requests/channel_revokes_spec.rb` (NEW).
- `spec/jobs/delete_channel_data_job_spec.rb` (NEW).
- `spec/views/channels/_google_banner.html.erb_spec.rb` (NEW).
- `spec/views/channels/_google_panel.html.erb_spec.rb` (NEW).
- `spec/views/channels/_revoke_modal.html.erb_spec.rb` (NEW).
- `spec/system/channel_revoke_spec.rb` (NEW; critical user journey per spec
  pyramid item #10).
- `docs/design.md` (NEW section: wide-modal pattern, if not already documented).

## Decisions locked (architect-autonomous, per the user note)

1. **`/settings/youtube` is dropped.** No slim debug page survives. The router
   keeps a 301 redirect `/settings/youtube → /channels` for one phase as
   back-compat for browser bookmarks, then revisits in a later hygiene pass.
2. **`[revoke]` placement on channel show:** the heading-actions row, inline
   with `[edit]` / `[unstar]` / etc. Not in the body. This mirrors the existing
   row-level action grouping on the show page.
3. **No per-row `[revoke]` in `/channels` index.** Bulk-revoke replaces the
   per-row inline action; see sub-spec 24e. Rationale: the per-row HTML in the
   channels list is already crowded; the bulk-revoke surface preserves the
   existing `/settings/youtube` pattern (multi-select + `[revoke N]`).
4. **Confirmation surface:** **wide-modal** (new pattern in this phase), not the
   action-screen framework. Reason: the modal needs to display structured
   cascade counts (videos, analytics rows, diffs, change-logs, links,
   rejected-imports, plus the YoutubeConnection-last-channel hint), which the
   action-screen pattern is too plain to display readably. The wide-modal
   pattern follows `[cancel]` / `[confirm revoke]` button order on the right,
   bracketed-link convention, `pane--standalone` background. Documented in
   `docs/design.md` as part of this phase.
5. **Modal copy (single canonical string used by 24c + 24e — bulk variant
   pluralizes the channel noun):**

   ```
   Revoke channel "{title}"? This will permanently delete {N} video(s),
   {M} analytics record(s), {D} diff record(s), {L} change-log record(s),
   {K} link record(s), {R} rejected-import record(s), and {C} calendar entry
   (entries). The Google OAuth grant will be revoked if this is the last
   channel on the connection. This action cannot be undone.
   ```

   Where `{title}` falls back to the UC-id slug when `channel.title` is blank
   (mirroring `SettingsController#index`'s label resolution).

6. **Authorization:** existing `Sessions::AuthConcern` (signed-in user) is the
   single gate. The single-install + multi-user model (ADR 0003) means anyone
   authenticated has full access; no per-user channel scope. The spec sweep
   includes the unauthenticated-redirect branch but NOT an IDOR test (retired
   per project conventions).
7. **Job retention:** `DeleteChannelDataJob` runs through Sidekiq's standard
   retention. No additional audit row is written when the job completes — the
   channel and its videos are gone, so there is nothing to attach an audit row
   to. The Sidekiq job log is the trail.
8. **Modal counts source:** the controller computes them at the moment the modal
   renders (no caching). For a channel with thousands of videos and millions of
   analytics rows the counts come from indexed `COUNT(*)` queries, which run in
   tens of milliseconds. The wide-modal partial accepts the count hash and
   renders it.
9. **Idempotency:** `DeleteChannelDataJob` accepts a `channel_id` plus
   `youtube_connection_id` snapshot at enqueue time. If the channel is already
   gone when the job runs (double-confirm, retry, etc.), the job no-ops on the
   channel deletes but still re-checks the YoutubeConnection — if the captured
   connection_id now has zero channels and zero videos referencing it, the job
   destroys it. Re-running the job on an already-gone channel returns silently.
10. **Yes/no boundary:** the revoke confirmation endpoint accepts a `confirm`
    param valued `"yes"` (anything else is treated as cancel). Boundary
    convention per the project's yes/no rule (`CLAUDE.md` hard rule).

## Acceptance (umbrella)

- [ ] 24a, 24b, 24c, 24d, 24e all satisfied (see each sub-spec's checkbox list).
- [ ] No `/settings/youtube` route exists; the legacy URL 301-redirects to
      `/channels`.
- [ ] No Google card / fieldset renders on `/settings`.
- [ ] `/channels` index shows the new Google banner with connected-accounts
      summary + `[+ add another Google account]`.
- [ ] `/channels/:slug` show page renders a Google connection panel inline.
- [ ] `[revoke]` link on channel show opens the wide-modal with the canonical
      copy and live cascade counts.
- [ ] Confirm enqueues `DeleteChannelDataJob` with the channel id + connection
      id; cancel closes the modal without enqueueing.
- [ ] `DeleteChannelDataJob` deletes the channel, all videos, all analytics
      rows, all diffs (channel + video), all change-logs (channel + video), all
      link rows (video_game_links), all rejected_video_imports, all
      calendar_entries, and — when the captured connection has zero remaining
      channels AND zero remaining videos — the `YoutubeConnection` itself.
- [ ] No orphaned rows remain (asserted by a sweep of every dependent table in
      the job spec).
- [ ] The job is idempotent (re-running on an already-gone channel is a no-op).
- [ ] Bulk `[revoke N]` on `/channels` index uses the same modal + same job.
- [ ] Full RSpec suite green; Brakeman / bundler-audit clean; design alignment
      with `docs/design.md` updated if the wide-modal pattern is new.

## Manual test recipe (umbrella)

A combined end-to-end recipe lives in 24c's sub-spec. Run that recipe first.
Then verify the bulk variant per 24e's recipe.

Teardown: re-seed via `bin/setup` if you want to repeat. The cascade is
destructive by design.

## Cross-stack scope

- **Rails web:** in scope across all five sub-specs.
- **MCP:** out of scope for this phase. The MCP `delete_records` tool already
  exists for `channel` and is sufficient for programmatic revocation; the
  cascade reuses the same job (24d) when the MCP path triggers a channel
  destroy. Out-of-band: confirm in the 24d sub-spec that the existing MCP
  channel-delete path routes through `DeleteChannelDataJob` rather than the
  default `dependent: :destroy` Rails-side cascade. If it does not, a tiny
  follow-up under `docs/orchestration/follow-ups.md` captures the gap (NOT in
  this phase).
- **CLI:** out of scope. The `pito` CLI's channel-delete surface uses the
  existing `/deletions/channel/:ids` framework. CLI parity work has its own
  follow-up under "CLI feature-parity sweep" in
  `docs/orchestration/follow-ups.md`; this phase does not touch it.
- **Website:** not in scope.

## Open questions (surface to user before sub-spec dispatch)

1. **`/settings/youtube` → 301 redirect, OR 404?** Architect recommends 301
   redirect to `/channels` for back-compat (browser bookmarks, browser history).
   The 301 lives in `config/routes.rb` until a hygiene sweep revisits it.
2. **Cascade scope — do notes attached to a channel's videos really die with the
   channel?** Architect note: in the current schema, Notes belong to Project,
   not directly to Channel or Video. They do NOT cascade through the channel
   destroy. The user note mentions "notes attached to videos belonging to this
   channel" — that surface does not exist today. The 24d sub-spec assumes no
   Notes are touched (Notes live on Project). Confirm or surface the missing
   schema link.
3. **CSV/JSON export "download channel data first" affordance in the modal?**
   Architect recommends NO for v1 (deferred). Confirm.
4. **Bulk-revoke from `/channels` index — keep the multi-select bulk-mode
   pattern (always-on checkboxes on channel rows), OR a one-shot bulk-revoke
   header link?** Architect recommends multi-select bulk mode matching the
   existing channels list bulk shape (the channels list already has bulk-delete;
   revoke piggybacks on the same checkbox state). 24e's sub-spec assumes this;
   confirm.
5. **YoutubeConnection cleanup — also check
   `Video.where(youtube_connection_id: connection_id).none?` in addition to
   channels.none?** Architect: yes, because `Video` has its own optional
   `youtube_connection_id` FK with `dependent: :nullify`, so a video could in
   theory still reference a connection even after its channel is gone. The 24d
   sub-spec captures this as the second branch of the YoutubeConnection-cleanup
   check. Confirm the interpretation matches user intent.
6. **`[revoke]` keyboard shortcut?** The keyboard shortcuts modal lists every
   page-level action. Should `[revoke]` get a key? Architect recommends NO
   (destructive + requires confirmation; no keyboard shortcut for safety,
   matching the absence of a shortcut for `[delete]`). Confirm.
