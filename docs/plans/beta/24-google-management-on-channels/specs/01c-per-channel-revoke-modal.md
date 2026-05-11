# 24c — Per-channel `[revoke]` action + wide-modal confirmation

## Goal

Add a `[revoke]` action to the channel show page heading-actions row. Clicking
it opens a wide-modal confirmation dialog displaying the full cascade footprint
(N videos, M analytics rows, D diff rows, L change-log rows, K link rows, R
rejected-import rows, C calendar entries) plus a hint that the Google OAuth
grant will be revoked if this is the last channel on the connection. The modal
offers `[cancel]` (closes the modal, no side effects) and `[confirm revoke]`
(enqueues `DeleteChannelDataJob` — defined in sub-spec 24d — then redirects to
`/channels` with a flash notice).

## Files touched

### Controllers

- `app/controllers/channel_revokes_controller.rb` — NEW. Two actions:
  - `GET /channels/:id/revoke` — renders the wide-modal view with live cascade
    counts computed inline. The `:id` matches the channel slug (UC-id) per Phase
    20 friendly URLs. Loads `@channel`, `@counts` (hash), and
    `@is_last_channel_on_connection`.
  - `POST /channels/:id/revoke` — accepts `confirm=yes` (yes/no boundary per
    project rule). On `confirm=yes`: enqueues
    `DeleteChannelDataJob.perform_async(channel.id, channel.youtube_connection_id)`,
    redirects to `/channels` with `notice: "channel revoke scheduled."`. On
    anything else: redirects back to the channel show with
    `alert: "revoke cancelled."`.
- `app/controllers/channels_controller.rb` — add the `[revoke]` link to the
  heading-actions row on the show view (no new action on this controller; the
  link targets `channel_revokes_controller`'s show endpoint).

### Views

- `app/views/channels/show.html.erb` — add `[revoke]` to the heading-actions
  row, inline with `[edit]` / `[star]` / `[unstar]`. Bracketed-link convention
  per project rule A — `[revoke]`, no inner spaces.
- `app/views/channel_revokes/show.html.erb` — NEW. Renders the wide-modal:
  - H1: `revoke channel "<title>"`
  - Modal body paragraph (one-sentence-per-line lead per project rule B):
    ```
    This will permanently delete:<br>
    {N} video(s)<br>
    {M} analytics record(s)<br>
    {D} diff record(s)<br>
    {L} change-log record(s)<br>
    {K} link record(s)<br>
    {R} rejected-import record(s)<br>
    {C} calendar entry (entries).<br>
    The Google OAuth grant will be revoked if this is the last channel on the
    connection.<br>
    This action cannot be undone.
    ```
  - `<form method="post" action="<channel_revoke_path>">` with `confirm=yes`
    hidden field and `authenticity_token`.
  - Buttons row, right-aligned: `[cancel]` (anchor to channel show),
    `[confirm revoke]` (submit).
- `app/views/channels/_revoke_modal.html.erb` — NEW shared partial. Same content
  as `channel_revokes/show.html.erb`, factored so sub-spec 24e (bulk variant)
  can render it with a `count: N` channel preview list.

### Routes

- `config/routes.rb`:
  - `get "/channels/:id/revoke", to: "channel_revokes#show", as: :channel_revoke`
  - `post "/channels/:id/revoke", to: "channel_revokes#create"`

  (Two routes, one path, distinct HTTP verbs — mirror the `DeletionsController`
  / `SyncsController` pattern.)

### Counts service

- `app/services/channel_revoke_counts.rb` — NEW. Plain service object with a
  single class method `.for(channel)` returning a hash:
  ```ruby
  {
    videos: Integer,
    analytics: Integer,     # sum across all channel_* and video_* analytics tables
    diffs: Integer,         # channel_diffs + sum of video_diffs across channel's videos
    change_logs: Integer,   # channel_change_logs + sum of video_change_logs across channel's videos
    links: Integer,         # sum of video_game_links across channel's videos
    rejected_imports: Integer,
    calendar_entries: Integer  # channel's calendar_entries + sum across channel's videos
  }
  ```
  Internally uses one `COUNT(*)` per table, all wrapped in a single
  read-committed transaction so the totals are consistent for the modal render.
  Service is reused by 24d (the job re-derives the counts at execute time for
  the flash message).

### Specs

- `spec/requests/channel_revokes_spec.rb` — NEW. Covers:
  - `GET /channels/:id/revoke` happy path (200, modal body renders, counts are
    integers, title falls back to slug when blank).
  - `GET /channels/:id/revoke` for a non-existent slug → 404.
  - `GET /channels/:id/revoke` when unauthenticated → redirects to login.
  - `POST /channels/:id/revoke` with `confirm=yes` enqueues
    `DeleteChannelDataJob` with `(channel.id, channel.youtube_connection_id)`
    and redirects to `/channels`.
  - `POST /channels/:id/revoke` without `confirm=yes` redirects back without
    enqueueing.
  - `POST /channels/:id/revoke` with `confirm=true` (legacy boundary violation)
    redirects back without enqueueing — confirms the yes/no boundary rule.
  - `POST /channels/:id/revoke` when unauthenticated → redirects to login, no
    job enqueued.
- `spec/services/channel_revoke_counts_spec.rb` — NEW. Covers:
  - Empty channel returns all zeros.
  - Channel with N videos + analytics rows + diffs + change-logs + links +
    rejected-imports + calendar entries returns the right sums.
  - Other channels' rows are NOT counted (isolation).
- `spec/views/channels/_revoke_modal.html.erb_spec.rb` — NEW. Covers:
  - Renders all seven cascade counts.
  - Renders the last-channel hint when applicable.
  - `[cancel]` link targets the right path.
  - `[confirm revoke]` form posts to the right path with `confirm=yes`.
- `spec/system/channel_revoke_spec.rb` — NEW. Critical user journey per the spec
  pyramid item #10. Single happy-path scenario:
  1. Visit a channel show.
  2. Click `[revoke]`.
  3. Verify the modal renders.
  4. Click `[confirm revoke]`.
  5. Assert the redirect + flash notice.
  6. Assert the job was enqueued.

## Acceptance

- [ ] `[revoke]` link appears on the channel show heading-actions row, inline
      with `[edit]` / `[star]` / `[unstar]`. Bracketed-link convention
      compliant.
- [ ] `GET /channels/:id/revoke` renders the wide-modal with title, the seven
      cascade counts, the last-channel hint, and `[cancel]` /
      `[confirm     revoke]` buttons.
- [ ] Modal counts are accurate against the DB at render time (verified by the
      service spec + request spec).
- [ ] `POST /channels/:id/revoke` with `confirm=yes` enqueues
      `DeleteChannelDataJob.perform_async(channel.id,     channel.youtube_connection_id)`
      and redirects to `/channels`.
- [ ] `POST /channels/:id/revoke` without `confirm=yes` does NOT enqueue any
      job; it redirects back to the channel show.
- [ ] Unauthenticated requests to either endpoint redirect to the login surface
      (via existing `Sessions::AuthConcern`).
- [ ] No `data-turbo-confirm`, no JS `confirm()` / `alert()` / `prompt()` — the
      wide-modal is a server-rendered page (per `CLAUDE.md` hard rule).
- [ ] `[cancel]` anchor returns the user to the channel show. No JavaScript
      gymnastics required.
- [ ] Title fallback works: when `channel.title` is blank, the modal renders the
      UC-id slug instead.
- [ ] Yes/no boundary observed at every external surface (`confirm=yes` is the
      only accepted truthy value).
- [ ] `docs/design.md` updated with the wide-modal pattern (or a callout in the
      existing modal section if one exists).

## Manual test recipe

1. `bin/dev`.
2. Visit `http://127.0.0.1:3027/channels/<UC-id>` (any channel).
3. In the heading-actions row, click `[revoke]`. Expect: the wide-modal page
   renders with `revoke channel "<title>"` heading and the seven cascade counts.
4. Click `[cancel]`. Expect: browser returns to the channel show page; no data
   has changed.
5. Revisit the revoke modal via `[revoke]` again. Click `[confirm revoke]`.
6. Expect: a redirect to `/channels` with a flash notice
   `channel revoke scheduled.`. The channel is still in the index UNTIL the
   Sidekiq job runs (which it does immediately in `bin/dev` because Sidekiq is
   alive).
7. Refresh `/channels`. The channel is gone. Verify in `bin/rails console`:
   `Channel.find_by(channel_url: "<...>")` → `nil`. (Detailed cascade
   verification belongs to 24d's recipe.)

Teardown: re-seed the DB via `bin/setup` if you want to repeat the test.

## Cross-stack scope

- **Rails web:** in scope.
- **MCP:** not in scope. The existing `delete_records` tool for `channel`
  remains and goes through the same job (per 24d open question).
- **CLI:** not in scope.
- **Website:** not in scope.

## Open questions

1. Wide-modal as a separate page (`GET /channels/:id/revoke` rendering a full
   HTML response) vs. Turbo Frame modal overlaid on the channel show? Architect
   recommendation: separate page. Reasons: (a) the project's hard rule against
   `data-turbo-confirm` and JS modals points to server-rendered confirmation
   pages; (b) the existing `shared/_action_screen.html.erb` framework is exactly
   this pattern, just visually plainer. The wide-modal is a styled action-screen
   with a structured count block.
2. Should the modal also surface the connection's email when the last-channel
   hint applies? E.g., "The OAuth grant for `<email>` will be revoked."
   Architect recommendation: yes — it makes the consequence concrete.
3. Modal copy: the umbrella spec locks the canonical string. Confirm the
   one-sentence-per-line variant rendered here matches it (the umbrella's
   single-paragraph form is the wire copy; the modal's structured list is the
   rendered form).
4. If the channel's `youtube_connection_id` is NULL (no connection), the "Google
   OAuth grant" hint is irrelevant. Should the modal drop that line when there's
   no connection? Architect recommendation: yes — render the hint conditionally.
