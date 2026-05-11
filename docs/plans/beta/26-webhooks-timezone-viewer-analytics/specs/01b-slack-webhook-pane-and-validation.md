# 01b — Slack webhook pane + validation

> Settings pane for Slack incoming webhooks. Writes one row to the existing
> `notification_delivery_channels` table (Phase 16). Mandatory test ping before
> save. Per-provider state: `everything` + `daily_digest` booleans. Can ship
> parallel with 01c (Discord). Implementation agent: `pito-rails`.

## Goal

Add a `slack` pane on `/settings` with a single URL input, provider-specific
regex validation, a mandatory test ping (must succeed before the URL is saved),
and two checkboxes that persist per-provider state. The pane reads from and
writes to the existing `notification_delivery_channels` table — keyed on
`kind: "slack"` — that Phase 16 ships. No new table is created.

## Files touched

### New

- `app/controllers/settings/webhooks/slack_controller.rb` — `update` action.
  Validates URL shape via the Slack regex, sends a test ping via
  `Webhooks::SlackClient#ping`, persists the `notification_delivery_channels`
  row only if the ping returns HTTP 2xx, re-renders the form with the error
  message if the ping fails.
- `app/services/webhooks/slack_client.rb` — wraps `Net::HTTP` POST. Public
  methods: `#ping` (sends a fixed "hi from pito" payload, returns
  `Result.new(success:, status:, body:, error:)`), `#deliver(payload)` (used by
  01e for digest delivery; bodied with provider-specific blocks). Timeout: 5s.
  No retries here — retries live in the delivery job (01e).
- `app/services/webhooks/slack_url_validator.rb` — custom validator. Regex
  `\Ahttps://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+\z`.
  Used by the controller and by the `NotificationDeliveryChannel#valid_url?`
  model method.
- `app/views/settings/_slack_pane.html.erb` — pane following the existing
  Settings pane primitives (`.pane`, bracketed links, monospace font). URL
  input, `[update]` submit, `[help]` link opening the 01d modal, two
  `<input type="checkbox">` for `everything` + `daily_digest`. Hint under
  `daily digest`: "Sent daily at 09:00 in your timezone."
- Specs:
  - `spec/models/notification_delivery_channel_spec.rb` — extend for the `slack`
    kind: validation cases, `valid_url?` cases, scope test for the "find by
    kind" lookup. (The model itself already exists from Phase 16; this spec just
    extends it.)
  - `spec/services/webhooks/slack_client_spec.rb` — `#ping` happy (200) + sad
    (400, 404, 500) + edge (timeout, DNS failure). Uses WebMock. `#deliver`
    covered by 01e.
  - `spec/services/webhooks/slack_url_validator_spec.rb` — happy / sad / edge
    inputs (valid, missing host, missing services prefix, missing bot token
    segment, http instead of https, trailing whitespace, etc.).
  - `spec/requests/settings/webhooks/slack_spec.rb` — PATCH happy / sad / yes-no
    boundary on `everything` + `daily_digest` / invalid URL / failing test ping
    / unauthenticated / CSRF reject. Yes / no strings at the wire convert to
    Boolean storage.
  - `spec/system/settings_slack_webhook_spec.rb` — critical journey: paste valid
    URL, tick `daily digest`, click `[update]`, see success + persisted state on
    reload.

### Edited

- `app/views/settings/index.html.erb` — render `_slack_pane` among the existing
  Settings panes.
- `config/routes.rb` —
  `namespace :settings do; resource :slack_webhook, only: %i[update], controller: "settings/webhooks/slack" ; end`.
  URL: `PATCH /settings/slack_webhook`. Friendly URL preserved.
- `app/models/notification_delivery_channel.rb` — extend with a `kind`- scoped
  finder (`.for_slack`, `.for_discord`) and the `#valid_url?` method that
  dispatches to the provider's validator. (Phase 16 ships the table + base
  model; this sub-spec extends it.)
- `config/locales/en.yml` — error messages: `invalid_slack_url`,
  `slack_ping_failed`, `slack_saved`.

### Read-only inputs

- The Phase 16 `notification_delivery_channels` table schema (columns:
  `id, kind, config (jsonb), immediate_kinds (text[]), digest_enabled, digest_at_local_time, user_id, timestamps`
  — verify exact shape when dispatching).
- `app/helpers/time_zone_helper.rb` (from 01a) — used to render the per-user
  09:00 hint text in the user's local zone.

## Acceptance

- [ ] Pane renders on `/settings` with current state pre-filled. If no
      `notification_delivery_channel` row exists for `kind: "slack"`, both
      checkboxes are unchecked, URL input empty.
- [ ] URL input validated against the Slack regex. Bad shapes fail before the
      test-ping fires (422 with friendly error).
- [ ] Valid URL triggers the test ping. If ping fails (HTTP non-2xx, timeout,
      DNS failure), the URL is NOT saved and the form re-renders with the
      provider's error message. If ping succeeds (HTTP 2xx), the URL persists.
- [ ] `everything` and `daily_digest` are independent booleans. Both / neither /
      either is a valid combination. Each checkbox saves on `[update]` (no
      autosave — match existing Settings pattern; **confirm with user before
      dispatch**).
- [ ] Yes / no boundary: form payload uses `"yes"` / `"no"` for the two
      booleans; internal storage is Boolean. Controller converts at the
      boundary.
- [ ] One row per user per provider in `notification_delivery_channels`. Update
      path mutates the existing row; first save creates it.
- [ ] `[help]` link opens the 01d Slack help modal (Markdown-rendered).
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`.
- [ ] Friendly URL preserved: `/settings/slack_webhook`.
- [ ] Spec pyramid covers: model extension, service (`SlackClient`), validator
      (`SlackUrlValidator`), request (controller), system (critical journey). No
      new job here — delivery jobs are 01e.
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/dev` running. Create a fresh Slack workspace + test channel, follow the
   in-app Slack help modal (01d) to mint a webhook URL.
2. Open `/settings`. Locate the Slack pane.
3. Paste the URL, leave both checkboxes unchecked, click `[update]`. A test
   message "hi from pito" lands in the Slack channel. The pane shows the URL
   persisted on reload.
4. Edit the URL to something garbage like `https://hooks.slack.com/foo`. Click
   `[update]`. The form re-renders with "Invalid Slack webhook URL." The
   original URL stays in the DB.
5. Edit the URL to a syntactically valid but server-side-invalid URL (e.g.,
   replace the last segment with random chars). Click `[update]`. The test ping
   returns 404. The form re-renders with "Slack test ping failed: 404." The
   original URL stays.
6. Tick `everything`, untick `daily digest`, click `[update]`. Reload —
   `everything` is on, `daily digest` is off. Tick both. Click `[update]`.
   Reload — both on. Untick both. Reload — both off.
7. Inspect the DB:
   `Rails.cache.clear; NotificationDeliveryChannel.where(kind: "slack").last`
   should reflect the current pane state.

## Cross-stack scope

| Surface | Status | Note                                                 |
| ------- | ------ | ---------------------------------------------------- |
| Web     | in     | Primary surface.                                     |
| MCP     | out    | Webhook config is web-only for v1. (Future: a tool   |
|         |        | for Mobile Claude to list / rotate webhooks — out of |
|         |        | scope here.)                                         |
| CLI     | out    | Server-side delivery surface; CLI does not configure |
|         |        | webhooks.                                            |
| Website | out    | No change.                                           |

## Open questions

1. **Autosave vs `[update]`.** Existing Settings panes use explicit `[update]`.
   Spec recommends `[update]` for parity. **Confirm with user before dispatch.**
2. **2FA gate on URL change.** The webhook URL is a delivery secret; replacing
   it is sensitive. v1 leans "normal Settings update, no extra 2FA hop" until
   app-wide 2FA ships. **Confirm with user.**
3. **Test-ping payload copy.** v1 sends
   `"hi from pito (test ping from <user.email>)"`. **Confirm copy with user.**
4. **Disable webhook (clear URL) UX.** To stop delivery, the user clears the URL
   and `[update]`s. Or do we want a dedicated `[disable]` bracketed link? v1
   leans on "clear + update" for simplicity. **Confirm with user.**
5. **Rate-limit / abuse guard on test pings.** A malicious user could spam test
   pings. v1 leans on Rails' existing rack-attack throttle (one PATCH per second
   per user). **Confirm with user.**
