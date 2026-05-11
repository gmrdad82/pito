# Phase 21 — JSON Endpoints for CLI / MCP Parity · Session Log

## 2026-05-10 — Rails-impl: all three controller lanes in one sweep

**Spec:**
`docs/plans/beta/21-json-endpoints-cli-mcp-parity/specs/01-rails-json-endpoints.md`
(all 8 locked decisions honored).

**Goal of the session.** Land the JSON contract on `GamesController`,
`Calendar::*Controller`, `NotificationsController`, and the
`DeletionsController#cancel_calendar_entry` action so the upcoming `pito` CLI
extensions and the `yt:*` MCP tool surface have a stable wire shape to consume.
Three new decorators (`GameDecorator`, `CalendarEntryDecorator`,
`NotificationDecorator`) keep summary + detail shapes in one place; jbuilder
partials reuse them via `as_summary_json` / `as_detail_json`.

### What landed (file-level)

**Decorators (new):**

- `app/decorators/game_decorator.rb` — `as_summary_json` + `as_detail_json`.
  Boolean fields serialized as `"yes"` / `"no"` strings. Genres / platforms
  rendered as `[{id:, name:}]`.
- `app/decorators/calendar_entry_decorator.rb` — summary + detail.
  `dispatch_declarations_json` accessor renders the
  `Calendar::NotificationDispatchDeclaration.declarations_for(entry)` array with
  ISO-8601 `fires_at`.
- `app/decorators/notification_decorator.rb` — summary + detail. Detail wraps
  `NotificationFormatter::InApp.payload_for` under `:payload`.

**Controllers (modified — `format.json` branches added):**

- `app/controllers/games_controller.rb` — `index`, `show`, `resync`, `search`
  JSON branches. `show` preserves request format on the canonical-slug 301 (so
  `GET /games/42.json` → 301 to `/games/<slug>.json`, then 200). `resync`
  returns 202 + jid on enqueue, 409 with `{ error: "already_resyncing" }` on the
  in-flight mutex hit. `search` catches `Igdb::Client::Error` → 200 with
  `search_error: { kind, message }` and an empty results array (locked decision
  #8).
- `app/controllers/calendar/schedule_controller.rb` — JSON branch on `show`.
  Echoes pagination + filter + selected_kinds.
- `app/controllers/calendar/month_controller.rb` — JSON branch on `show`.
  Date-keyed `buckets` hash (empty days omitted). Empty-bucket case explicitly
  emits `{}` rather than jbuilder's default `null`.
- `app/controllers/calendar/entries_controller.rb` — JSON branches on `show`,
  `create`, `update`, `note`. Read-only entry update rejects with 403 +
  `{ error: "read_only_entry" }`. Non-manual entry_type on create rejects with
  422 + `{ error: "entry_type_not_user_creatable" }`. Malformed yes/no rejects
  with 422 + `{ error: "invalid_yes_no", field:, value: }`. `parent_entry_id`
  permitted (locked decision #3).
- `app/controllers/notifications_controller.rb` — JSON branches on `index`,
  `show`, `mark_read`, `mark_all_read`. New `badge` collection action returning
  `{ unread_count, has_failures }` (locked decision #6).
  `respond_with_state_change` JSON branch upgraded from `head :no_content` to
  200 + `{ id, read, in_app_read_at, unread_count }` (locked decision #2).
- `app/controllers/deletions_controller.rb` — JSON branch on
  `cancel_calendar_entry`. Returns the minimal
  `{ cancelled: [{ id, state }], skipped: [{ id, reason }] }` (locked decision
  #4). Skipped reasons cover both `"already_cancelled"` and
  `"not_user_cancellable"` (the latter for derived/auto entries filtered out by
  `scope_for`).
- `app/controllers/concerns/confirmable.rb` — split the empty-ids and
  empty-scope error envelopes; the JSON branch now returns
  `{ error: "no_ids_supplied" }` when `ids` is empty (CLI / MCP callers parse
  this; the free-form HTML alert text wasn't normative).

**Routes:**

- `config/routes.rb` — added `get :badge` as a collection action on
  `resources :notifications`.

**Jbuilder views (new):**

- `app/views/games/{index,show,resync,search}.json.jbuilder`
- `app/views/games/_game.json.jbuilder`
- `app/views/calendar/schedule/show.json.jbuilder`
- `app/views/calendar/month/show.json.jbuilder`
- `app/views/calendar/entries/{show,_entry}.json.jbuilder` (`create.json` /
  `update.json` / `note.json` reuse `show.json` via `render :show`; no dedicated
  files needed)
- `app/views/deletions/cancel_calendar_entry.json.jbuilder`
- `app/views/notifications/{index,show,badge,state_change,read,unread,mark_read,mark_all_read}.json.jbuilder`
- `app/views/notifications/{_notification,_state_change,_bulk_response}.json.jbuilder`

**Spec files (new):**

- `spec/decorators/{game,calendar_entry,notification}_decorator_spec.rb`
- `spec/views/games/{index,show,resync,search}.json.jbuilder_spec.rb`
- `spec/views/calendar/schedule/show.json.jbuilder_spec.rb`
- `spec/views/calendar/month/show.json.jbuilder_spec.rb`
- `spec/views/calendar/entries/show.json.jbuilder_spec.rb`
- `spec/views/notifications/{index,show,badge}.json.jbuilder_spec.rb`
- `spec/requests/games_json_spec.rb`
- `spec/requests/calendar/{schedule,month,entries}_json_spec.rb`
- `spec/requests/deletions/calendar_entry_json_spec.rb`
- `spec/requests/notifications_json_spec.rb`

**Spec count delta.** +163 new examples across decorator, view, and request
specs. All green.

### Gates

- `bundle exec rspec spec/decorators spec/views spec/requests` — 1607 examples,
  0 failures (the 1284 request specs include all pre-existing surfaces + the new
  JSON request specs).
- `bundle exec rubocop` on every touched file (38 files) — no offenses detected.
- `bundle exec brakeman -q -w2` — 0 warnings, 0 errors, no new ignore entries.

### Notable decisions during the session

- The `show.json` canonical-slug redirect needed `request.format.json?`
  branching so `game_path(g, format: :json)` is only passed on JSON requests;
  passing `format: :html` to a route helper drops the extension. Mirrors what
  other framework code does at the redirect boundary.
- The `mark_read` / `mark_all_read` JSON branches share their body via
  `app/views/notifications/_bulk_response.json.jbuilder`. Similarly `read.json`
  / `unread.json` / the inline `respond_with_state_change` branch share via
  `_state_change.json.jbuilder`. Avoids three-way duplication of the same key
  set.
- `selected_kinds` in calendar list/grid responses serializes as `nil` (no
  filter applied), `[]` (filter present but explicit empty), or an
  `Array<String>` of valid kind labels. The CLI / MCP caller can distinguish
  "default = show everything" from "explicit empty" by checking `is_array?` vs
  `is_null?`. Same pattern is in the HTML controller code (`:empty` sentinel
  internally).
- The empty-`buckets` case needed an explicit `json.merge!({})` so jbuilder
  emits `"buckets": {}` instead of `"buckets": null` (a default `do/end` block
  with no `set!` calls collapses to null).
- The soft-cancel response carries `skipped` rows with two distinct reasons:
  `"already_cancelled"` (entry exists, state already cancelled) and
  `"not_user_cancellable"` (entry doesn't exist OR was filtered out by
  `Confirmable#scope_for("calendar_entry", …)` for being a derived/auto entry).
  The empty-ids case is handled before `cancel_calendar_entry` by the
  `Confirmable#load_items` before_action (now returning
  `{ error: "no_ids_supplied" }` for JSON).
- IGDB search took_ms is measured via
  `Process.clock_gettime (Process::CLOCK_MONOTONIC)` (not `Time.current`
  arithmetic) so wall clock changes during a long request can't go negative.

### Open / follow-up

- `[ ]` Reviewer pass — every endpoint covered by request + view spec.
- `[ ]` Manual test recipe (curl) walked end-to-end (cookie via DevTools → all
  curls in spec §"Manual test recipe").
- `[ ]` User validates. Master commits + pushes after.

### Inputs / cross-stack references

- Phase 14 §1 — Game model + IGDB sync flow.
- Phase 15 §1 — `Calendar::NotificationDispatchDeclaration.declarations_for`.
- Phase 16 §3 — `NotificationFormatter::InApp.payload_for` + the
  `enforce_mark_read_rate_limit` before_action.
- Phase 20 — friendly URLs (`Game.friendly.find` + `FriendlyRedirect` concern
  stripping the format extension before comparing).
- CLAUDE.md hard rules — yes/no boundary, bulk-as-foundation, destructive
  actions go through action-confirmation page (n/a for these JSON wire
  endpoints; the CLI / MCP confirmation pattern is its own surface).
