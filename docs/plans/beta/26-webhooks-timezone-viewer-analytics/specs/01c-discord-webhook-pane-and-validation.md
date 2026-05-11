# 01c — Discord webhook pane + validation

> Mirror of 01b for Discord. Different regex, different test-ping payload shape,
> independent row in `notification_delivery_channels` keyed on
> `kind: "discord"`. Both `discord.com` and `discordapp.com` host forms
> accepted. Can ship parallel with 01b. Implementation agent: `pito-rails`.

## Goal

Add a `discord` pane on `/settings` symmetric to 01b. Single URL input,
Discord-specific regex validation, mandatory test ping, and per-provider
`everything` + `daily_digest` booleans. Discord webhooks require a body with an
inline `content` field (Slack accepts an empty body); the test ping payload
differs accordingly. The persistence target is the same Phase 16
`notification_delivery_channels` table, with `kind: "discord"`.

## Files touched

### New

- `app/controllers/settings/webhooks/discord_controller.rb` — `update` action.
  Mirror of the Slack controller; switches the validator + client.
- `app/services/webhooks/discord_client.rb` — wraps `Net::HTTP` POST. Public
  methods: `#ping` (sends `{ content: "hi from pito" }` with the required
  `Content-Type: application/json` header; returns `Result`),
  `#deliver(payload)` (used by 01e, emits Discord embeds). Timeout: 5s.
- `app/services/webhooks/discord_url_validator.rb` — custom validator. Regex
  `\Ahttps://(discord|discordapp)\.com/api/webhooks/\d+/[A-Za-z0-9_-]+\z`.
  Accepts both `discord.com` and `discordapp.com` (Discord redirects the legacy
  form to the canonical one server-side).
- `app/views/settings/_discord_pane.html.erb` — symmetric to
  `_slack_pane.html.erb`. URL input, `[update]` submit, `[help]` link opening
  the 01d Discord modal, `everything` + `daily_digest` checkboxes. Hint text
  "Sent daily at 09:00 in your timezone."
- Specs:
  - `spec/models/notification_delivery_channel_spec.rb` — extend for the
    `discord` kind (paired with 01b's extension; one combined PR is fine).
  - `spec/services/webhooks/discord_client_spec.rb` — `#ping` happy (200, 204) +
    sad (400, 404, 401, 429, 500) + edge (timeout, DNS failure, redirect from
    discordapp.com). WebMock-driven.
  - `spec/services/webhooks/discord_url_validator_spec.rb` — happy / sad / edge:
    valid `discord.com` form, valid `discordapp.com` form, missing scheme,
    missing `/api/webhooks/`, snowflake ID not numeric, token segment with
    invalid chars, trailing slash, trailing query string, http (not https).
  - `spec/requests/settings/webhooks/discord_spec.rb` — PATCH happy / sad /
    yes-no boundary / invalid URL / failing test ping / unauthenticated / CSRF
    reject.
  - `spec/system/settings_discord_webhook_spec.rb` — critical journey: paste
    valid URL, tick `everything`, click `[update]`, see success + persisted
    state on reload.

### Edited

- `app/views/settings/index.html.erb` — render `_discord_pane`.
- `config/routes.rb` —
  `namespace :settings do; resource :discord_webhook, only: %i[update], controller: "settings/webhooks/discord" ; end`.
  URL: `PATCH /settings/discord_webhook`. Friendly URL preserved.
- `app/models/notification_delivery_channel.rb` — extend with the `for_discord`
  finder (paired with 01b). `#valid_url?` dispatches to the Discord validator
  when `kind == "discord"`.
- `config/locales/en.yml` — error messages: `invalid_discord_url`,
  `discord_ping_failed`, `discord_saved`.

### Read-only inputs

- Phase 16 `notification_delivery_channels` table.
- `app/helpers/time_zone_helper.rb` (from 01a).

## Acceptance

- [ ] Pane renders on `/settings` with state pre-filled. Empty URL + unchecked
      boxes if no `notification_delivery_channel` row for `kind: "discord"`
      exists yet.
- [ ] URL validated against the Discord regex. Both `discord.com` and
      `discordapp.com` forms accepted. Bad shapes fail before the test ping
      (422).
- [ ] Valid URL triggers the test ping with `{ content: "hi from pito" }` body.
      If ping fails (HTTP non-2xx, timeout, DNS), URL does NOT save and the form
      re-renders with the error. If ping succeeds (HTTP 2xx — Discord returns
      204 No Content on success), URL persists.
- [ ] `everything` and `daily_digest` are independent booleans. Per- provider
      state isolated from Slack's row.
- [ ] Yes / no boundary at the form payload; Boolean storage.
- [ ] One row per user for `kind: "discord"`. Update mutates; first save
      creates.
- [ ] `[help]` link opens the 01d Discord help modal.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`.
- [ ] Friendly URL preserved: `/settings/discord_webhook`.
- [ ] Spec pyramid covers: model extension, service (`DiscordClient`), validator
      (`DiscordUrlValidator`), request, system.
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/dev` running. Create a Discord webhook on a test server (follow the 01d
   Discord help modal).
2. Open `/settings`. Locate the Discord pane.
3. Paste the URL, click `[update]`. A test message "hi from pito" lands in the
   Discord channel. URL persists on reload.
4. Edit URL to the `discordapp.com` form (`https://discordapp.com/api/...`).
   Click `[update]`. Test ping succeeds; URL persists in its original form.
   (Discord-side redirect is fine; pito doesn't rewrite.)
5. Edit URL to a syntactically valid but server-side-invalid URL. Click
   `[update]`. Test ping returns 404. Form re-renders with "Discord test ping
   failed: 404." Original URL stays.
6. Tick `everything`, click `[update]`. Reload — `everything` on. Tick
   `daily digest`. Click `[update]`. Reload — both on. Untick both. Reload —
   both off.
7. DB inspect: `NotificationDeliveryChannel.where(kind: "discord").last`
   reflects the current state.

## Cross-stack scope

Identical to 01b. Webhook config is web-only for v1.

## Open questions

1. **Autosave vs `[update]`.** Same question as 01b. Confirm together.
2. **2FA gate.** Same question. Confirm.
3. **Test-ping copy.** v1: `"hi from pito (test ping from <user.email>)"`.
   **Confirm copy with user.**
4. **Disable UX.** Same as 01b — clear URL + `[update]`. Confirm.
5. **Rate-limit / abuse guard.** Same as 01b. Confirm.
6. **`username` / `avatar_url` overrides.** Discord webhooks accept per-message
   `username` and `avatar_url` overrides. v1 sends "pito" as the username and no
   avatar. **Confirm with user — or wait until 01e when the digest payload shape
   is locked.**
