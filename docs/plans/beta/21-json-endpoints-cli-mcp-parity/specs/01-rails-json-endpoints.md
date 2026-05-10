# Rails JSON Endpoints for CLI / MCP Parity

## Goal

Add a stable JSON contract to three controllers — `GamesController`,
`Calendar::*Controller`, and `NotificationsController` — so the
upcoming `pito` CLI extensions and the `yt:*` MCP tool surface can
read, write, and mutate the corresponding domain objects without
re-implementing per-feature shape logic. Every JSON shape mirrors a
domain object the web UI already exposes; this phase does not add
business logic, it adds a typed wire surface.

The audience is two non-human clients:

1. The `pito` CLI (Rust, hits Rails over HTTP, parses JSON).
2. MCP tool implementations under `app/mcp/tools/` (Ruby, mostly
   call the same Rails controller code from inside the same
   process; the JSON-renderable shape doubles as the MCP tool
   payload via `as_*_json` decorators).

Both consumers share the same wire shape. CLI subcommand and MCP
tool additions are non-scope here — they land in follow-ups under
`extras/cli/` and `app/mcp/tools/` once these endpoints exist.

## Files touched

### Controllers (request layer)

- `app/controllers/games_controller.rb` — add `format.json` branches
  to `index`, `show`, `resync`; add a JSON branch to the existing
  `search` action (currently HTML-partial only).
- `app/controllers/calendar/schedule_controller.rb` — add
  `format.json` to `show`.
- `app/controllers/calendar/month_controller.rb` — add `format.json`
  to `show`.
- `app/controllers/calendar/entries_controller.rb` — add
  `format.json` branches to `show`, `create`, `update`, `note`. The
  existing `new` / `edit` HTML-form actions stay HTML-only (forms
  are a UI concern).
- `app/controllers/deletions_controller.rb` — add a `format.json`
  branch to `cancel_calendar_entry` (the action that handles
  `DELETE /deletions/calendar_entry/:ids` per existing
  `routes.rb`). Returns the soft-cancelled entry list as JSON.
- `app/controllers/notifications_controller.rb` — add `format.json`
  branches to `index`, `show`. Replace the existing
  `format.json { head :no_content }` in `respond_with_state_change`
  with a JSON body. Add a new `badge` action (or extend an existing
  one) that returns `{ unread_count, has_failures }`.

### Routes

- `config/routes.rb` — add a `get :badge` member-or-collection
  route on the `notifications` resource to expose the badge JSON
  (collection action: `GET /notifications/badge.json`). All other
  endpoints use existing routes plus `.json` suffix.

### Jbuilder views (shape layer)

- `app/views/games/index.json.jbuilder`
- `app/views/games/show.json.jbuilder`
- `app/views/games/resync.json.jbuilder`
- `app/views/games/search.json.jbuilder`
- `app/views/games/_game.json.jbuilder` — partial reused by index +
  search (summary shape)
- `app/views/calendar/schedule/show.json.jbuilder`
- `app/views/calendar/month/show.json.jbuilder`
- `app/views/calendar/entries/show.json.jbuilder`
- `app/views/calendar/entries/create.json.jbuilder`
- `app/views/calendar/entries/update.json.jbuilder`
- `app/views/calendar/entries/note.json.jbuilder`
- `app/views/calendar/entries/_entry.json.jbuilder` — partial reused
  by schedule + month + show (summary shape)
- `app/views/deletions/cancel_calendar_entry.json.jbuilder`
- `app/views/notifications/index.json.jbuilder`
- `app/views/notifications/show.json.jbuilder`
- `app/views/notifications/badge.json.jbuilder`
- `app/views/notifications/_notification.json.jbuilder` — partial
  reused by index + read/unread state-change responses
- `app/views/notifications/read.json.jbuilder`
- `app/views/notifications/unread.json.jbuilder`
- `app/views/notifications/mark_read.json.jbuilder`
- `app/views/notifications/mark_all_read.json.jbuilder`

### Decorators (optional — only if the shape grows beyond a thin jbuilder)

- `app/decorators/game_decorator.rb` — new file. `as_summary_json`
  + `as_detail_json` mirroring `VideoDecorator`. Drives the search
  partial too (so search hits and index rows share one shape
  definition).
- `app/decorators/calendar_entry_decorator.rb` — new file.
  `as_summary_json` + `as_detail_json`. Detail variant includes
  `parent_entry_id`, `child_entry_ids[]`, and the
  `Calendar::NotificationDispatchDeclaration.declarations_for(entry)`
  array (already loaded into `@declarations` on `show`).
- `app/decorators/notification_decorator.rb` — new file.
  `as_summary_json` + `as_detail_json`. Detail variant wraps the
  existing `NotificationFormatter::InApp.payload_for` payload.

Decorator usage is a soft preference — if a shape stays trivial
(under ~10 fields, no derived values), inline it in the jbuilder
template. The rule: no shape duplication between two jbuilder
files. If two views render the same record, factor through a
partial OR a decorator method.

### Spec files (test layer — every endpoint, every shape)

Request specs:

- `spec/requests/games_json_spec.rb`
- `spec/requests/calendar/schedule_json_spec.rb`
- `spec/requests/calendar/month_json_spec.rb`
- `spec/requests/calendar/entries_json_spec.rb`
- `spec/requests/deletions/calendar_entry_json_spec.rb`
- `spec/requests/notifications_json_spec.rb`

View specs (jbuilder shape only — no controller reachability):

- `spec/views/games/index.json.jbuilder_spec.rb`
- `spec/views/games/show.json.jbuilder_spec.rb`
- `spec/views/games/resync.json.jbuilder_spec.rb`
- `spec/views/games/search.json.jbuilder_spec.rb`
- `spec/views/calendar/schedule/show.json.jbuilder_spec.rb`
- `spec/views/calendar/month/show.json.jbuilder_spec.rb`
- `spec/views/calendar/entries/show.json.jbuilder_spec.rb`
- `spec/views/notifications/index.json.jbuilder_spec.rb`
- `spec/views/notifications/show.json.jbuilder_spec.rb`
- `spec/views/notifications/badge.json.jbuilder_spec.rb`

Decorator specs (only for new decorators):

- `spec/decorators/game_decorator_spec.rb`
- `spec/decorators/calendar_entry_decorator_spec.rb`
- `spec/decorators/notification_decorator_spec.rb`

## Wire-shape contracts

> Illustrative payload shapes. The implementing agent renders these
> in jbuilder; the shape is normative, the implementation is not.

### Games

`GET /games.json?sort=&dir=&page=&genre=&platform_owned=`

```json
{
  "games": [
    {
      "id": 42,
      "slug": "the-witness",
      "title": "The Witness",
      "release_year": 2016,
      "igdb_rating": 87.4,
      "platform_owned_id": 3,
      "played_at": "2024-01-12T00:00:00Z",
      "cover_image_id": "co1abc",
      "resyncing": "no",
      "igdb_synced_at": "2026-05-01T18:21:00Z",
      "created_at": "2025-12-10T09:14:00Z"
    }
  ],
  "filter": { "genre_id": null, "platform_owned_id": 3 },
  "sort": { "key": "release_year", "dir": "desc" }
}
```

`GET /games/:id.json` — accepts slug **or** integer id (per
Phase 20 `friendly_id :igdb_slug, use: :finders`). Canonical slug
redirect (HTTP 301 from `redirect_to_canonical_slug!`) applies to
`.json` requests too — the existing `FriendlyRedirect` concern
already strips the format extension before comparing, so no special
handling is needed.

```json
{
  "game": {
    "id": 42,
    "slug": "the-witness",
    "igdb_id": 18811,
    "title": "The Witness",
    "summary": "...",
    "release_date": "2016-01-26",
    "release_year": 2016,
    "igdb_rating": 87.4,
    "igdb_rating_count": 421,
    "aggregated_rating": 91.0,
    "total_rating": 89.2,
    "total_rating_count": 510,
    "ttb_main_seconds": 36000,
    "ttb_extras_seconds": 72000,
    "ttb_completionist_seconds": 360000,
    "external_steam_app_id": "210970",
    "external_gog_id": null,
    "external_epic_id": null,
    "cover_image_id": "co1abc",
    "platform_owned_id": 3,
    "played_at": "2024-01-12T00:00:00Z",
    "notes": "local note text",
    "hours_of_footage_manual": 12.5,
    "hours_of_footage_cached": 8.2,
    "manual_date_override": "no",
    "resyncing": "no",
    "igdb_synced_at": "2026-05-01T18:21:00Z",
    "last_sync_error": null,
    "genres": [{ "id": 1, "name": "Puzzle" }],
    "platforms_owning": [{ "id": 3, "name": "Steam" }],
    "created_at": "2025-12-10T09:14:00Z",
    "updated_at": "2026-05-01T18:21:00Z"
  }
}
```

`POST /games/:id/resync.json` — enqueue acknowledgment.

Response (HTTP 202 Accepted on enqueue, 409 Conflict when
`resyncing?` is already true):

```json
{
  "game_id": 42,
  "resyncing": "yes",
  "enqueued_jid": "abc123def456",
  "message": "refreshing from igdb…"
}
```

`409` body when already resyncing:

```json
{ "game_id": 42, "resyncing": "yes", "error": "already_resyncing" }
```

The `enqueued_jid` field surfaces the Sidekiq job id returned by
`GameIgdbSync.perform_async(game.id)` so the CLI / MCP caller can
poll an audit row keyed by jid in a future phase. The current
HTML flow throws the jid away; this spec keeps it.

`GET /games/search.json?q=witness`:

```json
{
  "query": "witness",
  "results": [
    {
      "igdb_id": 18811,
      "title": "The Witness",
      "release_year": 2016,
      "cover_image_id": "co1abc",
      "summary": "..."
    }
  ],
  "took_ms": 142.0,
  "search_error": null
}
```

When IGDB returns an error, `results` is `[]` and `search_error`
carries the message. The HTTP status is still 200 — the request
itself succeeded; the upstream IGDB call was the failure.

The query is trimmed and capped at `MAX_QUERY_LENGTH` (100 chars,
mirrors the existing controller constant). Empty `q` returns
`results: []` with `took_ms: 0` and HTTP 200 — not 422; an empty
search box is a valid (no-op) query.

### Calendar

`GET /calendar/schedule.json?types=&source=&state=&page=`:

```json
{
  "page": 1,
  "total_pages": 4,
  "total": 187,
  "per_page": 50,
  "selected_kinds": ["video", "game"],
  "selected_source": null,
  "show_cancelled": "no",
  "install_tz": "Europe/Bucharest",
  "today": "2026-05-10T18:42:00Z",
  "entries": [
    {
      "id": 12,
      "entry_type": "game_release",
      "title": "Hades 2 launch",
      "starts_at": "2026-05-13T17:00:00Z",
      "ends_at": null,
      "all_day": "no",
      "timezone": "Europe/Bucharest",
      "state": "scheduled",
      "source": "derived",
      "read_only": "yes",
      "game_id": 42,
      "video_id": null,
      "channel_id": null,
      "project_id": null,
      "milestone_rule_id": null
    }
  ]
}
```

`GET /calendar/month/:year/:month.json?types=&state=`:

```json
{
  "year": 2026,
  "month": 5,
  "install_tz": "Europe/Bucharest",
  "first_day": "2026-04-27",
  "last_day": "2026-06-01",
  "today": "2026-05-10",
  "on_current_month": "yes",
  "selected_kinds": ["video", "game"],
  "show_cancelled": "no",
  "buckets": {
    "2026-05-13": [
      { "id": 12, "entry_type": "game_release", "title": "Hades 2 launch", "..." }
    ]
  },
  "nav": {
    "prev": { "year": 2026, "month": 4 },
    "next": { "year": 2026, "month": 6 }
  }
}
```

The `buckets` keys are ISO-8601 dates in `install_tz`. Empty days
are omitted (the CLI/MCP caller fills them with empty arrays
locally — no need to ship 30+ empty arrays).

`GET /calendar/entries/:id.json`:

```json
{
  "entry": {
    "id": 12,
    "entry_type": "game_release",
    "title": "Hades 2 launch",
    "description": "...",
    "starts_at": "2026-05-13T17:00:00Z",
    "ends_at": null,
    "all_day": "no",
    "timezone": "Europe/Bucharest",
    "state": "scheduled",
    "source": "derived",
    "read_only": "yes",
    "manual_date_override": "no",
    "release_precision": "exact",
    "tba_remind_monthly": "no",
    "notify_anyway": "no",
    "metadata": { "user_overrides": { "note": "..." } },
    "parent_entry_id": null,
    "child_entry_ids": [55, 56],
    "game_id": 42,
    "video_id": null,
    "channel_id": null,
    "project_id": null,
    "milestone_rule_id": null,
    "created_by_user_id": 1,
    "created_at": "...",
    "updated_at": "..."
  },
  "dispatch_declarations": [
    {
      "channel": "in_app",
      "fires_at": "2026-05-13T17:00:00Z",
      "kind": "game_release_today",
      "severity": "info",
      "...": "shape mirrors NotificationDispatchDeclaration#as_json"
    }
  ]
}
```

The `dispatch_declarations` array maps from the existing
`Calendar::NotificationDispatchDeclaration.declarations_for(entry)`
return value. The decorator (or jbuilder) calls `as_json` on each;
the spec freezes the keys actually emitted.

`POST /calendar/entries.json` — JSON body. Same params shape as the
HTML form (`{ calendar_entry: { ... } }`). yes/no fields
(`all_day`, `manual_date_override`, `tba_remind_monthly`,
`notify_anyway`) MUST be the strings `"yes"` / `"no"`; any other
value rejects with HTTP 422 (existing `coerce_yes_no!` already
enforces this for HTML, the JSON branch reuses it).

Success → HTTP 201 Created, body = the same shape as `show.json`.
Validation failure → HTTP 422 Unprocessable Content with:

```json
{ "errors": { "starts_at": ["can't be blank"], "title": ["..."] } }
```

Read-only-entry-type rejection (an `entry_type` outside
`MANUAL_ENTRY_TYPES`) → HTTP 422 with
`{ "error": "entry_type_not_user_creatable" }`.

`PATCH /calendar/entries/:id.json` — same shape as create. Read-only
entry attempt → HTTP 403 Forbidden (the HTML branch redirects with a
flash; the JSON branch returns a structured error):

```json
{ "error": "read_only_entry" }
```

`PATCH /calendar/entries/:id/note.json` — body
`{ "calendar_entry": { "note": "..." } }`. Returns the updated
entry. Auto / derived entries can hit this even when `read_only?`
is true (the existing controller already bypasses readonly for the
`metadata` column on this action).

`DELETE /deletions/calendar_entry/:ids.json` — soft-cancel. `:ids`
is one or N comma-separated ids. Returns:

```json
{
  "cancelled": [{ "id": 12, "state": "cancelled" }],
  "skipped": [{ "id": 55, "reason": "already_cancelled" }]
}
```

Empty ids list → HTTP 422 `{ "error": "no_ids_supplied" }`.

### Notifications

`GET /notifications.json?filter=&kind=&severity=&page=`:

```json
{
  "page": 1,
  "total_pages": 3,
  "total": 124,
  "per_page": 50,
  "filter": "unread",
  "kind": null,
  "severity": null,
  "unread_count": 17,
  "has_failures": "yes",
  "notifications": [
    {
      "id": 91,
      "kind": "video_published",
      "severity": "success",
      "event_type": "video.published",
      "title": "video published",
      "body": "...",
      "url": "/videos/abc123",
      "fires_at": "2026-05-10T17:00:00Z",
      "in_app_read_at": null,
      "read": "no",
      "discord_delivered_at": "2026-05-10T17:00:01Z",
      "slack_delivered_at": null,
      "retry_count": 0,
      "last_error": null,
      "created_at": "2026-05-10T17:00:00Z"
    }
  ]
}
```

`GET /notifications/:id.json`:

```json
{
  "notification": {
    "id": 91,
    "...": "all summary fields"
  },
  "payload": {
    "...": "NotificationFormatter::InApp.payload_for(@notification)"
  }
}
```

`GET /notifications/badge.json`:

```json
{ "unread_count": 17, "has_failures": "yes" }
```

`PATCH /notifications/:id/read.json`,
`PATCH /notifications/:id/unread.json`:

```json
{
  "id": 91,
  "read": "yes",
  "in_app_read_at": "2026-05-10T18:42:00Z",
  "unread_count": 16
}
```

The current code returns `head :no_content`. This spec changes that
JSON branch to return a body (callers told us they need the new
unread_count without a follow-up call). The 204 → 200 + body
transition is a wire-contract change; the HTML / Turbo Stream
branches stay untouched.

`PATCH /notifications/mark_read.json?ids=`,
`PATCH /notifications/mark_all_read.json`:

```json
{ "marked": 17, "unread_count": 0, "has_failures": "no" }
```

## Cross-cutting rules (every endpoint must honor)

### Auth gate

Every endpoint inherits `Sessions::AuthConcern` via
`ApplicationController`. Unauthenticated JSON requests redirect to
`/login` (302) — same as HTML. The CLI / MCP follow-up phases will
swap this for bearer-token auth via `Api::AuthConcern`; in this
phase, cookie-session is the only auth surface (matches Phase
12+ behavior). Specs MUST cover the unauthenticated case for at
least one endpoint per controller (a 302 redirect to login is
acceptable, the JSON envelope expectation is not enforced for the
unauth path because the response is HTML-shaped).

### `yes` / `no` boundary

Every boolean field at the JSON boundary serializes as the string
`"yes"` or `"no"` — never `true`/`false`/`0`/`1`. The decorators
and jbuilder templates MUST call `YesNo.to_yes_no(value)` on every
boolean. Inbound boolean params (only `Calendar::EntriesController`
accepts writes here) reuse the existing `coerce_yes_no!` helper —
on a malformed value the JSON branch returns HTTP 422 with:

```json
{ "error": "invalid_yes_no", "field": "all_day", "value": "true" }
```

(The existing helper currently renders HTML; the JSON branch
re-paths to a JSON 422 instead of the HTML re-render.)

### Friendly-id slug resolution

`GET /games/:id.json` MUST accept slug or integer id. The existing
`Game.friendly.find(params[:id])` call already does this. Canonical
slug redirect (301 from `redirect_to_canonical_slug!`) applies to
`.json` requests too. Spec MUST cover all three paths:

1. Request with canonical slug → 200, no redirect.
2. Request with integer id → 301 to the canonical slug URL
   (preserving `.json`), then 200.
3. Request with stale / unknown slug → 404.

### 404 vs 422 distinction

- **404 Not Found** — the record does not exist
  (`ActiveRecord::RecordNotFound`). `ApplicationController` already
  rescues this and renders `{ "error": "Not found" }` for JSON.
- **422 Unprocessable Content** — the record exists but the request
  payload is invalid (validation errors, malformed yes/no, an
  empty `:ids` list, an `entry_type` outside `MANUAL_ENTRY_TYPES`).
- **403 Forbidden** — the request is structurally fine but the
  caller cannot perform it (read-only entry update).
- **409 Conflict** — concurrent-state rejection (resync already in
  flight).
- **202 Accepted** — async enqueue acknowledgment (resync).

Spec MUST exercise every status above with a matching example.

### Rate limit / lock awareness

`POST /games/:id/resync.json` reuses the existing `games.resyncing`
mutex flag (Phase 14 §1 polish). When the flag is true, the JSON
branch returns HTTP 409 (the HTML branch flashes "already
resyncing" and redirects). The SAME mutex protects against
spam-clicks from the CLI / MCP. No new rate-limit middleware is
introduced here. If the future Phase 13 F3-style per-resource lock
work expands to the calendar / notifications endpoints, that's a
follow-up — this spec only consumes the existing lock semantics
for `resync`.

### CSRF

`skip_before_action :verify_authenticity_token, if: -> { request.format.json? }`
is added per controller (mirrors `SavedViewsController`). HTML form
submissions still hit the regular CSRF check.

## Acceptance

### Routes

- [ ] `GET /games.json` returns the index shape.
- [ ] `GET /games/:id.json` accepts slug AND integer id.
- [ ] `POST /games/:id/resync.json` returns 202 + jid on success,
      409 on already-resyncing.
- [ ] `GET /games/search.json?q=` returns the IGDB type-ahead
      shape.
- [ ] `GET /calendar/schedule.json` honors `?types`, `?source`,
      `?state`, `?page` — same semantics as HTML.
- [ ] `GET /calendar/month/:year/:month.json` honors `?types`,
      `?state` — same semantics as HTML.
- [ ] `GET /calendar/entries/:id.json` returns detail + child
      entry ids + dispatch declarations.
- [ ] `POST /calendar/entries.json` creates manual entries; rejects
      non-manual `entry_type` with 422.
- [ ] `PATCH /calendar/entries/:id.json` updates manual entries;
      rejects read-only entries with 403.
- [ ] `PATCH /calendar/entries/:id/note.json` sets
      `metadata.user_overrides.note` even on read-only entries.
- [ ] `DELETE /deletions/calendar_entry/:ids.json` soft-cancels
      one or N entries; returns cancelled + skipped lists.
- [ ] `GET /notifications.json` returns paginated index +
      `unread_count` + `has_failures`.
- [ ] `GET /notifications/:id.json` returns detail + formatter
      payload.
- [ ] `GET /notifications/badge.json` returns
      `{ unread_count, has_failures }`.
- [ ] `PATCH /notifications/:id/read.json` returns
      `{ id, read, in_app_read_at, unread_count }` (replacing the
      current 204).
- [ ] `PATCH /notifications/:id/unread.json` returns the same
      shape with `read: "no"`.
- [ ] `PATCH /notifications/mark_read.json?ids=` returns
      `{ marked, unread_count, has_failures }`.
- [ ] `PATCH /notifications/mark_all_read.json` returns the same.

### Shape

- [ ] Every boolean field at the JSON boundary serializes as
      `"yes"` / `"no"`.
- [ ] Every timestamp serializes as ISO-8601 (`iso8601` on the
      Time/DateTime object).
- [ ] `null` is emitted for absent associations (no `0`, no
      `""`).
- [ ] Pagination fields (`page`, `total_pages`, `total`,
      `per_page`) appear on every paginated index.
- [ ] Filter / sort echo fields (`filter`, `sort`,
      `selected_kinds`, etc.) appear on every endpoint that
      accepts those params, so the CLI/MCP caller can verify
      what it asked for.

### Auth + boundary

- [ ] Unauthenticated JSON requests redirect to `/login` (covered
      by at least one spec per controller).
- [ ] Malformed yes/no on calendar create/update returns 422 with
      `{ "error": "invalid_yes_no", "field": "...", "value": "..." }`.
- [ ] `Game.friendly.find` rejection on unknown slug → 404 JSON.
- [ ] Integer id → canonical slug 301 (response includes
      `Location: /games/<slug>.json`).
- [ ] Slug + integer id both resolve the same record.

### Test coverage (mandatory sweep — `docs/agents/architect.md` §D)

- [ ] **Request specs** — every endpoint × happy / sad / edge /
      flaw:
  - happy: 200 / 201 / 202 + correct shape
  - sad: 4xx with the expected error body
  - edge: empty list / empty query / boundary page numbers /
    timezone DST flip / cross-month boundary / slug-vs-id /
    canonical-redirect
  - flaw: malformed yes/no, malformed JSON body, oversized query
    (`q` over `MAX_QUERY_LENGTH`), unknown filter values, ids
    list with 0 or `evil` strings, race-condition resync
    (mutex held)
- [ ] **View specs** (jbuilder-only) — every shape rendered with a
      stub `assign(:games, [game])` etc., asserting exact key set
      + value types.
- [ ] **Decorator specs** (only for new decorators) — full unit
      coverage of `as_summary_json` and `as_detail_json`.
- [ ] **Controller-internal helpers** — `coerce_yes_no!` JSON
      branch covered explicitly (not only as a side-effect of
      request specs).
- [ ] No system specs — out of scope for this phase.
- [ ] No new MCP tool specs — out of scope.
- [ ] No new CLI integration specs — out of scope (CLI lane is a
      follow-up phase).

### Wire-shape snapshots

- [ ] At least one request spec per endpoint asserts the exact
      JSON key set (`expect(json.keys).to match_array([...])`)
      so future shape drift fails loudly. The CLI / MCP follow-up
      phases will pin specific keys; this phase pins the contract
      for them.

## Manual test recipe

Prereqs: `bin/dev` running, a logged-in browser session for
cookie reuse, OR a test cookie copied via `curl --cookie`. The
session cookie is `pito_session` (signed). Easiest path: log in
via the browser, copy the cookie via DevTools, then:

```bash
COOKIE="pito_session=<value-from-devtools>"
HOST="http://localhost:3000"

# Games
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/games.json?sort=release_year&dir=desc" | jq

# Show via slug AND via id (the redirect is followed — note the 301)
curl -s -L -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/games/the-witness.json" | jq '.game.id'
curl -s -L -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/games/42.json" | jq '.game.slug'

# Resync (expect 202 first call, 409 second call within the same window)
curl -s -X POST -H "Accept: application/json" \
     -H "Content-Type: application/json" --cookie "$COOKIE" \
     "$HOST/games/42/resync.json" -i

# IGDB type-ahead
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/games/search.json?q=witness" | jq

# Calendar
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/calendar/schedule.json?types=video,game&page=1" | jq
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/calendar/month/2026/5.json" | jq

# Create a manual entry
curl -s -X POST -H "Accept: application/json" \
     -H "Content-Type: application/json" --cookie "$COOKIE" \
     -d '{
       "calendar_entry": {
         "entry_type": "milestone_manual",
         "title": "ship phase 21",
         "starts_at": "2026-06-01T10:00:00Z",
         "all_day": "no",
         "timezone": "Europe/Bucharest"
       }
     }' \
     "$HOST/calendar/entries.json" -i

# Update it
ID=<from previous response>
curl -s -X PATCH -H "Accept: application/json" \
     -H "Content-Type: application/json" --cookie "$COOKIE" \
     -d "{\"calendar_entry\": {\"title\": \"updated\"}}" \
     "$HOST/calendar/entries/$ID.json" | jq

# Soft-cancel
curl -s -X DELETE -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/deletions/calendar_entry/$ID.json" | jq

# Notifications
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/notifications.json?filter=unread&page=1" | jq
curl -s -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/notifications/badge.json" | jq

# Mark a single notification read
NID=<id from previous response>
curl -s -X PATCH -H "Accept: application/json" --cookie "$COOKIE" \
     "$HOST/notifications/$NID/read.json" | jq
```

Expected outcomes:

- All endpoints return `Content-Type: application/json`.
- Booleans render as `"yes"` / `"no"` strings, never `true`/`false`.
- Integer-id `GET /games/42.json` returns 301 with
  `Location: /games/the-witness.json`; following the redirect
  yields 200 + the detail shape.
- Posting `{"all_day": "true"}` to calendar create returns 422
  with `{ "error": "invalid_yes_no", "field": "all_day", "value": "true" }`.
- Posting twice to `/games/42/resync.json` within a few seconds
  returns 202 then 409.
- `mark_read` on a single id flips `read` to `"yes"` and decrements
  `unread_count` by 1.

Teardown: nothing persistent beyond the manual entry created above
— delete it via the soft-cancel curl above, or via the web UI's
calendar page.

## Cross-stack scope

| Surface          | Status     | Note                                                                                       |
| ---------------- | ---------- | ------------------------------------------------------------------------------------------ |
| Rails web (HTML) | unchanged  | All HTML branches are untouched. No locale changes, no view changes, no controller logic changes for HTML callers. |
| Rails JSON       | **in scope** | All work for this phase.                                                                 |
| MCP tools        | **skipped** | Follow-up phase. The new decorators here unblock that work — `Game.find(id).decorate.as_detail_json` becomes the MCP payload directly. |
| `pito` CLI       | **skipped** | Follow-up phase. Once these endpoints land, the CLI lane fans out subcommands like `pito games list`, `pito calendar month`, `pito notifications`. |
| Website          | n/a        | Marketing surface, no domain coupling.                                                   |

## Open questions

1. **Notification badge route shape** — collection or member? The
   existing notifications resource has no badge endpoint today.
   Recommendation: `GET /notifications/badge.json` as a collection
   action. The user / master agent confirm before the impl agent
   wires the route.
2. **`mark_read` 204 → 200 wire change** — the existing JSON branch
   returns `head :no_content`. No external consumer relies on the
   204 today (the CLI / MCP haven't shipped yet), so changing it
   to 200 + body is safe. The user confirms before the impl agent
   ships the change so it's an intentional break, not an accident.
3. **`POST /calendar/entries.json` parent_entry_id** — manual
   entries today can carry a `parent_entry_id` (existing strong
   params permit it). Spec assumes the JSON branch keeps that
   permission. If the master agent prefers locking parent linkage
   to the HTML form only, the impl agent strips the param from
   the JSON branch.
4. **Soft-cancel response shape** — should `cancelled` /
   `skipped` carry the full entry shape, or only `id` + `state` /
   `reason`? Spec proposes minimal `id`+`state`/`reason` to keep
   the response small (the caller can re-fetch detail if needed).
   Confirm before impl.
5. **Decorator vs. inline jbuilder** — three new decorators are
   recommended for shape reuse. The master agent may opt for
   inline jbuilder only (no new decorators) if it prefers fewer
   classes. The spec accepts either.
6. **`badge` route placement** — should it be a top-level
   `notifications/badge` collection action (recommended), or
   namespaced under `/api/notifications/badge` for consistency
   with the existing `/api/footages/...` pattern? The current
   `Api::AuthConcern` is bearer-only and would lock out the
   cookie-session caller; recommendation is to keep the route
   on the existing cookie-authed controller.
7. **`GET /games/:id.json` 301 on integer-id access** — the
   existing `FriendlyRedirect` issues a 301 for canonical
   redirect. For JSON consumers, a 301 is annoying (each must
   handle the redirect). The CLI / MCP follow-up may want to
   request a non-redirecting "use slug or id, never redirect"
   variant later. For this phase the redirect stays — drop the
   surprise into the CLI lane's lap, not Rails'.
8. **IGDB error 502 propagation in `/games/search.json`** — the
   spec says HTTP 200 with `search_error` populated. Is that the
   right call vs. propagating a 502 status? Recommendation: keep
   200 — the request succeeded, the upstream call failed; the
   caller distinguishes via the `search_error` field. Confirm.
