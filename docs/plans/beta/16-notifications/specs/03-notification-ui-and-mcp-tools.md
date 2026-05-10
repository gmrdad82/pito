# Phase 16 §3 — Notification UI + MCP Tools

> **Status:** dispatched 2026-05-10. Two primary lanes: **rails** (UI) + **mcp**
> (MCP tools). Builds on §1's `Notification` model + §2's formatter. Closes
> Phase 16.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 8. Resolved ambiguity #6
>   (all-users-see-all; install-level webhooks).
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. §"In-app" + §"MCP pull" sections.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope.
> - `docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`
>   — §1. `Notification` model + scopes (`unread`, `recent`).
> - `docs/plans/beta/16-notifications/specs/02-notification-formatter.md` — §2.
>   `NotificationFormatter::InApp` / `Mcp` payloads consumed here.
> - `docs/design.md` — design system. Lowercase, monospace 13px, bracketed-link
>   convention, `cursor: pointer` on every clickable, no animation. The
>   notification surface MUST follow lowercase discipline + bracketed-link
>   convention.
> - `CLAUDE.md` — hard rules: no JS `confirm` / `alert` / `prompt`;
>   bulk-as-foundation URL pattern (`/<action>s/:type/:ids`); `yes` / `no` for
>   external booleans; Sidekiq Web at `/sidekiq` is NOT linked from nav.

## Goal

Ship the in-app notification inbox at `/notifications` (an index + detail +
mark-read flow) and the four MCP tools that expose the same rows to Claude
Mobile / Web sessions. Render an unread-count badge in the global nav header;
live-update the badge via Turbo Stream broadcast when the scheduler inserts a
new row OR a user marks a row read. Honor the all-users-see-all read state per
§1's Q1: any user marking a row read marks it for all users; the badge reflects
the install-wide unread count.

This is realignment work unit 8's UI + MCP tier.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Routes.** `GET /notifications` (index), `GET /notifications/:id` (detail), `PATCH /notifications/:id/read` (mark read), `PATCH /notifications/:id/unread` (mark unread), bulk: `PATCH /notifications/mark_read` (with `ids` param — bulk-as-foundation per CLAUDE.md), `PATCH /notifications/mark_all_read` (no params). Detail surface is light: title, body, timestamp, source links; clicking the row's url is a separate action from marking read.   |
| Q2  | **Auto-mark-on-click.** When a user clicks the notification's `url` link, the row marks read AS A SIDE EFFECT. Implementation: the link is wrapped in a small Stimulus controller that issues a fire-and-forget PATCH to `/notifications/:id/read` BEFORE following the link (so the badge decrements immediately). NO `confirm()` / `alert()`. NO `data-turbo-confirm`. The browser is told `data-action="click->notification-link#markReadAndNavigate"`. |
| Q3  | **Unread badge in nav.** A small bracketed counter `[ <N> ]` next to the `notifications` nav link when `unread_count > 0`. Hidden when zero. Live-updated via Turbo Stream broadcast targeted at a stable `dom_id "notifications_badge"`.                                                                                                                                                                                                                  |
| Q4  | **Live update via Turbo Streams.** `Notification.after_create_commit`, `after_update_commit { broadcast_replace_to "notifications_badge", ... }` re-renders the badge on every insert and on every read-state change. Index page also uses Turbo Streams to insert new rows at the top live (`broadcast_prepend_to "notifications_index", ...`).                                                                                                           |
| Q5  | **Index ordering + pagination.** Unread first (ordered by `created_at DESC`), then read (ordered by `created_at DESC`). Pagination via the project-standard pattern (page param `?page=N`, 50 rows per page). Per `docs/design.md` `[ next page ]` / `[ prev page ]` brackets at the bottom.                                                                                                                                                               |
| Q6  | **Empty state.** A single line: `no notifications yet.` (lowercase, period per `docs/design.md` punctuation rule). No image / illustration.                                                                                                                                                                                                                                                                                                                |
| Q7  | **Filtering.** Index supports `?filter=unread` (default `?filter=all`), `?kind=<kind>` (single value, optional), `?severity=<severity>` (single value, optional). NO multi-select in v1. Filter cluster at top: `[ all ]` / `[ unread ]`.                                                                                                                                                                                                                  |
| Q8  | **Detail view scope.** `/notifications/:id` shows: title, severity badge (lowercase text, no icon), body (rendered HTML from §2's formatter), timestamp (relative + absolute), source link (the notification's `url`), per-channel delivery state (`in_app: yes`, `discord: <delivered_at iso or "pending">`, `slack: <delivered_at iso or "pending">`), `last_error` if non-blank. Bracketed actions: `[ mark read ]` / `[ mark unread ]` / `[ back ]`.   |
| Q9  | **Mark-read UX paths.** Three:                                                                                                                                                                                                                                                                                                                                                                                                                             |
|     | (a) Click the source link → auto-mark read (Q2).                                                                                                                                                                                                                                                                                                                                                                                                           |
|     | (b) Click `[ mark read ]` on the index row OR detail page.                                                                                                                                                                                                                                                                                                                                                                                                 |
|     | (c) Click `[ mark all read ]` at the top of the index.                                                                                                                                                                                                                                                                                                                                                                                                     |
|     | Mark-read does NOT route through the action confirmation page framework because it is non-destructive (per `docs/design.md` "destructive / dangerous actions only"). The bulk URL pattern `/notifications/mark_read?ids=A,B,C` is used for symmetry with the rest of the app (`/<action>s/:type/:ids`).                                                                                                                                                    |
| Q10 | **Tenant-free.** No `tenant_id` filter in queries.                                                                                                                                                                                                                                                                                                                                                                                                         |
| Q11 | **MCP tools — four.** All on `app` scope (per ADR 0004):                                                                                                                                                                                                                                                                                                                                                                                                   |
|     | (a) `notifications_list` — paginated. Filter by `unread: yes/no`, `kind`, `severity`. Returns a list per §2's `NotificationFormatter::Mcp` shape.                                                                                                                                                                                                                                                                                                          |
|     | (b) `notifications_unread_count` — returns `{count: <int>}`.                                                                                                                                                                                                                                                                                                                                                                                               |
|     | (c) `notifications_mark_read` — accepts `ids: [...]` array. Two-step `confirm: yes/no` per CLAUDE.md (although this is non-destructive, the bulk surface shape requires the confirm flag for symmetry; first call returns a preview, second with `confirm: yes` performs the action). See Open question #4.                                                                                                                                                |
|     | (d) `notifications_mark_all_read` — no params. Same two-step `confirm: yes/no`.                                                                                                                                                                                                                                                                                                                                                                            |
| Q12 | **MCP tool boundary booleans.** Per CLAUDE.md, every external boolean uses `"yes"` / `"no"`. Tools accept `unread: "yes"` / `"no"` (NOT `true`/`false`). The `read` field in returned rows is `"yes"` / `"no"`. The `confirm` flag is `"yes"` / `"no"`.                                                                                                                                                                                                    |
| Q13 | **Authentication / scope.**                                                                                                                                                                                                                                                                                                                                                                                                                                |
|     | - In-app: every route requires authentication via `Sessions::AuthConcern`. No per-user filtering — every authenticated user sees the full install-wide stream.                                                                                                                                                                                                                                                                                             |
|     | - MCP: every tool gates on the `app` scope via `Mcp::ToolAuth.require_scope!(:app)`.                                                                                                                                                                                                                                                                                                                                                                       |
| Q14 | **No CLI.** Per realignment work unit 10. CLI parity for the notification surface is a separate dispatch.                                                                                                                                                                                                                                                                                                                                                  |
| Q15 | **Test posture.** Exhaustive per the brief.                                                                                                                                                                                                                                                                                                                                                                                                                |

## Migration posture (LOCKED)

**No schema changes.** This spec is purely UI / controller / route / MCP-tool
work on top of §1's models and §2's formatters.

If the implementation agent finds a missing column / index, STOP and surface —
schema gaps belong in §1.

## Files touched

### Routes

- `config/routes.rb` (light edit) — add the notifications surface inside the
  existing `Rails.application.routes.draw` block. Sketch:
  ```ruby
  resources :notifications, only: %i[index show] do
    member do
      patch :read
      patch :unread
    end
    collection do
      patch :mark_read   # accepts ids[]
      patch :mark_all_read
    end
  end
  ```
  The bulk endpoint accepts `params[:ids]` as a comma-separated string per the
  existing project convention, OR as an array — implementation agent confirms
  which the project uses (the `DeletionsController` / `SyncsController`
  precedent dictates the shape).

### Controllers

- `app/controllers/notifications_controller.rb` (new) — actions:
  - `index` — paginated list per Q5; honors `?filter=` / `?kind=` /
    `?severity=`. Renders `notifications/index.html.erb`.
  - `show` — single row detail. Renders `notifications/show.html.erb`.
  - `read` (member PATCH) — `n.mark_read!`; responds with Turbo Stream that
    updates the row + the badge.
  - `unread` (member PATCH) — `n.mark_unread!`; same shape.
  - `mark_read` (collection PATCH) — bulk; `ids = params[:ids].split(",")`;
    `Notification.where(id: ids).update_all(in_app_read_at: Time.current)`.
    Broadcasts the badge update.
  - `mark_all_read` (collection PATCH) —
    `Notification.unread.update_all(in_app_read_at: Time.current)`. Broadcasts.
  - All actions inherit the `Sessions::AuthConcern` (default in
    `ApplicationController`).

### Views (ERB)

- `app/views/notifications/index.html.erb` (new) — list view per
  `docs/design.md`. Lowercase headings, monospace, bracketed-link filter
  cluster.
- `app/views/notifications/_notification.html.erb` (new) — single-row partial.
  Renders title, glyph, severity badge, timestamp, `[ mark read ]` action. Click
  on title navigates to `show` (NOT the source URL — Q2's auto-mark-on-click
  governs the source URL separately on the detail page).
- `app/views/notifications/show.html.erb` (new) — detail view per Q8.
- `app/views/layouts/_nav.html.erb` (light edit) — add the notifications nav
  link with the badge fragment. Wrap the badge in a `<turbo-frame>` or
  `<div data-controller="notifications-badge">` scoped element so live updates
  re-render in place.
- `app/views/notifications/_badge.html.erb` (new) — extracted partial rendering
  `[ <N> ]` when `unread_count > 0`, else empty.

### Stimulus controllers

- `app/javascript/controllers/notification_link_controller.js` (new) — Q2's
  auto-mark-on-click. Issues a `fetch(...)` PATCH to `/notifications/:id/read`
  then navigates. Falls back to direct navigation if the PATCH fails (the link
  still works).
- `app/javascript/controllers/index.js` (light edit) — register the new
  controller.

### Models (Turbo Stream callbacks)

- `app/models/notification.rb` (light edit on §1's model) — add the Turbo Stream
  broadcast callbacks:
  ```ruby
  after_create_commit  -> { broadcast_prepend_later_to "notifications_index" }
  after_create_commit  -> { broadcast_replace_to "notifications_badge", target: "notifications_badge", partial: "notifications/badge", locals: { unread_count: Notification.unread.count } }
  after_update_commit  -> { broadcast_replace_to "notifications_badge", target: "notifications_badge", partial: "notifications/badge", locals: { unread_count: Notification.unread.count } }
  after_update_commit  -> { broadcast_replace_to "notifications_index", target: dom_id(self), partial: "notifications/notification", locals: { notification: self } }
  ```
  The implementation agent confirms the Turbo Stream API exact signature against
  the project's existing broadcast usage. The `after_create_commit` enqueue may
  use `_later_to` for performance; read-state changes are immediate.

### MCP tools

- `app/mcp/tools/notifications_list.rb` (new) — params: `unread: "yes"/"no"`
  (optional), `kind` (optional, one of the eight enum values), `severity`
  (optional), `page` (int, default 1), `per_page` (int, default 25, max 100).
  Returns a hash with `notifications: [...]` (per
  `NotificationFormatter::Mcp.payload_for`) +
  `pagination: {page:, per_page:, total:, total_pages:}`. Gates on `app` scope.
- `app/mcp/tools/notifications_unread_count.rb` (new) — no params. Returns
  `{count: <int>}`. Gates on `app` scope.
- `app/mcp/tools/notifications_mark_read.rb` (new) — params: `ids: [...]` (array
  of UUID strings), `confirm: "yes"/"no"`. First call (`confirm: "no"` or
  absent) returns a preview hash: `{would_mark_read: <count>, ids: [...]}`.
  Second call (`confirm: "yes"`) performs the bulk update; returns
  `{marked_read: <count>}`. Gates on `app` scope.
- `app/mcp/tools/notifications_mark_all_read.rb` (new) — params:
  `confirm: "yes"/"no"`. Same two-step pattern; preview returns the current
  unread count.
- `app/mcp/tool_registry.rb` or equivalent (light edit) — register the four new
  tools. The implementation agent confirms the registration pattern against the
  existing tools (`save_note`, `list_docs`, `read_doc`).

### Decorators (optional)

- `app/decorators/notification_decorator.rb` (new, OR fold into the formatter —
  implementation agent picks; recommendation: NO decorator, the formatter is the
  canonical render layer).

### Out of scope (this spec)

- Settings UI for `discord_enabled` / `slack_enabled` toggles — follow-up.
- CLI parity (`extras/cli/`). Realignment work unit 10.
- Schema changes — §1.
- Formatter logic — §2.
- Webhook delivery — §1.
- Per-user notification preferences — non-goal (Q1 of §1).
- Notification grouping / coalescing — Open question.
- Email / push notification surfaces — non-goal.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Routes

- [ ] `GET /notifications` returns 200 for an authenticated user.
- [ ] `GET /notifications` redirects to `/login` for an unauthenticated request.
- [ ] `GET /notifications/:id` returns 200 for a valid id; 404 for an unknown
      id.
- [ ] `PATCH /notifications/:id/read` updates `in_app_read_at` and returns Turbo
      Stream.
- [ ] `PATCH /notifications/:id/unread` clears `in_app_read_at` and returns
      Turbo Stream.
- [ ] `PATCH /notifications/mark_read` with `ids=A,B,C` updates the three rows
      and broadcasts the badge update.
- [ ] `PATCH /notifications/mark_all_read` updates every unread row.

### Index view

- [ ] Renders unread rows first, ordered by `created_at DESC`.
- [ ] Renders read rows after, ordered by `created_at DESC`.
- [ ] Filter cluster `[ all ]` / `[ unread ]` is visible at top.
- [ ] `?filter=unread` filters to unread only.
- [ ] `?kind=sync_error` filters to that kind only.
- [ ] `?severity=urgent` filters to that severity only.
- [ ] Empty state shows `no notifications yet.` (lowercase, period).
- [ ] Each row shows: glyph (per Q6 emoji map of §2), title, severity badge
      (text), `time_ago_in_words`, `[ mark read ]` (only if unread).
- [ ] Each row's title links to `/notifications/:id` (NOT the source URL).
- [ ] `[ mark all read ]` appears at the top when unread_count > 0.
- [ ] Pagination: `[ next page ]` / `[ prev page ]` at bottom; 50 rows per page.

### Show view

- [ ] Renders title, severity, body (HTML from `NotificationFormatter::InApp`),
      `fires_at_relative` + `fires_at_iso`.
- [ ] If `url` is set, renders a `[ open source ]` bracketed link wrapped in the
      `notification-link` Stimulus controller.
- [ ] Clicking `[ open source ]` issues a PATCH to `/notifications/:id/read` and
      then navigates.
- [ ] Renders per-channel delivery state: `in_app: yes`, `discord:     <iso>` or
      `discord: pending`, `slack: <iso>` or `slack: pending`.
- [ ] Renders `last_error` if non-blank.
- [ ] `[ mark read ]` / `[ mark unread ]` toggles depending on state.
- [ ] `[ back ]` returns to the index.
- [ ] No `confirm()` / `alert()` / `prompt()` / `data-turbo-confirm` anywhere in
      the rendered HTML.

### Badge

- [ ] When `Notification.unread.count == 0`, the badge fragment renders empty
      (no bracket).
- [ ] When `unread.count > 0`, the badge renders `[ N ]` next to the
      `notifications` nav link.
- [ ] When a new `Notification` row is inserted, the badge re-renders live via
      Turbo Stream (verified in a Capybara system spec with
      `assert_turbo_stream` or similar).
- [ ] When a row is marked read, the badge decrements live.
- [ ] When the last unread row is read, the badge disappears.

### MCP tools

- [ ] `notifications_list` returns paginated results. Default page 1, per_page
      25, max 100.
- [ ] `notifications_list({unread: "yes"})` returns only unread rows.
- [ ] `notifications_list({kind: "sync_error"})` filters by kind.
- [ ] `notifications_list({severity: "urgent"})` filters by severity.
- [ ] Each row in the response matches `NotificationFormatter::Mcp.payload_for`
      output.
- [ ] `read` field in each row is `"yes"` / `"no"` (string).
- [ ] `notifications_unread_count` returns `{count: <int>}`.
- [ ] `notifications_mark_read({ids: [...], confirm: "no"})` returns a preview
      (no DB mutation).
- [ ] `notifications_mark_read({ids: [...], confirm: "yes"})` performs the
      update.
- [ ] `notifications_mark_read({ids: [<uuid_not_in_db>], confirm: "yes"})`
      returns `{marked_read: 0}` (graceful no-op).
- [ ] `notifications_mark_all_read({confirm: "no"})` returns the current unread
      count as preview.
- [ ] `notifications_mark_all_read({confirm: "yes"})` updates all unread rows.
- [ ] All four tools require the `app` scope (verified by attempting a call with
      a `dev`-only token — should fail with the standard scope error).
- [ ] All four tools require an authenticated MCP session (verified by an
      unauthenticated request returning the standard 401).

### Stimulus

- [ ] `notification_link_controller.js` issues PATCH then navigates.
- [ ] On PATCH failure (e.g., 500), the controller still navigates (defensive —
      the link works even if the mark-read fails).
- [ ] No `window.confirm` / `alert` / `prompt` / `data-turbo-confirm` in the
      controller code.

### Boundary discipline

- [ ] MCP tool definitions declare boolean params as `enum: ["yes",     "no"]`
      strings (per CLAUDE.md hard rule).
- [ ] In-app form params for any boolean are `"yes"` / `"no"` if they cross the
      URL or JSON boundary; internal storage stays Boolean.

## Test sweep

The implementation agent owns the full sweep. Each spec name below MUST end up
in the repo on green.

- `spec/requests/notifications_spec.rb` (new) — full request matrix.
- `spec/system/notifications_index_spec.rb` (new) — Capybara end-to-end on the
  index.
- `spec/system/notifications_show_spec.rb` (new).
- `spec/system/notifications_badge_live_update_spec.rb` (new) — Turbo Stream
  live update behavior.
- `spec/javascript/controllers/notification_link_controller_test.js` (new) —
  Stimulus controller unit test.
- `spec/mcp/tools/notifications_list_spec.rb` (new).
- `spec/mcp/tools/notifications_unread_count_spec.rb` (new).
- `spec/mcp/tools/notifications_mark_read_spec.rb` (new).
- `spec/mcp/tools/notifications_mark_all_read_spec.rb` (new).
- `spec/views/notifications/index_html_erb_spec.rb` (new — light view spec for
  the empty-state copy + filter cluster).
- `spec/views/notifications/show_html_erb_spec.rb` (new).
- `spec/views/layouts/_nav_html_erb_spec.rb` (light edit — assert the badge
  partial is embedded).

### Required test cases (exhaustive — implementation agent enumerates each)

#### `spec/requests/notifications_spec.rb`

- [ ] **GET /notifications (happy)**: 200; renders index.
- [ ] **GET /notifications (unauthenticated)**: 302 to `/login`.
- [ ] **GET /notifications?filter=unread**: only unread rows.
- [ ] **GET /notifications?filter=all**: all rows.
- [ ] **GET /notifications?kind=sync_error**: filters by kind.
- [ ] **GET /notifications?kind=invalid**: 422 OR ignored (architect picks:
      ignored — degrades gracefully). Spec asserts the choice.
- [ ] **GET /notifications?severity=urgent**: filters.
- [ ] **GET /notifications?page=2**: pagination works.
- [ ] **GET /notifications/:id (happy)**: 200.
- [ ] **GET /notifications/:id (not found)**: 404.
- [ ] **PATCH /notifications/:id/read (happy)**: stamps `in_app_read_at`;
      returns Turbo Stream.
- [ ] **PATCH /notifications/:id/read (already read)**: idempotent (re-stamps
      the timestamp; no error).
- [ ] **PATCH /notifications/:id/unread (happy)**: clears `in_app_read_at`.
- [ ] **PATCH /notifications/mark_read (bulk happy)**: updates the supplied ids.
- [ ] **PATCH /notifications/mark_read with stray id**: only valid ids update;
      the stray is silently ignored.
- [ ] **PATCH /notifications/mark_all_read**: all unread → read.
- [ ] **All routes 401 without auth**: matrix assertion.

#### `spec/system/notifications_index_spec.rb`

- [ ] Visits `/notifications`; sees the index.
- [ ] Empty state: `no notifications yet.` visible.
- [ ] With one unread + one read row: unread first.
- [ ] Click `[ mark read ]` on a row: row updates inline; badge decrements.
- [ ] Click `[ mark all read ]`: all rows flip read; badge disappears.
- [ ] `[ all ]` / `[ unread ]` filter cluster works.

#### `spec/system/notifications_show_spec.rb`

- [ ] Visits `/notifications/:id`; sees title + body + delivery state.
- [ ] Click `[ mark read ]`: stamps; UI updates.
- [ ] Click `[ open source ]`: navigates to the source URL; the row flips read.
- [ ] Per-channel delivery state renders correctly (yes / iso / pending).

#### `spec/system/notifications_badge_live_update_spec.rb`

- [ ] Open the index page; insert a `Notification` row from another session; the
      badge updates live (Capybara `assert_selector` with Turbo Stream wait).
- [ ] Mark a row read from one tab; the other tab's badge decrements live.
- [ ] When the last unread is read, the badge disappears live.

#### `spec/mcp/tools/notifications_list_spec.rb`

- [ ] Authenticated `app`-scope call: returns paginated rows.
- [ ] `dev`-only-scope call: rejected with the standard scope error.
- [ ] Unauthenticated call: 401.
- [ ] `unread: "yes"` filters.
- [ ] `unread: "no"` returns read rows only.
- [ ] `kind: "sync_error"` filters.
- [ ] `severity: "urgent"` filters.
- [ ] `page: 2` paginates.
- [ ] `per_page: 100` honored.
- [ ] `per_page: 1000` capped at 100.
- [ ] Each returned row has `read` as a string `"yes"` / `"no"`.
- [ ] **Smuggle `tenant_id` into the params (flaw test)**: ignored; response
      unchanged.
- [ ] **Smuggle a UUID for a deleted row (flaw test)**: not present in response;
      no error.

#### `spec/mcp/tools/notifications_unread_count_spec.rb`

- [ ] Authenticated `app` call returns `{count: <int>}`.
- [ ] `dev`-only call rejected.
- [ ] Unauthenticated 401.

#### `spec/mcp/tools/notifications_mark_read_spec.rb`

- [ ] `confirm: "no"` returns preview; no DB mutation.
- [ ] `confirm: "yes"` performs the update.
- [ ] `confirm: <missing>` treated as `"no"`.
- [ ] `confirm: "true"` (wrong value) rejected with a clear error.
- [ ] `ids: []` empty array → `marked_read: 0`.
- [ ] `ids: [<unknown>]` → `marked_read: 0` (no error).
- [ ] `ids` containing a mix of known + unknown: only known updated.
- [ ] `app` scope required.
- [ ] **Smuggle a malformed UUID (flaw test)**: rejected with a clear error.

#### `spec/mcp/tools/notifications_mark_all_read_spec.rb`

- [ ] `confirm: "no"` returns preview with `unread_count`.
- [ ] `confirm: "yes"` updates all unread rows.
- [ ] `app` scope required.

#### Edge cases (across the spec set)

- [ ] **1000 unread notifications**: index page loads in <1s; badge shows
      `[ 1000 ]`.
- [ ] **Notification with very long title** (255 chars): renders without
      overflow (CSS truncation acceptable; the spec asserts no JavaScript
      error).
- [ ] **Unicode title** (emoji + RTL): renders cleanly.
- [ ] **No URL on the notification**: the `[ open source ]` link is absent on
      the detail page.
- [ ] **Webhook URL not configured** (delivered_at NULL forever): the detail
      page shows `discord: pending` + `last_error`; the in-app row still
      appears.
- [ ] **AppSetting `discord_enabled = false`**: detail page shows
      `discord: disabled` (or `discord: pending` — implementation agent picks;
      recommendation: `disabled` is more accurate).
- [ ] **Notification with `event_payload` carrying `<script>`**: detail HTML
      body strips the script (per §2's sanitize).

#### Flaw tests

- [ ] **Smuggle a different user's notification id**: there is no "different
      user" — every row is install-wide. Request returns the row.
- [ ] **Smuggle a tenant_id param**: ignored.
- [ ] **Smuggle a `read_at` value via params on the read endpoint**: ignored;
      the controller stamps `Time.current` itself.
- [ ] **Attempt to bypass read-state by direct SQL on `in_app_read_at`**: out of
      scope (DB-level write protection is not a v1 concern).
- [ ] **Attempt to inject untrusted HTML in the URL via `event_payload`**: §2's
      sanitize strips; in-app render is HTML-safe.
- [ ] **Replay a `mark_read` against a deleted row**: graceful `marked_read: 0`.

## Manual playbook (post-implementation)

1. **Migrate** (from §1) and confirm `notifications` table exists.
2. **Configure webhooks** (from §1's manual playbook step 1).
3. **Toggle AppSetting flags** (from §1's manual playbook step 3).
4. **Trigger a notification.** With Phase 12 + Phase 15 already shipped,
   schedule a video publish OR create a manual milestone calendar entry; wait up
   to 1 minute for the scheduler.
5. **Visit `/notifications`.** Confirm the row appears.
6. **Confirm Discord webhook fired.** Open Discord; the embed appears.
7. **Confirm Slack webhook fired.** Open Slack; the block appears.
8. **Confirm unread badge.** Reload any page; the nav header shows `[ 1 ]` next
   to `notifications`.
9. **Mark notification as read.** Click `[ mark read ]` on the index row.
   Confirm the badge decrements live (no full-page reload).
10. **Mark all read.** Insert a few more rows; click `[ mark all read ]`.
    Confirm the badge disappears.
11. **Click a source link.** On the detail page click `[ open source ]`. Confirm
    the row flips to read AND the browser navigates.
12. **Trigger a milestone (game release T-30).** Insert a manual
    `milestone_rule` (per Phase 15 §1) with a low threshold; trigger the
    evaluator
    (`bin/rails runner "Calendar::MilestoneEvaluator.new.evaluate_all!"`).
    Confirm a `milestone_reached` notification lands.
13. **Trigger a sync error.** Run
    `bin/rails runner "NotificationSource::SyncError.report!(job: ChannelSync, error: StandardError.new('boom'), dedup_key: 'manual-test')"`.
    Confirm the urgent row appears with severity badge.
14. **Webhook failure.** Misconfigure the Discord URL in credentials. Trigger a
    notification. Confirm the in-app row lands; the detail page shows
    `discord: pending` + `last_error`.
15. **MCP smoke (Claude Mobile).** Call `notifications_list` from Claude Mobile;
    confirm the rows appear. Call `notifications_unread_count`; confirm the
    count matches the badge. Call
    `notifications_mark_read({ids: [...], confirm: "yes"})`; confirm the rows
    flip read in the web UI live.
16. **MCP scope check.** Issue a `notifications_list` call with a `dev`-only
    token; confirm it's rejected.
17. **Run the full RSpec suite.**
    ```bash
    bundle exec rspec
    ```
    Confirm green.
18. **Run rubocop.** Confirm clean.

## Cross-stack scope

| Surface           | Status                                 |
| ----------------- | -------------------------------------- |
| Rails web app     | **In scope.** Primary lane.            |
| MCP rack app      | **In scope.** Sub-lane. Four tools.    |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10. |
| Astro / website   | **Skipped.** N/A.                      |

## Copy questions to escalate (master agent asks user before dispatch)

1. **Index page heading.** Suggested: `notifications` (lowercase, h1 per
   `docs/design.md`). User confirms.
2. **Empty state.** Suggested: `no notifications yet.` (period per
   `docs/design.md` punctuation rule). User confirms or picks alternative.
3. **Mark-read button label.** Suggested: `[ mark read ]`. User confirms.
4. **Mark-unread button label.** Suggested: `[ mark unread ]`. User confirms.
5. **Mark-all-read button label.** Suggested: `[ mark all read ]`. User
   confirms.
6. **Open-source link label** on the detail page. Suggested: `[ open source ]`.
   User confirms or picks `[ open ]` or `[ visit ]`.
7. **Back link label.** Suggested: `[ back ]`. User confirms.
8. **Filter labels.** Suggested: `[ all ]` / `[ unread ]`. User confirms.
9. **Unread badge format.** Suggested: `[ N ]` (matching the bracketed- link
   convention). User confirms.
10. **Severity badge text.** Suggested: lowercase severity name (`info` /
    `success` / `warn` / `urgent`). User confirms.
11. **Per-channel delivery state copy on the detail page.** Suggested:
    `discord: pending` / `discord: 2026-05-10T12:00:00Z` / `discord: disabled`.
    User confirms.
12. **Webhook misconfigured warning copy** (banner at the top of the index when
    any unread row carries `last_error`). Suggested:
    `webhook delivery failing — see notification detail.`. User confirms.
13. **MCP tool descriptions** (the `description` field in each tool's JSON-RPC
    schema). Suggested per tool:
    - `notifications_list`:
      `"list pito notifications, optionally filtered by unread/kind/severity. paginated."`
    - `notifications_unread_count`:
      `"return the install-wide count of unread notifications."`
    - `notifications_mark_read`:
      `"mark one or more notifications as read. requires confirm=yes on the second call."`
    - `notifications_mark_all_read`:
      `"mark all unread notifications   as read. requires confirm=yes on the second call."`
      User confirms.
14. **Nav link label.** Suggested: `notifications`. User confirms.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Auto-mark-on-click default.** Q2 ships auto-mark on source-link click. Some
   users prefer explicit-only (the badge is the audit trail of "what's new").
   Architect's lean: auto-mark stays.
2. **Bulk URL pattern shape.** Q1 ships `/notifications/mark_read?ids=A,B,C`.
   The CLAUDE.md bulk-as-foundation pattern is `/<action>s/:type/:ids` — for
   destructive actions. Mark-read is not destructive; the architect uses a
   collection POST/PATCH with a `?ids=` param. User confirms or pushes for the
   `/<action>s/:type/:ids` shape with a fake "type" segment (e.g.,
   `notifications`).
3. **`confirm: yes/no` requirement on mark-read MCP tools.** CLAUDE.md requires
   the two-step pattern for destructive / significant MCP actions. Mark-read is
   non-destructive; architect ships `confirm: yes/no` anyway for symmetry with
   the rest of the bulk MCP surface. User confirms or removes the requirement.
4. **Sound / browser notification.** Out of scope for v1. Open question only as
   a "noted, deferred."
5. **Per-channel delivery state granularity.** Q8 shows three states (`yes` /
   iso / pending / disabled). User confirms or wants finer (e.g.,
   `retrying (3/5)`).
6. **Unread row visual treatment.** Architect ships: bold title for unread;
   muted (per `--color-muted`) title for read. Per `docs/design.md` (no
   decorative red, no animation). User confirms or picks alternative (e.g., a
   `[ • ]` glyph prefix).
7. **MCP `notifications_unread_count` cache.** A 1-second cache is defensible;
   Architect's lean: NO cache for v1; the count query over a partial index is
   fast.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. **Index page heading** → `notifications` (lowercase, h1).
2. **Empty state** → `no notifications yet.`
3. **Mark-read button label** → `[ mark read ]`.
4. **Mark-unread button label** → `[ mark unread ]`.
5. **Mark-all-read button label** → `[ mark all read ]`.
6. **Open-source link label** → `[ open ]`. Override architect's
   `[ open source ]` (ambiguous; reads like "open-source software").
7. **Back link label** → `[ back ]`.
8. **Filter labels** → `[ all ]` / `[ unread ]`.
9. **Unread badge format** → `[ N ]`.
10. **Severity badge text** → Lowercase severity name: `info` / `success` /
    `warn` / `urgent`.
11. **Per-channel delivery state copy** → Architect's drafts: `discord: pending`
    / `discord: 2026-05-10T12:00:00Z` / `discord: disabled`.
12. **Webhook misconfigured warning banner** →
    `webhook delivery failing — see notification detail.`
13. **MCP tool descriptions** → Architect's drafts verbatim:
    - `notifications_list`:
      `list pito notifications, optionally filtered by unread/kind/severity. paginated.`
    - `notifications_unread_count`:
      `return the install-wide count of unread notifications.`
    - `notifications_mark_read`: Override below — use
      `mark one or more notifications as read.` (drop the `requires confirm=yes`
      clause; see open-question decision #3).
    - `notifications_mark_all_read`: Override below — use
      `mark all unread notifications as read.` (drop the `requires confirm=yes`
      clause).
14. **Nav link label** → `notifications`.

### Open-question decisions

1. **Auto-mark-on-click default** → Keep auto-mark. Explicit-only is a follow-up
   if needed.
2. **Bulk URL pattern** → Collection POST/PATCH with `?ids=` param
   (`/notifications/mark_read?ids=A,B,C`). Mark-read is non-destructive; the
   `/<action>s/:type/:ids` pattern (CLAUDE.md hard rule) is for destructive
   actions only.
3. **`confirm: yes/no` requirement on mark-read MCP tools** → REMOVE. Mark-read
   is non-destructive. The two-step pattern in CLAUDE.md is for destructive /
   significant actions. Override architect's symmetry argument. Update the tool
   descriptions accordingly (per Copy #13 above).
4. **Sound / browser notification** → Out of scope.
5. **Per-channel delivery state granularity** → 3 states sufficient (`pending` /
   iso-timestamp / `disabled`). Finer grain is a follow-up.
6. **Unread row visual treatment** → Bold title for unread; muted
   (`--color-muted`) title for read. No glyph prefix.
7. **MCP `notifications_unread_count` cache** → No cache for v1. Partial-index
   query is fast.

## Non-goals (explicit)

- Per-user notification preferences.
- Email / push notifications.
- Sound / browser-native notifications.
- CLI parity (work unit 10).
- Settings UI for `discord_enabled` / `slack_enabled`.
- Notification grouping / coalescing.
- Notification archival / pruning.
- Notification search / full-text.

## Implementation lane assignment

Two lanes:

- **rails-impl** (primary):
  - `config/routes.rb`
  - `app/controllers/notifications_controller.rb`
  - `app/views/notifications/**`
  - `app/views/layouts/_nav.html.erb`
  - `app/javascript/controllers/notification_link_controller.js`
  - `app/javascript/controllers/index.js`
  - `app/models/notification.rb` (callbacks added)
  - `spec/requests/notifications_spec.rb`
  - `spec/system/**`
  - `spec/views/**`

- **mcp-impl** (sub-lane, dispatched in parallel after rails-impl green):
  - `app/mcp/tools/notifications_list.rb`
  - `app/mcp/tools/notifications_unread_count.rb`
  - `app/mcp/tools/notifications_mark_read.rb`
  - `app/mcp/tools/notifications_mark_all_read.rb`
  - `app/mcp/tool_registry.rb` (or equivalent)
  - `spec/mcp/tools/**`

No `extras/cli/`, no `extras/website/`, no `db/`, no `docs/`.
