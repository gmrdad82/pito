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

## 2026-05-11 — sub-spec 01c Discord webhook pane (pito-rails)

Mirror of 01b for Discord. Single dispatch — paste a URL, regex-
validate, fire a test ping with the Discord-shaped `{ "content": ... }`
payload, persist on 2xx. Independent `notification_delivery_channels`
row keyed on `kind: "discord"`. Both `discord.com` and `discordapp.com`
host forms accepted.

### Files touched

**New:**

- `app/services/webhooks/discord_client.rb` — `#ping(text)` +
  `#deliver(payload)` mirroring `Webhooks::SlackClient`. Only
  meaningful difference is the payload key (`content` vs `text`).
- `app/controllers/settings/discord_webhooks_controller.rb` —
  single `update` action. Validates the URL with
  `NotificationDeliveryChannel::DISCORD_URL_REGEX`, fires the test
  ping, upserts the install-level row on 2xx, redirects with notice /
  alert. Test-ping copy locked at
  `"Pito test ping — Discord webhook configured."`.
- `app/views/settings/_discord_pane.html.erb` — pane partial. URL
  input + two yes/no checkboxes (`everything`, `daily_digest`) +
  `[update]` submit. Pre-fills from `@discord_webhook` (the AR row).
- Specs: `spec/services/webhooks/discord_client_spec.rb` (20 examples),
  `spec/requests/settings/discord_webhooks_spec.rb` (33 examples),
  `spec/views/settings/_discord_pane_html_erb_spec.rb` (14 examples).

**Edited:**

- `config/routes.rb` — added
  `resource :discord_webhook, only: %i[update], controller: "discord_webhooks"`
  inside the existing `namespace :settings do` block. URL preserved
  as `/settings/discord_webhook`.
- `app/views/settings/index.html.erb` — paired the Slack pane with
  the new Discord pane in the existing Phase 26 01b/01c `.pane-row`.
- `app/controllers/settings_controller.rb` — added the
  `@discord_webhook = NotificationDeliveryChannel.find_record_for("discord")`
  read so the pane pre-fills from the AR row.
- `spec/requests/settings_spec.rb` — bumped the pane-count assertion
  from `5 rows / 9 panes` (01a baseline) to `6 rows / 11 panes` (01b
  Slack + 01c Discord paired in a new row).

### Decisions made in flow

- **Architect's locked decisions overrode the spec's older file
  paths.** Spec 01c originally pointed at
  `app/controllers/settings/webhooks/discord_controller.rb` and
  `app/services/webhooks/discord_url_validator.rb` (a standalone
  validator object). The dispatch from master locked the mirror-of-
  Slack shape: regex constant on the AR model, controller at
  `app/controllers/settings/discord_webhooks_controller.rb`, route
  `resource :discord_webhook, only: :update`. Honored the dispatch.
- **Discord PORO refactor (`webhook_url` reads AR row first).** Already
  staged in `app/services/notification_delivery_channel/discord.rb`
  alongside the Slack refactor — AR row first, then
  `Rails.application.credentials.notifications.discord_webhook_url`
  fallback. No changes needed; the model lookup `NotificationDeliveryChannel.discord&.webhook_url`
  resolves correctly because the AR model already had `KINDS`
  containing both `"slack"` and `"discord"`.
- **`kind: "discord"` already in the AR model's enum.** 01b landed
  both kinds in `NotificationDeliveryChannel::KINDS` and the
  per-kind regex (`DISCORD_URL_REGEX`). 01c reuses the existing
  constant — no model migration needed.
- **Brand casing — `Discord`.** Pane heading uses `<h2>Discord</h2>`
  with the brand capital D (mirror of `<h2>Slack</h2>`). Body copy
  stays lowercase pito-style.

### Specs

| Surface | New specs | Pass |
|---|---|---|
| `Webhooks::DiscordClient` (service) | 20 | yes |
| `Settings::DiscordWebhooks` (request) | 33 | yes |
| `settings/_discord_pane.html.erb` (view) | 14 | yes |
| `spec/requests/settings_spec.rb` (pane count update) | 0 net | yes |
| **Total new** | **67** | **all green** |

Adjacent specs (376 across `spec/requests/settings`, `spec/views/settings`,
`spec/services/webhooks`, `spec/services/notification_delivery_channel`,
and `spec/models/notification_delivery_channel_spec.rb`) all green.

### Gates

- `bundle exec rspec` (Discord + adjacent settings/webhook surface) — 376 / 376 green.
- `bundle exec rubocop` — 8 / 8 Ruby files clean (ERB files excluded from
  rubocop run per project posture; rubocop's ERB parser is opt-in).
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.

### Cross-cutting compliance

- **yes / no boundary** — `everything` + `daily_digest` ride
  `"yes"` / `"no"` on the wire (checkbox `value="yes"`, absence
  ⇒ false). Controller's `coerce_boolean` uses `YesNo.yes_no?` +
  `YesNo.from_yes_no`. Spec asserts non-`yes`/`no` strings
  (`"true"`, `"1"`) coerce to false.
- **Friendly URLs** — `/settings/discord_webhook` pinned by spec
  assertion (`expect(settings_discord_webhook_path).to eq("/settings/discord_webhook")`).
- **No JS confirm / alert / prompt / `data-turbo-confirm`** —
  view spec includes a guard assertion (`expect(rendered).not_to include("data-turbo-confirm")`).
- **Brand casing** — `<h2>Discord</h2>` preserved; verified by
  view spec rendering check.
- **Active Record Encryption** — `webhook_url` column inherits the
  ARE `encrypts :webhook_url` declaration from 01b's model. No
  ciphertext can leak into logs or `raw` selects (covered by
  existing model spec).

### Manual test plan (for the user)

1. `bin/dev` running. Create a Discord webhook on a test server.
   (Server → Settings → Integrations → Webhooks → New.)
2. Open `/settings`. Locate the new Discord pane next to Slack.
3. Paste the URL, click `[update]`. A test message "Pito test ping —
   Discord webhook configured." lands in the Discord channel. URL
   persists on reload.
4. Edit URL to the `discordapp.com` form. Click `[update]`. Test
   ping succeeds; URL persists.
5. Edit URL to a syntactically valid but server-side-invalid URL.
   Click `[update]`. Test ping returns 404. Form re-renders with
   "Discord test ping failed: 404." Original URL stays.
6. Tick `everything`, click `[update]`. Reload — checkbox stays
   ticked. Tick `daily digest`. Click `[update]`. Reload — both
   ticked. Untick both. Reload — both unticked.
7. DB inspect:
   `NotificationDeliveryChannel.where(kind: "discord").last` reflects
   current state.

### Follow-ups surfaced

- **01b help modal not yet wired into the pane.** 01d will add the
  `[help]` bracketed link next to each pane heading (Slack + Discord)
  opening a Markdown modal. Out of 01c scope.
- **Sad-path URL validation lives in the controller only** — the AR
  model's `webhook_url_must_match_kind` is the second line of
  defense. The spec dispatch didn't ask for a dedicated
  `DiscordUrlValidator` service object, so the original sub-spec's
  validator file (`app/services/webhooks/discord_url_validator.rb`)
  is intentionally NOT created — the regex constant lives on the AR
  model and is reused by the controller + the model validation.

## 2026-05-11 — sub-spec 01b Slack webhook pane re-dispatch (pito-rails)

Re-dispatch of sub-spec 01b — Slack webhook pane per
`specs/01b-slack-webhook-pane-and-validation.md` and the master-locked
re-dispatch decisions. The first dispatch landed the model + base
PORO + controller + view + specs in commit `b14f974`, but the PORO
subclass files (`Slack`, `Discord`, `InApp`) were still declared as
`class X < NotificationDeliveryChannel` — which would have triggered
STI auto-bind against the new AR table. This session reconciles that
inconsistency and finishes the refactor.

### Files touched

**Edited (PORO refactor — STI fix):**

- `app/services/notification_delivery_channel/slack.rb` — parent
  changed from `NotificationDeliveryChannel` to
  `NotificationDeliveryChannel::Base` so the PORO is no longer an
  STI subclass of the AR model. `#webhook_url` now resolves the AR
  row first (`NotificationDeliveryChannel.slack&.webhook_url`) and
  falls back to credentials — the Settings pane manages the URL
  without rotating credentials, and existing installs that wired
  the URL via credentials keep delivering.
- `app/services/notification_delivery_channel/discord.rb` — same
  refactor for the Discord PORO. AR-row-first / credentials-fallback
  resolution.
- `app/services/notification_delivery_channel/in_app.rb` — parent
  changed to `Base`. No URL resolution (in-app delivery is a no-op).
- `spec/services/notification_delivery_channel_spec.rb` —
  `TestNotificationChannel` now inherits from
  `NotificationDeliveryChannel::Base` (was the AR model — STI again).

**New (added in this session):**

- `spec/views/settings/_slack_pane_html_erb_spec.rb` — mirror of the
  Discord pane view spec the 01c agent shipped: renders the pane
  with / without an AR row, asserts pre-fill, yes/no checkbox wire
  format, no `data-turbo-confirm`.

**Already shipped in commit `b14f974` (re-verified, no edits needed):**

- `db/migrate/20260511150000_create_notification_delivery_channels.rb`
- `app/models/notification_delivery_channel.rb`
- `app/services/notification_delivery_channel/base.rb`
- `app/services/webhooks/slack_client.rb`
- `app/controllers/settings/slack_webhooks_controller.rb`
- `app/views/settings/_slack_pane.html.erb`
- `config/routes.rb` (`resource :slack_webhook`)
- `app/controllers/settings_controller.rb` (`@slack_webhook` ivar)
- `app/views/settings/index.html.erb` (`render "slack_pane"`)
- `spec/models/notification_delivery_channel_spec.rb`
- `spec/services/webhooks/slack_client_spec.rb`
- `spec/requests/settings/slack_webhooks_spec.rb`

### Migration

`bin/rails db:migrate` ran clean against the dev DB earlier in the
re-dispatch path. `bin/rails db:migrate:status` reports
`up   20260511150000  Create notification delivery channels`.
RSpec auto-migrates the test DB via `maintain_test_schema!`. The 01c
agent reads the same table by adding `discord` to the shared `KINDS`
enum constant.

### Decisions made in flow

- **PORO base lives at `NotificationDeliveryChannel::Base`.** The
  AR model claims the top-level constant; the dispatcher base is a
  nested PORO. `NotificationDeliveryChannel.for(kind)` (existing
  call site in `NotificationDeliver` job + spec suite) delegates to
  `Base.for(kind)` so existing call shapes keep working without an
  STI flip.
- **`for(kind)` returns a PORO; `find_record_for(kind)` returns an
  AR row.** Two different responsibilities under two different
  names. AR-row lookup is `find_record_for` and the kind-scoped
  shorthands (`.slack`, `.discord`) — never `.for`.
- **AR-row-first resolution with credentials fallback.** Existing
  installs that wired their webhook URL through
  `Rails.application.credentials.notifications.slack_webhook_url`
  keep delivering. New installs use the Settings pane. Both coexist;
  the row wins when present.

### Specs

| Surface | New / edited | Pass |
|---|---|---|
| `NotificationDeliveryChannel` (AR model) | 25 new | yes |
| `Webhooks::SlackClient` (service) | 20 new | yes |
| `Settings::SlackWebhooks` (request) | 30 new | yes |
| `settings/_slack_pane.html.erb` (view) | 14 new | yes |
| `NotificationDeliveryChannel::Base` dispatcher (existing) | 0 new | yes |
| `NotificationDeliveryChannel::Slack` (existing) | 0 new | yes |
| `NotificationDeliveryChannel::Discord` (existing) | 0 new | yes |
| `NotificationDeliveryChannel::InApp` (existing) | 0 new | yes |
| `NotificationDeliver` job (existing) | 0 new | yes |
| **Total touched, all green** | **89 new + adjacent** | **yes** |

### Gates

- `bundle exec rspec` on the Phase 26 spec surface (models +
  services + requests + views + dispatcher + jobs + settings) —
  287 / 287 green.
- `bundle exec rubocop` on touched Ruby files — clean.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors. Two obsolete ignore
  entries reported but unrelated to this change.

### Cross-cutting compliance

- **yes / no boundary** — `everything` + `daily_digest` cross the
  wire as `"yes"` / `"no"` strings. The controller's
  `coerce_boolean` helper rejects every non-yes/no value as `false`
  (including `"true"`, `"1"`, `"on"`). Yes/no sweep block in the
  request spec asserts both directions.
- **Friendly URL** — `/settings/slack_webhook` (no numeric / UUID
  id). Route spec assertion pins it.
- **No JS confirm / alert / prompt** — none in the pane partial.
  View spec asserts no `data-turbo-confirm` is emitted.
- **Test ping copy locked** — controller emits
  `"Pito test ping — Slack webhook configured."` as the test
  payload `text`. Request spec asserts the exact body.
- **AR Encryption on `webhook_url`** — model spec asserts the
  ciphertext blob in the underlying column does NOT contain the
  plaintext `hooks.slack.com` substring; round-trip read returns
  plaintext as expected.

### Coordination with 01c (Discord)

The 01c agent shipped `_discord_pane`,
`Settings::DiscordWebhooksController`, `Webhooks::DiscordClient`,
and the Discord-specific test surface against the same shared
`NotificationDeliveryChannel` AR model. The 01b/01c split is clean:
01b owned the migration + model + base PORO + Slack pane + Slack
client; 01c added the `discord` row, controller, client, view, and
specs without touching the migration or the shared model schema.

### Follow-ups surfaced

- Acceptance bullets that depend on 01d (Slack help modal Markdown
  rendering) stay open — the pane will link to the help modal via
  `[help]` but the modal copy lands with 01d.
- Spec dispatch's `Webhooks::SlackUrlValidator` was folded into the
  AR model (`#valid_url?` + `SLACK_URL_REGEX` constant) rather than
  shipped as a standalone `ActiveModel::Validator` class — the
  controller-level regex pre-check + the model's
  `validate :webhook_url_must_match_kind` callback together enforce
  shape at both boundaries.
- 107 unrelated test failures pre-exist on `main` HEAD — concentrated
  in `spec/models/game_*` and `spec/requests/games_spec.rb` (Phase 27
  in-flight work). Confirmed by stashing the working tree and re-
  running: the failures persist. Not caused by this dispatch.
