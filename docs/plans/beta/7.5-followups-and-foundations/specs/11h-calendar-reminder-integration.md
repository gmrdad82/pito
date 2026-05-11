# Phase 7.5 — Step 11h — Calendar Reminder Integration

> Sub-spec of Step 11 (Channel Revamp). Wires the 14-day title/handle unlock
> gate on `/channels/:slug/edit` to the existing Phase 15 `Calendar::Entry`
> model via the Phase 21 JSON endpoint. The user clicks
> `[remind me on YYYY-MM-DD]`, the server silently creates a reminder, and a
> toast confirms — no redirect, no edit-form lock, no new controller, no new
> model, no new migration.

Source of truth: parent Step 11 spec, locked decision **D19** + **Q1**
resolution — silent auto-create reminder + toast confirmation, NO redirect.

---

## Goal

When the title or handle gate on `/channels/:slug/edit` is locked (the field was
last changed less than 14 days ago), render a `[remind me on YYYY-MM-DD]` link
adjacent to the gate message. Clicking it POSTs a prefilled body to the existing
Phase 21 JSON endpoint `POST /calendar/entries.json`, the server creates a
`Calendar::Entry` of `kind: "reminder"` for the exact unlock date, and the
client renders a flash-style toast confirming the date. The user stays on the
edit form. The created entry surfaces in the regular `/calendar` schedule +
month views, where it can be edited, cancelled, or viewed later.

This closes the gap between "the gate told me when I can rename" and "I will
actually remember to come back on that date" without dragging the user away from
the form they're already on. No new server-side surface; only a Stimulus
controller, a small view change, and (if missing) a tiny shared toast partial.

## Files touched

### New

- `app/javascript/controllers/calendar_reminder_create_controller.js` — Stimulus
  controller. Targets: the `[remind me on YYYY-MM-DD]` link and a toast slot. On
  click: prevent default, POST JSON to `/calendar/entries.json`, render a toast
  with the returned date on success, render an error toast on failure. Reads the
  prefill payload from `data-calendar-reminder-create-*` values on the link.

### Edited

- `app/views/channels/edit.html.erb` — only the 14-day gate row. Add the
  `[remind me on YYYY-MM-DD]` link with:
  - `data-controller="calendar-reminder-create"`
  - `data-action="click->calendar-reminder-create#create"`
  - `data-calendar-reminder-create-unlock-date-value` — the ISO unlock date
    (`title_changed_at + 14.days` or `handle_changed_at + 14.days`, whichever
    field this gate row is for; formatted as `YYYY-MM-DD` in the channel
    timezone — see Open question on time-of-day default).
  - `data-calendar-reminder-create-channel-id-value` — the channel id.
  - `data-calendar-reminder-create-channel-name-value` — the channel display
    name (server-rendered, HTML-escaped via standard ERB; the Stimulus
    controller treats it as a plain string when composing the title body — it
    does NOT inject it into the DOM unsanitised).
  - `data-calendar-reminder-create-gate-kind-value` — `"title"` or `"handle"`
    (so the title body can read "Channel title unlock — …" or "Channel handle
    unlock — …" — see Open question 2 if the user wants a single shape).
  - `data-calendar-reminder-create-csrf-value` — the request CSRF token
    (`form_authenticity_token`), since this is a JSON POST outside a
    `form_with`.
  - `data-calendar-reminder-create-toast-target` (separate element below the
    gate row, an empty `div` that the controller fills on response).

### Edited or created (shared toast)

- `app/views/shared/_toast.html.erb` — reuse if it exists. If not, create as a
  minimal partial that renders a `<div class="toast">` with the message slot and
  the existing flash styling (top-right, matches existing flash convention — see
  Open question 1). The Stimulus controller calls
  `/* fetch */ then renders the partial inline by injecting an HTML string`, OR
  — preferred — the JSON response carries the rendered toast HTML in a
  `toast_html` key so the server controls the markup. Defer the choice to the
  rails-impl agent; either is acceptable as long as the toast styling matches
  the existing flash convention and no new toast CSS is invented.

### Routes / controllers / models / migrations

- No new routes.
- No new controllers. `POST /calendar/entries.json` already exists from
  Phase 21.
- No new models. `Calendar::Entry` already exists from Phase 15.
- No migrations.

### Specs (see "Spec pyramid" below)

- `spec/javascript/controllers/calendar_reminder_create_controller_spec.js` —
  only if the project has JS unit-spec scaffolding. If not, system spec covers
  controller behavior. Confirm with rails-impl on dispatch.
- `spec/system/channels/edit_calendar_reminder_spec.rb` (new) — the critical
  user journey: click the link → toast appears → DB has the entry.
- `spec/requests/calendar/entries_spec.rb` — extend existing Phase 21 request
  spec with the reminder-kind / unlock-date payload variant (do NOT duplicate
  coverage Phase 21 already has; only add the variant if it isn't already
  there).

## Acceptance

- [ ] `/channels/:slug/edit` renders `[remind me on YYYY-MM-DD]` adjacent to
      every locked 14-day gate row (title gate AND handle gate, if both are
      locked).
- [ ] The link is omitted when the gate is NOT locked (i.e., the field is
      currently editable).
- [ ] The link's date matches `title_changed_at + 14.days` (or
      `handle_changed_at + 14.days`) rendered in the configured timezone, as
      `YYYY-MM-DD`.
- [ ] Clicking the link sends `POST /calendar/entries.json` with body:
      `json     {       "kind": "reminder",       "title": "Channel title unlock — <channel name>",       "starts_at": "<unlock_date in configured timezone>",       "ends_at": null,       "all_day": "yes"     }     `
      (External boolean encoded as `"yes"` per the yes / no boundary hard rule.)
- [ ] On success (201), the toast slot renders `Reminder created for YYYY-MM-DD`
      using the existing flash styling.
- [ ] On network or server failure, the toast slot renders
      `Couldn't create reminder; try again` and does NOT break the edit form (no
      field state lost, no inputs disabled).
- [ ] Rate-limit collision (Phase 21 endpoint returns 429 on rapid double-
      click) renders the same generic failure toast. No second `Calendar::Entry`
      row is created. Spec asserts DB row count stays at 1 across two rapid
      clicks.
- [ ] The CSRF token is read from the link's data attribute (rendered server-
      side via `form_authenticity_token`), included in the fetch as
      `X-CSRF-Token`, and the request succeeds against the standard Rails CSRF
      filter.
- [ ] Channel name is HTML-escaped server-side in the data attribute (standard
      ERB escaping). The Stimulus controller does NOT use `innerHTML` to render
      the channel name anywhere; if it composes the title body, it sends it as a
      plain JSON string and trusts server-side `Calendar::Entry` validation
      (Phase 15) to enforce length / character rules.
- [ ] The created entry is visible at `/calendar` (schedule view + month view)
      without any further work — Phase 15 + Phase 21 already wire that.
- [ ] System spec covers the happy path end-to-end: click → toast text asserted
      → `Calendar::Entry.where(kind: "reminder").count` incremented by 1 → DB
      row's `starts_at`, `kind`, and `title` match the expected values.
- [ ] Request spec confirms the reminder variant of the JSON endpoint
      (`kind: "reminder"`, `all_day: "yes"`, `ends_at: null`) returns 201 with a
      minimal JSON envelope
      (`{ "id": <id>, "kind": "reminder",     "starts_at": "YYYY-MM-DD" }` or
      whatever Phase 21 already declared as the canonical envelope — do NOT
      introduce a new shape).
- [ ] Sad-path request spec: invalid `starts_at` returns 4xx and no DB row is
      created (existing Phase 21 coverage; confirm it covers this variant).
- [ ] XSS smoke: a channel named `<script>alert(1)</script>` does NOT execute JS
      when its edit page is rendered (existing ERB escaping covers the view) and
      does NOT execute JS when the entry surfaces in `/calendar` (Phase 15
      `Calendar::Entry` title validation + view-side escaping cover that).
      System spec asserts the literal angle-bracket text appears in the DOM as
      text, not as a `<script>` node.
- [ ] No new JS `alert` / `confirm` / `prompt` / `data-turbo-confirm` anywhere.
      The toast is a passive flash, not a confirmation prompt.
- [ ] No new `BracketedLinkComponent` variants or kwargs invented; the
      `[remind me on YYYY-MM-DD]` link uses the existing component with
      `data-action` and `data-*` values wired through whatever the component
      already accepts.

## Manual test recipe

1. `bin/dev` up. Log in as the seed owner.
2. Create or open an existing channel. Edit its title (or handle), save.
3. Re-open `/channels/<slug>/edit`. The title gate (or handle gate) is now
   locked.
4. Confirm a `[remind me on YYYY-MM-DD]` link is rendered adjacent to the gate
   message, with a date that is 14 days after the change.
5. Click the link. Confirm a top-right toast appears with the text
   `Reminder created for YYYY-MM-DD` (date matching the link's date).
6. Confirm the page does NOT navigate. The form fields retain their state.
7. Open a new tab to `/calendar`. Confirm the reminder appears in both the
   schedule view and the month view, on the expected date, with title
   `Channel title unlock — <channel name>` (or `Channel handle unlock — …`).
8. Back on `/channels/<slug>/edit`, click `[remind me on YYYY-MM-DD]` again
   rapidly twice. Confirm only one toast (or one success + one rate-limit
   failure toast) appears, and that `Calendar::Entry.count` only incremented by
   1 in `bin/rails runner 'p Calendar::Entry.where(kind: "reminder").count'`.
9. Network-failure sim: open DevTools → Network → set throttling to "Offline",
   click `[remind me on YYYY-MM-DD]`. Confirm the failure toast shows and the
   edit form is still usable (fields editable, no spinners stuck).
10. XSS sim: rename a test channel to `<script>alert("x")</script>`, save, wait
    until past the 14-day unlock (or temporarily backdate `title_changed_at` via
    `bin/rails runner` for the test). Re-open `/channels/<slug>/edit`, click
    `[remind me]`, confirm the alert does NOT fire on edit page OR on
    `/calendar`.

Teardown:
`bin/rails runner 'Calendar::Entry.where(kind: "reminder").destroy_all'` to
clear test reminders.

## Cross-stack scope

- **Rails web app** — in scope. Stimulus controller + view edit + (maybe) toast
  partial + specs.
- **MCP** — skipped. The 14-day gate is a web-form-side ergonomic; MCP edits
  don't render the form. If a user wants a reminder via MCP, they call
  `create_calendar_entry` directly (Phase 15 / 21 surface). Add a note in
  `docs/mcp.md` ONLY if the docs-keeper agent later decides MCP needs a parity
  helper; not in scope here.
- **`pito` CLI** — skipped. The CLI's channel edit screen (if any) handles the
  14-day gate per its own conventions; mirroring this reminder ergonomic is a
  Phase 11 sub-task tracked separately, not here.
- **Website (`extras/website/`)** — out of scope. Marketing surface only.

## Open questions

1. **Toast position.** Top-right (matches existing flash convention) or
   bottom-of-form (closer to the click)? **Recommendation:** top-right, match
   the existing flash. Confirm with user before dispatch.
2. **Reminder time-of-day default.** Midnight in `AppSetting.first.timezone`
   (Phase 15 convention) or in UTC or in the user's browser-local timezone?
   **Recommendation:** `AppSetting.first.timezone` at 00:00 local, since
   `all_day: "yes"` already collapses the display to a date-only render — the
   underlying `starts_at` only matters for sort order in the schedule view.
   Confirm.
3. **Duplicate handling.** If a `Calendar::Entry` with `kind: "reminder"` AND a
   title matching `"Channel title unlock — <channel name>"` (or the handle
   variant) AND `starts_at` matching the unlock date already exists, do we
   create a duplicate or no-op? **Recommendation:** no-op + toast
   `Reminder already exists for YYYY-MM-DD`. The endpoint stays idempotent for
   this narrow case. Phase 21's endpoint may or may not have this uniqueness
   scope today — confirm with the user / docs whether Phase 21 added it; if not,
   this sub-spec needs to extend the endpoint with a uniqueness check OR move
   the duplicate detection client-side (less robust). Flagging as a blocker for
   dispatch.
4. **Title body shape.** The user-supplied source-of-truth body is
   `"Channel title unlock — <channel name>"`. Should the handle gate use
   `"Channel handle unlock — <channel name>"` (parallel shape) or a single
   generic `"Channel rename unlock — <channel name>"` covering both? Defer to
   user.
5. **Channel name source.** `Channel` currently uses `id.to_s` as a label
   placeholder (per `CLAUDE.md` architecture notes — display field is gone until
   Phase 8 sync repopulates it). What goes in `<channel name>` until then — the
   `channel_url`, the `id`, or whatever the decorator resolves to?
   **Recommendation:** match whatever `app/views/channels/edit.html.erb` already
   renders for the page H1, so the toast / calendar entry / edit page all say
   the same thing. Confirm.
