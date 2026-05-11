# Phase 26 — log

## 2026-05-11 — sub-spec 01a Timezone foundation (pito-rails)

Implemented sub-spec 01a — Timezone foundation per
`specs/01a-timezone-foundation.md`. Foundation work that pins
UTC-storage / user-tz-render as the app-wide contract and unblocks
01d, 01e, 01f, 01g, 01h.

### Files touched

**New:**

- `db/migrate/20260511132718_add_time_zone_to_users.rb` — adds
  `users.time_zone` (string, NOT NULL, default `"Etc/UTC"`).
- `app/models/concerns/timezoned.rb` — `Timezoned` concern mixed into
  `User`. Validates `time_zone` against the union of
  `TZInfo::Timezone.all_identifiers` (full IANA set) +
  `ActiveSupport::TimeZone::MAPPING.{keys,values}` (Rails aliases) —
  exposes `#tz` returning the resolved `ActiveSupport::TimeZone`
  instance, with `Etc/UTC` fallback for corrupted stored values.
- `app/helpers/time_zone_helper.rb` — `l_user_tz(time, format:)`
  render helper (`:long` default, `:short`, `:date`, `:iso`) and
  `current_time_in_user_tz(format:)` convenience helper. Nil-safe,
  accepts `Time`, `DateTime`, `ActiveSupport::TimeWithZone`.
- `app/controllers/settings/time_zone_controller.rb` — single
  `update` action. HTML caller (Settings dropdown) redirects with
  flash; JSON / detect caller gets 204 / 422.
- `app/views/settings/_time_zone_pane.html.erb` — Settings pane
  carrying a two-optgroup dropdown ("common" + "all IANA") so every
  IANA zone is reachable from the UI (acceptance bullet "all valid
  IANA zones").
- `app/javascript/controllers/timezone_detect_controller.js` —
  Stimulus controller mounted on `<body>`. On first authenticated
  load (stored zone == `"Etc/UTC"` sentinel) detects the browser zone
  via `Intl.DateTimeFormat().resolvedOptions().timeZone` and silently
  PATCHes `/settings/time_zone`. No JS confirm/alert/prompt. Reads
  the CSRF token from the layout meta tag and forwards it as
  `X-CSRF-Token`.
- Specs: `spec/models/concerns/timezoned_spec.rb`,
  `spec/helpers/time_zone_helper_spec.rb`,
  `spec/requests/settings/time_zone_spec.rb`,
  `spec/system/settings_time_zone_spec.rb`,
  `spec/system/timezone_detect_spec.rb`.

**Edited:**

- `app/models/user.rb` — `include Timezoned`.
- `app/controllers/application_controller.rb` — added
  `before_action :set_user_time_zone`. Sets `Time.zone = Current.user&.time_zone.presence || "Etc/UTC"`
  per request.
- `app/views/layouts/application.html.erb` — mounted the
  `timezone-detect` Stimulus controller on `<body>` and conditionally
  carry the stored zone + URL + CSRF token via Stimulus values on
  authenticated layouts. The data attribute is omitted on
  unauthenticated screens (login, OAuth consent) so the controller
  bails on its own.
- `app/views/settings/index.html.erb` — paired the previously
  single-pane "user" row with the new timezone pane (now two-pane row).
- `config/routes.rb` — added
  `resource :time_zone, only: %i[update], controller: "time_zone"`
  inside the existing `namespace :settings do` block. URL preserved
  as the friendly `/settings/time_zone` (no numeric / UUID).
- `spec/models/user_spec.rb` — extended with `describe "time_zone column"` block.
- `spec/requests/settings_spec.rb` — bumped pane count from 8 to 9
  (the new timezone pane joins row 4 / paired-user row).

### Migration

`bin/rails db:migrate` ran clean against the dev DB. Schema
diff:

```
t.string "time_zone", default: "Etc/UTC", null: false
```

### Decisions made in flow

- **Dropdown scope expanded.** The spec said the dropdown lists
  `ActiveSupport::TimeZone.all.map { |z| [z.name, z.tzinfo.name] }`
  (Rails-curated 152 zones), but the Acceptance bullet says "all
  valid IANA zones". Reconciled by splitting the `<select>` into two
  `<optgroup>` blocks — `common` (the curated friendly subset) and
  `all IANA` (the rest of `TZInfo::Timezone.all_identifiers`). All
  values persist as canonical IANA names.
- **Validator scope expanded.** The locked decision said validate
  against `ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)` +
  alias mapping, but that misses edge zones the Acceptance bullet
  required (`Pacific/Kiritimati`, `Pacific/Pago_Pago`). Switched the
  allow-list source to `TZInfo::Timezone.all_identifiers` (full IANA
  set) so JS-detected names always validate. Rails alias keys + values
  still in the set so `"UTC"`-style inputs work.
- **Header chrome render of `current_time_in_user_tz`.** Open
  question (sub-spec OQ 3) on whether to render a visual confirmation
  in the header. Skipped — the helper exists for downstream sub-specs
  to consume, and the spec's acceptance only requires its definition.
  Master agent can surface the question to the user before 01b-01h
  land.
- **MCP tool surface for tz update.** Sub-spec OQ 4 + cross-stack
  scope note. Spec's Acceptance explicitly carves out: "No new
  service / job / component / validator / lib / MCP tool needed for
  this foundation (downstream sub-specs add those)." Deferred.
- **CLI parity (`pito settings show / set_tz`).** Out of this agent's
  file scope (`extras/` is owned by `pito-rust`). Deferred.

### Specs

| Surface | New specs | Pass |
|---|---|---|
| `Timezoned` concern (model) | 18 | yes |
| `User` model (tz block extension) | 5 | yes |
| `TimeZoneHelper` (helper) | 18 | yes |
| `Settings::TimeZone` (request) | 12 | yes |
| `Settings → time zone pane` (system) | 4 | yes |
| `Timezone first-load detect` (system) | 4 | yes |
| **Total new** | **61** | **all green** |

Edited spec (`spec/requests/settings_spec.rb`) bumps the pane count
assertion from 8 → 9.

### Gates

- `bundle exec rspec` — 151 / 151 green across touched specs
  (1685 / 1685 across the wider `spec/controllers spec/requests` set
  except one **pre-existing** failure unrelated to this work:
  `spec/requests/concerns/sessions/auth_concern_spec.rb:57` —
  POSTs to `/channels` which is not a valid route on `main` HEAD;
  confirmed by re-running after stashing all changes).
- `bundle exec rubocop` — 1061 / 1061 files clean.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.

### Cross-cutting compliance

- **yes / no boundary** — the tz update flow carries no external
  Boolean (only the `time_zone` string). Sweep spec backstop in the
  request spec asserts the response body contains no
  `"true"` / `"false"` literals.
- **Friendly URLs** — `/settings/time_zone` is the canonical
  surface; route spec assertion pins it.
- **No JS confirm / alert / prompt** — the Stimulus detect controller
  is silent on success and silent on failure (the user can override
  via the Settings dropdown). The dropdown form is a normal POST
  redirect.
- **Brand casing** — "pito" lowercase preserved in the pane hint
  text ("affects how every time is rendered across pito.").

### Manual test plan (for the user)

1. `bin/rails db:migrate` — confirm the migration ran (already done
   in this session against dev DB).
2. `bin/dev` to start the stack.
3. Open `/settings` in a fresh browser session (where the user's
   `time_zone` is still `"Etc/UTC"`). Watch the network tab: a silent
   `PATCH /settings/time_zone` fires with the browser-detected zone
   (likely `"Europe/Bucharest"`). Reload — no second detect call.
4. Pick a different zone (e.g. `"America/Los_Angeles"`) from the
   dropdown's `common` optgroup, hit `[update]`. The page redirects
   to `/settings` with the new zone applied (the dropdown re-renders
   with the selected option).
5. Pick an edge zone (e.g. `"Pacific/Kiritimati"`) from the
   `all IANA` optgroup, hit `[update]`. Same result — persisted via
   the full-IANA allow-list.
6. Open a Rails console:
   `User.last.update!(time_zone: "Pacific/Kiritimati")`. Reload
   `/settings` — the dropdown shows the new zone pre-selected.
7. Try to PATCH with an invalid zone:
   ```sh
   curl -X PATCH http://127.0.0.1:3027/settings/time_zone \
     -b cookies.txt -d 'time_zone=Mars/Olympus_Mons'
   ```
   Expect a 422 (JSON / detect caller) or redirect with flash
   alert (HTML caller).

### Follow-ups surfaced

- Header chrome rendering of `current_time_in_user_tz` (sub-spec
  OQ 3) — decision deferred to master agent.
- MCP tool for user tz read / update (umbrella locked decision
  mentions "existing settings MCP namespace" — current
  `manage_settings` MCP tool is app-settings, not user-settings; a
  new `user_settings` MCP tool is out of this sub-spec's scope).
- CLI parity (`pito settings show` / `set_tz`) — `extras/cli/`
  changes belong to `pito-rust`; defer dispatch.

### Open follow-ups from umbrella

OQ 1 (YouTube channel tz field) and OQ 2 (cross-tz diff dialog
copy) referenced by 01a — both are content / surfacing questions
not blocking this foundation. Surface to user before any sub-spec
that consumes them.
