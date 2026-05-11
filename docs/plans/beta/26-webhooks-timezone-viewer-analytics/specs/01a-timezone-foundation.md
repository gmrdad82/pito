# 01a — Timezone foundation

> **Foundation sub-spec — blocks 01b autosave UX, 01d, 01e, 01e digest cron, 01f
> analytics architecture, 01g viewer-time analytics, 01h scheduled publish.**
> Ship first. Implementation agent: `pito-rails`.

## Goal

Pin UTC-storage / user-tz-render as the app-wide contract for every time value.
Add a `time_zone` column to `users`, validate against the IANA tz set, default
to browser-detected zone on first authenticated load (fall back to `Etc/UTC`),
wire `Time.zone` per-request via `ApplicationController`, surface the picker on
`/settings`, and ship a small render-helper layer (`l_user_tz`) that downstream
views use for every user-facing time value. No analytics work here — this spec
is purely the foundation other sub-specs build on.

## Files touched

### New

- `db/migrate/YYYYMMDDHHMMSS_add_time_zone_to_users.rb` —
  `add_column :users, :time_zone, :string, null: false, default: "Etc/UTC"`, no
  index (low-cardinality lookups happen via `Current.user`).
- `app/models/concerns/timezoned.rb` — concern mixed into `User`. Validates
  `time_zone` is in `ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }`
  (canonical IANA set) plus the Rails-friendly aliases
  `ActiveSupport::TimeZone::MAPPING.values`. Exposes `#tz` returning the
  resolved `ActiveSupport::TimeZone` instance.
- `app/helpers/time_zone_helper.rb` — `l_user_tz(time, format: :long)` and
  `current_time_in_user_tz` helpers. `l_user_tz` accepts a `Time`, `DateTime`,
  `ActiveSupport::TimeWithZone`, or `nil` and returns the formatted user-local
  string. Nil-safe.
- `app/javascript/controllers/timezone_detect_controller.js` — Stimulus
  controller mounted on the layout `<body>` on first authenticated load. If
  `Current.user.time_zone == "Etc/UTC"` (the sentinel "never set"), the
  controller POSTs `Intl.DateTimeFormat().resolvedOptions().timeZone` to
  `PATCH /settings/time_zone` and re-renders the page via Turbo. **No JS
  `confirm`** — silent persist on first load only; the user may override on
  Settings.
- `app/controllers/settings/time_zone_controller.rb` — single `update` action.
  Accepts `{ time_zone: "Europe/Bucharest" }` (the JS-detected zone on first
  load) OR the form-submitted zone from Settings. Validates, saves, returns 204
  on success / 422 with the validation message on failure.
- `app/views/settings/_time_zone_pane.html.erb` — Settings pane: dropdown
  `<select>` of
  `ActiveSupport::TimeZone.all.map { |z| [z.name, z.tzinfo.name] }`
  (Rails-friendly label, IANA value stored), `[update]` submit, hint text
  "Affects how every time is rendered across pito."
- Specs:
  - `spec/models/concerns/timezoned_spec.rb` — validation + `#tz` resolution.
  - `spec/models/user_spec.rb` — extend with timezone-related cases.
  - `spec/helpers/time_zone_helper_spec.rb` — `l_user_tz` happy / sad / edge
    (nil input, `Time` vs `DateTime` vs `TimeWithZone`, DST cross-over).
  - `spec/requests/settings/time_zone_spec.rb` — PATCH happy / sad / yes-no
    boundary / invalid zone / unauthenticated.
  - `spec/system/settings_time_zone_spec.rb` — critical journey: pick a zone
    from the Settings dropdown, hit `[update]`, observe the layout's rendered
    times change immediately.
  - `spec/system/timezone_detect_spec.rb` — critical journey: simulate JS
    detection, assert silent PATCH happens on first load only.

### Edited

- `app/models/user.rb` — `include Timezoned`. No other change.
- `app/controllers/application_controller.rb` — add a `before_action` setting
  `Time.zone = Current.user&.time_zone || "Etc/UTC"`. Existing `Current.user`
  block stays.
- `app/views/layouts/application.html.erb` — mount the timezone-detect Stimulus
  controller. Add a small header span rendering
  `<%= l_user_tz(Time.current, format: :short) %>` for visual confirmation on
  every page (verify with user during dispatch — could be tucked into the
  existing chrome rather than always-on).
- `app/views/settings/index.html.erb` — render the new `_time_zone_pane` among
  the existing Settings panes.
- `config/routes.rb` —
  `resource :time_zone, only: %i[update], controller: "settings/time_zone"`
  nested under the existing `/settings` namespace. URL:
  `PATCH /settings/time_zone`. Friendly URL preserved.
- `docs/architecture.md` — referenced by 01f (analytics docs update); not edited
  here.

### Read-only inputs

- `app/controllers/application_controller.rb` (existing `Current.user` wiring).
- `app/views/settings/index.html.erb` (existing pane grid).
- `config/locales/en.yml` (extend with new copy strings).

## Acceptance

- [ ] Migration adds `time_zone` to `users`, NOT NULL, default `"Etc/UTC"`.
      Existing rows backfilled to `"Etc/UTC"` (default takes care of it).
- [ ] `User` validates `time_zone` against the IANA tz set + Rails alias
      mapping. Invalid values fail with a friendly message.
- [ ] `ApplicationController` sets `Time.zone` per request from
      `Current.user.time_zone`. Unauthenticated requests fall back to `Etc/UTC`.
- [ ] `l_user_tz(time, format: :long | :short)` helper exists, nil-safe,
      delegates through `Time.zone` for conversion.
- [ ] Settings `/settings` page renders a timezone dropdown with all valid IANA
      zones, current value pre-selected, `[update]` per pane (matching existing
      Settings pattern).
- [ ] On the first authenticated page load where `time_zone == "Etc/UTC"`, the
      JS Stimulus controller detects the browser zone via
      `Intl.DateTimeFormat().resolvedOptions().timeZone` and PATCHes
      `/settings/time_zone` silently. Subsequent loads do not re-detect.
- [ ] `PATCH /settings/time_zone` rejects unknown zones with 422.
- [ ] Every yes / no boundary in the controller / Stimulus / spec assertions
      uses `"yes"` / `"no"` strings (the detect flow does not carry a Boolean,
      but the spec sweep verifies the rule).
- [ ] Friendly URL `/settings/time_zone` is preserved (no UUID / numeric ID).
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`. The detect
      flow is silent on first load; Settings updates go through the normal form
      submit.
- [ ] Spec pyramid: model (Timezoned concern + User), helper, request, system
      (critical journey only — picker + detect). No new service / job /
      component / validator / lib / MCP tool needed for this foundation
      (downstream sub-specs add those).
- [ ] Brakeman + bundler-audit clean.
- [ ] `docs/architecture.md` is NOT edited here. 01f owns that.

## Manual test recipe

1. `bin/setup` to apply the migration. `bin/dev` to start the stack.
2. Open `/settings` in a fresh browser session (where the user's `time_zone` is
   still `Etc/UTC`). Watch the network tab: a silent `PATCH /settings/time_zone`
   fires with the browser-detected zone (likely `Europe/Bucharest`). Reload — no
   second detect call.
3. Pick a different zone (e.g., `America/Los_Angeles`) from the dropdown, hit
   `[update]`. The page reloads with the new zone applied; any rendered time
   value (the header span if it's wired) shows the new local time.
4. Open a Rails console: `User.last.update!(time_zone: "Pacific/Kiritimati")`.
   Reload the Settings page — the dropdown shows the new zone, the rendered
   times are 14 hours ahead of UTC.
5. Try to PATCH with an invalid zone:
   ```
   curl -X PATCH http://127.0.0.1:3027/settings/time_zone \
     -b cookies.txt -d 'time_zone=Mars/Olympus_Mons'
   ```
   Expect a 422 with the validation message.

## Cross-stack scope

| Surface | Status  | Note                                                 |
| ------- | ------- | ---------------------------------------------------- |
| Web     | in      | Foundation; primary surface.                         |
| MCP     | partial | Tool surface to read / update user tz lives in the   |
|         |         | existing settings MCP namespace (verify exact name   |
|         |         | during dispatch). Yes / no boundary applies to any   |
|         |         | flag carried alongside the tz string.                |
| CLI     | in      | `pito settings` reads / writes user tz (mirror Rails |
|         |         | dropdown via TUI picker). Yes / no boundary applies  |
|         |         | to any flag at the wire.                             |
| Website | out     | No change.                                           |

## Open questions

1. **YouTube channel tz field surfacing.** The Mobile note says "verify if Phase
   7.5 Step 11 captured the channel tz field." YouTube Data API does NOT expose
   a channel-level `timeZone` directly; we may derive from `country` +
   `defaultLanguage`. v1 records whatever YouTube returns and surfaces it raw on
   the channel show page (Phase 26's tz scope only adds the user-side;
   channel-side surfacing is a follow-up). **Confirm with user before
   dispatch.**
2. **Cross-tz diff dialog labeling.** When a user's tz differs from a tracked
   channel's tz, every diff dialog needs to label both columns explicitly. v1
   copy suggestion: `"Pito (your tz: Europe/Bucharest)"` vs
   `"YouTube (channel tz: America/Los_Angeles)"`. **Confirm copy with user.**
3. **Header-chrome rendering of `current_time_in_user_tz`.** The Mobile note
   doesn't mandate a header time display, but it's the cheapest visual
   confirmation the user has the right zone. **Confirm with user — yes (add to
   header), no (skip), or only on Settings page?**
4. **MCP tool surface for tz update.** Phase 16 / Settings already exposes a
   per-user settings tool (verify exact name). Extending it to accept
   `time_zone` is one line. **Confirm with user the MCP tool name + scope.**
