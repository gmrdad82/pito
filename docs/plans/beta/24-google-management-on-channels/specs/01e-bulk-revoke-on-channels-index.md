# 24e — Bulk `[revoke N]` on `/channels` index

## Goal

Port the bulk-revoke pattern from `/settings/youtube` to `/channels`. The
`/channels` index already supports always-on multi-select checkboxes (existing
bulk-delete pattern); this sub-spec adds a `[revoke N]` bulk action button that
opens the wide-modal — same modal partial as sub-spec 24c — with an aggregated
cascade summary for all selected channels. Confirm enqueues one
`DeleteChannelDataJob` per channel.

This sub-spec ships AFTER 24c so the modal partial it reuses exists.

## Files touched

### Controllers

- `app/controllers/channels/bulk_revokes_controller.rb` — NEW. Two actions:
  - `GET /channels/revokes/:ids` — `:ids` is a comma-separated list (matches the
    existing `/deletions/:type/:ids` URL pattern per `CLAUDE.md` hard rules —
    bulk-as-foundation). Loads the N channels, aggregates the cascade counts
    (sum of seven per-channel counts), determines which connections will be
    orphaned by the bulk revoke, and renders the wide-modal partial.
  - `POST /channels/revokes/:ids` — with `confirm=yes`, enqueues one
    `DeleteChannelDataJob.perform_async(channel.id, channel.youtube_connection_id)`
    per channel (the job's idempotency + connection orphan-check handle
    interleaving: if two channels share a connection, the second job's cleanup
    branch is the one that destroys the connection). Redirects to `/channels`
    with `notice: "N channel revoke(s) scheduled."`. Without `confirm=yes`:
    redirects back to `/channels` with cancel notice.

### Views

- `app/views/channels/index.html.erb` — extend the existing bulk-mode action bar
  with a `[revoke N]` button alongside `[delete N]`. The button only renders
  when the user has at least one channel selected (existing bulk-mode UI handles
  the visibility via Stimulus).
- `app/views/channels/_revoke_modal.html.erb` — extend to accept either a
  single-channel context (sub-spec 24c) OR a multi-channel context. In the
  multi-channel case:
  - H1: `revoke N channels`
  - Body lists the N channels by title (or UC-id slug fallback), capped at the
    first 10 with an `…and M more` line.
  - The aggregated count block uses the same seven categories with summed
    totals.
  - The last-channel hint enumerates which connections will be orphaned (e.g.,
    "The OAuth grants for `<email1>`, `<email2>` will be revoked.").

### Routes

- `config/routes.rb`:
  - `get "/channels/revokes/:ids", to: "channels/bulk_revokes#show", as: :channels_bulk_revoke`
  - `post "/channels/revokes/:ids", to: "channels/bulk_revokes#create"`
  - Constraint: `:ids` matches `[\d,]+` (digit-and-comma; URL builder uses
    integer IDs, not slugs, matching the existing `/deletions/:type/:ids`
    convention — confirm against `routes.rb` to keep consistency).

### Specs

- `spec/requests/channels/bulk_revokes_spec.rb` — NEW. Covers:
  - `GET /channels/revokes/1,2,3` renders modal with three channels listed,
    aggregated counts, list of connections-to-be-orphaned (where applicable).
  - `GET /channels/revokes/1` (single-element bulk per `CLAUDE.md` bulk-as-
    foundation rule) renders the same modal partial in single-channel mode.
  - `GET /channels/revokes/9999` (non-existent id) returns 404.
  - `POST /channels/revokes/1,2,3` with `confirm=yes` enqueues three
    `DeleteChannelDataJob` calls — one per channel — and redirects to
    `/channels` with notice `"3 channel revokes scheduled."`.
  - `POST /channels/revokes/1,2,3` without `confirm=yes` enqueues nothing.
  - `POST /channels/revokes/1,2,3` when unauthenticated → login redirect, no
    jobs enqueued.
- `spec/views/channels/_revoke_modal.html.erb_spec.rb` (extends the file from
  24c) — add multi-channel context cases:
  - Three channels listed by title, with truncation to first 10.
  - Aggregated counts summed correctly.
  - Connection-orphan enumeration when applicable.

### Existing bulk-mode plumbing

- The existing `bulk_select_controller.js` Stimulus controller handles the
  selection state. The new `[revoke N]` button hooks into the same
  `bulk-select-target="actionButton"` (or whatever the existing bulk-delete
  button uses) so the button enables / disables in sync with the checkbox state.
  No new Stimulus controller is added in this sub-spec.

## Acceptance

- [ ] `/channels` index renders `[revoke N]` in the bulk-mode action bar
      alongside `[delete N]` when at least one channel checkbox is selected.
- [ ] Clicking `[revoke N]` navigates to
      `/channels/revokes/<comma-separated-ids>`.
- [ ] The bulk modal renders the N channels, aggregated cascade counts, and the
      list of connections that will be orphaned.
- [ ] Confirming the bulk modal enqueues exactly N `DeleteChannelDataJob` calls,
      one per channel.
- [ ] Cancelling the bulk modal returns the user to `/channels` with no side
      effects.
- [ ] Single-element bulk (one id) renders the same modal partial in
      single-channel mode — bulk-as-foundation per `CLAUDE.md`.
- [ ] No `data-turbo-confirm` / JS `confirm` anywhere on the bulk path.
- [ ] Full RSpec suite green.

## Manual test recipe

1. `bin/dev`.
2. Visit `http://127.0.0.1:3027/channels`.
3. Toggle the channels list into bulk-select mode (existing UI affordance).
4. Check two or three channels. Expect: the `[revoke N]` button appears in the
   bulk-mode action bar with the count interpolated.
5. Click `[revoke N]`. Expect: the wide-modal renders with the selected channels
   listed by title, the aggregated count block, and a list of connections that
   will be revoked (when applicable).
6. Click `[cancel]`. Expect: return to `/channels` with no state change.
7. Repeat steps 3–5. Click `[confirm revoke]`. Expect: redirect to `/channels`
   with the multi-channel flash notice. Refresh — the selected channels are
   gone. Verify in `bin/rails console` per 24d's manual recipe.

Teardown: re-seed via `bin/setup` to repeat.

## Cross-stack scope

- **Rails web:** in scope.
- **MCP:** not in scope. The MCP `delete_records` tool already accepts a bulk
  `ids` array; if routed through `DeleteChannelDataJob` per 24d, the bulk path
  is consistent.
- **CLI:** not in scope.
- **Website:** not in scope.

## Open questions

1. URL shape: `/channels/revokes/:ids` matches `/deletions/:type/:ids`
   convention. Alternative: nest under deletions
   (`/deletions/channel_revoke/:ids`). Architect recommendation: dedicated
   namespace because revoke ≠ delete semantically (revoke cascades to
   YoutubeConnection; plain delete does not).
2. Bulk modal cap: first 10 channels listed + `…and M more`. Is 10 the right
   number? Architect recommendation: 10 — matches the existing "channel labels"
   cap on the now-removed Settings Google card (it capped at 5; the bulk-revoke
   modal benefits from a slightly higher cap because users are reading
   consequences, not summaries).
3. Connection-orphan enumeration: aggregate the connection_ids that would lose
   all their channels in the bulk operation. The check is "channel ids being
   revoked covers every channel of connection X" AND "no surviving videos
   reference connection X". Confirm the second condition is checked at modal
   render time (it's expensive on dense installs but accurate).
4. Should `[revoke N]` be available outside bulk-select mode (e.g., as a
   page-level toolbar action)? Architect recommendation: no — bulk-revoke
   requires multi-select; without it, users use the per-channel `[revoke]` on
   the show page.
