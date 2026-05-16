# AppSetting to credentials consolidation

## Goal

Restore the project's stated configuration strategy: **secrets live exclusively
in `Rails.application.credentials`; `AppSetting` is for runtime-mutable,
non-secret config only.** Three secret-bearing surfaces drifted onto the
`AppSetting` singleton during alpha / beta-1 — the YouTube OAuth + API
credentials, the Voyage AI embedding key, and the Google console credentials
(the same `:google_oauth` block, surfaced as the YouTube pane). This unit drops
all three from `AppSetting`, points every consumer at
`Rails.application.credentials`, and removes the Settings UI panels that edit
them. It also closes follow-up 3 (the omniauth hot-rotation gap) by accepting
the tradeoff: YouTube / Google config becomes deploy-time config, no longer
hot-rotatable.

Part 4 keeps Slack + Discord webhook config DB-backed and Settings-UI-managed —
the operator must be able to paste a webhook URL and toggle "deliver every
notification" from the web UI without a deploy. Inventory confirmed these
already live on the `NotificationDeliveryChannel` model (not `AppSetting`) and
the `webhook_url` column is **already encrypted** with the same Active Record
Encryption mechanism the Voyage key uses (`encrypts :webhook_url`,
probabilistic). Part 4 also **fixes a latent delivery bug**: the orphaned
`AppSetting.slack_enabled` / `discord_enabled` gate is replaced with one derived
from the `NotificationDeliveryChannel` row itself, so Slack/Discord delivery
actually works — see "Part 4" and "The orphaned legacy path" below.

Who uses it: the operator configuring the install; every downstream service that
reads YouTube / Voyage / webhook config.

## Inventory truth (what the codebase actually holds)

### `AppSetting` — current columns (`db/schema.rb` lines 68-84)

| Column                        | Storage                                                                    | Classification                                                            |
| ----------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `key` / `value`               | plain `string` / `text`; `value` is `encrypts :value, deterministic: true` | non-secret KV (max_panes, pane_title_length, theme, monetization_enabled) |
| `voyage_api_key`              | `encrypts :voyage_api_key` (probabilistic, non-deterministic)              | **SECRET — drop (Part 2)**                                                |
| `voyage_index_project_notes`  | plain `boolean`, default false                                             | non-secret runtime flag — **keep**                                        |
| `youtube_api_key`             | `encrypts :youtube_api_key` (probabilistic)                                | **SECRET — drop (Part 1/3)**                                              |
| `youtube_client_id`           | plain `text`                                                               | **SECRET-adjacent — drop (Part 1/3)**                                     |
| `youtube_client_secret`       | `encrypts :youtube_client_secret` (probabilistic)                          | **SECRET — drop (Part 1/3)**                                              |
| `youtube_redirect_uri`        | plain `text`                                                               | **config — drop (Part 1/3)**                                              |
| `keyboard_navigation_enabled` | plain `boolean`, default true                                              | non-secret runtime flag — **keep**                                        |
| `timezone`                    | plain `string`, default "UTC"                                              | non-secret runtime flag — **keep**                                        |
| `slack_enabled`               | plain `boolean`, default false                                             | **orphaned dead column — drop (Part 4 fix)**                              |
| `discord_enabled`             | plain `boolean`, default false                                             | **orphaned dead column — drop (Part 4 fix)**                              |

The `key`/`value` rows are the original generic KV store; `max_panes`,
`pane_title_length`, `theme`, `monetization_enabled` ride `value`. The other
columns are de-facto-singleton-row attributes added later. The model is treated
as a singleton via `AppSetting.first` throughout.

### Voyage key encryption — the exact pattern to replicate (already in place for Slack/Discord)

`app/models/app_setting.rb` line 8: `encrypts :voyage_api_key` — Active Record
Encryption, **non-deterministic (probabilistic)**, no `deterministic: true`
option. Uses the install's `active_record_encryption` credentials keys
(`primary_key`, `deterministic_key`, `key_derivation_salt`). The key is never
queried or compared, so probabilistic is correct.

`app/models/notification_delivery_channel.rb` line 34: `encrypts :webhook_url` —
**identical mechanism, identical probabilistic choice.** Part 4's encryption
requirement is therefore **already satisfied**. The model header comment even
documents the rationale ("never compared, never queried"). No model change is
needed to encrypt Slack/Discord — it is done.

### Where YouTube / Google / Voyage are read today (all consumers)

| Consumer                                            | Reads                                                                                                                                                            |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config/initializers/omniauth.rb`                   | `AppSetting.youtube_client_id` / `_client_secret` / `_redirect_uri`, falling back to `Rails.application.credentials.google_oauth` then ENV then test placeholder |
| `app/services/youtube/token_refresher.rb` (l.34-37) | `AppSetting.youtube_client_id` / `_client_secret`, fallback `credentials.google_oauth`                                                                           |
| `app/services/youtube/public_client.rb` (l.83-87)   | `AppSetting.youtube_api_key`, fallback `credentials.google_oauth.api_key` then `credentials.youtube.public_api_key`                                              |
| `app/jobs/notes/embed_job.rb` (l.84-89)             | `AppSetting.first&.voyage_api_key`, fallback `credentials.voyage[env].api_key`                                                                                   |
| `app/services/search.rb`                            | **no Voyage read** (grep clean — search uses Meilisearch only; the Voyage call lives entirely in `Notes::EmbedJob`)                                              |
| `app/models/app_setting.rb` (l.63-65, 79-125)       | `voyage_configured?`, `youtube_*` accessors + `*_configured?` predicates                                                                                         |
| `app/controllers/settings_controller.rb`            | `youtube_credentials_status`, `update_youtube`, `update_voyage`, `@voyage_configured`, `@voyage_indexing_project_notes`                                          |
| `app/views/settings/index.html.erb` (l.179-352)     | YouTube edit pane + Voyage.ai edit pane                                                                                                                          |
| `db/seeds.rb` (l.24-44)                             | seeds `voyage_api_key` from `credentials.voyage[env].api_key` into AppSetting                                                                                    |
| `lib/tasks/youtube_credentials_backfill.rake`       | backfills AppSetting YouTube columns from `credentials.google_oauth`                                                                                             |
| `app/mcp/tools/manage_settings.rb`                  | **does NOT expose YouTube / Voyage** — `ALLOWED_KEYS` is `max_panes`, `pane_title_length`, `theme` only. No MCP change needed.                                   |
| `config/application.rb` (l.61-66)                   | comment only — references `voyage_configured?`; update the comment in the docs pass, no code                                                                     |

`@voyage_indexing_project_notes` (the `voyage_index_project_notes` boolean
column) is a **non-secret runtime flag and STAYS** on `AppSetting`. Only the
`voyage_api_key` secret moves. After this unit, `voyage_configured?` is
redefined to check the credentials presence instead of the column.

### Slack / Discord — where they actually live

Not `AppSetting`. The webhook URL + routing flags live on
**`NotificationDeliveryChannel`** (`notification_delivery_channels` table,
`db/schema.rb` l.600-609):

- `kind` — `slack` / `discord`, unique index (install-level singleton per kind).
- `webhook_url` — `text NOT NULL`, **`encrypts :webhook_url` (probabilistic)**.
- `everything` — `boolean` default false (this is the "deliver every
  notification" checkbox).
- `daily_digest` — `boolean` default false.
- `last_validated_at` — `datetime`, set after a successful test ping.

UI: `app/views/settings/_slack_pane.html.erb` +
`app/views/settings/_discord_pane.html.erb`, rendered from
`app/views/settings/index.html.erb` l.361-364 (integrations row 2). Controllers:
`Settings::SlackWebhooksController` + `Settings::DiscordWebhooksController`
(`PATCH /settings/slack_webhook`, `PATCH /settings/discord_webhook`). Stimulus:
`totp-modal` controller intercepts the submit when 2FA is on. The dispatchers
`app/services/notification_delivery_channel/{slack,discord}.rb` read
`NotificationDeliveryChannel.slack&.webhook_url` first, falling back to
`credentials.dig(:notifications, :*_webhook_url)`.

### The orphaned legacy path (latent bug — RESOLVED: fix it in this refactor)

`AppSetting` carries `slack_enabled` / `discord_enabled` boolean columns and
`AppSetting.slack_delivery_enabled?` / `discord_delivery_enabled?` predicates
(`app/models/app_setting.rb` l.157-175). These predicates gate on the
`*_enabled` column AND check `credentials.dig(:notifications, :*_webhook_url)`
for the URL — but the Slack/Discord webhook controllers **never write the
`*_enabled` columns**, and the dispatchers read the URL from the
`NotificationDeliveryChannel` row, not credentials. So `slack_enabled` /
`discord_enabled` are dead columns: always `false` on any real install, which
means `enabled?` in the dispatchers
(`app/services/notification_delivery_channel/ slack.rb` l.23, `discord.rb` l.22)
returns `false` and **Slack/Discord delivery is currently dead in practice**.
This is a pre-existing bug surfaced by the inventory.

**Resolution (user-confirmed): this unit fixes the bug as part of Part 4 cleanup
so Slack/Discord delivery actually works.** The fix:

- **New source of truth.** "Is Slack/Discord delivery on" is derived entirely
  from the `NotificationDeliveryChannel` row for the kind — its existence plus a
  present `webhook_url` and at least one routing flag set (`everything` or
  `daily_digest`). The orphaned `AppSetting.*_enabled` booleans are not the
  source of truth and never were; they are deleted.
- **Drop the dead columns.** `slack_enabled` / `discord_enabled` are added to
  the column-drop migration (Migration 1 — see "Migration outline").
- **Rewrite the predicates.** `AppSetting.slack_delivery_enabled?` /
  `discord_delivery_enabled?` are rewritten to return `true` iff a
  `NotificationDeliveryChannel` row exists for the kind with a present
  `webhook_url` and at least one of `everything` / `daily_digest` set. They no
  longer read the dropped column or `credentials.dig(:notifications, ...)`. The
  `notifications_credentials_value` private helper is removed.
- **Consumers.** The dispatchers' `enabled?`
  (`app/services/notification_delivery_channel/slack.rb` l.23, `discord.rb`
  l.22) keep calling the rewritten predicates — no dispatcher-logic change, but
  the predicates now return `true` on a configured install, so delivery starts
  working. No other consumer reads the dropped columns.

This is a deliberate runtime-behavior change: Slack/Discord delivery transitions
from silently-dead to working when a channel is configured. The regression specs
below prove the gate is driven by the actual channel config and that the dead
columns are gone.

## Files touched

### Part 1-3 — drop YouTube / Voyage / Google from AppSetting

- `db/migrate/<ts>_drop_credential_columns_from_app_settings.rb` — **new**.
  Drops `voyage_api_key`, `youtube_api_key`, `youtube_client_id`,
  `youtube_client_secret`, `youtube_redirect_uri`, `slack_enabled`,
  `discord_enabled` from `app_settings`. (The Slack/Discord enabled columns ride
  along here — see Part 4.)
- `app/models/app_setting.rb` — modify. Remove `encrypts :voyage_api_key`,
  `encrypts :youtube_api_key`, `encrypts :youtube_client_secret`. Remove the
  `youtube_*` class accessors + `*_configured?` predicates (l.73-125). Rewrite
  `voyage_configured?` to read credentials. Rewrite `slack_delivery_enabled?` /
  `discord_delivery_enabled?` (Part 4). Remove `voyage_target_flags_require_key`
  validation's dependency on the column — see "Migration outline" note.
- `config/initializers/omniauth.rb` — modify. Remove
  `pito_appsetting_youtube_value` helper entirely. Replace the four-tier
  resolver with a credentials-first read: `credentials.google_oauth` block, ENV
  fallback for CI, test placeholder. Update the header comment.
- `app/services/youtube/token_refresher.rb` — modify (l.34-37). Read
  `credentials.dig(:google_oauth, :client_id)` / `:client_secret` directly; drop
  the `AppSetting.youtube_*` reads.
- `app/services/youtube/public_client.rb` — modify (l.83-87). Read
  `credentials.dig(:google_oauth, :api_key)` directly; drop the
  `AppSetting.youtube_api_key` read. Keep the `:youtube, :public_api_key`
  transitional path or drop it — see Open questions Q1.
- `app/jobs/notes/embed_job.rb` — modify (l.84-89). `resolve_api_key` reads
  `credentials.dig(:voyage, Rails.env.to_sym, :api_key)` directly; drop the
  `AppSetting.first&.voyage_api_key` read.
- `app/controllers/settings_controller.rb` — modify. Remove the `youtube` branch
  from `update` (l.159-174). Remove `update_youtube`, `YOUTUBE_FIELDS`,
  `youtube_credentials_status`, `YOUTUBE_OAUTH_DEFAULT_REDIRECT_URI`,
  `@youtube_credentials`. **The `voyage` branch survives in slimmed form** (see
  "Settings UI" below): `update_voyage` keeps writing only the
  `voyage_index_project_notes` flag — its `voyage_api_key` key-write path,
  `update_appsetting_section`, and `collect_appsetting_attrs` (the key-bearing
  paths) are removed. `@voyage_configured` / `@voyage_indexing_project_notes`
  ivars are re-sourced — `@voyage_configured` from credentials presence,
  `@voyage_indexing_project_notes` from the surviving column.
- `app/views/settings/index.html.erb` — modify. Remove the YouTube edit pane
  (l.186-279). **The Voyage.ai pane is slimmed, not removed** (see "Settings UI"
  below): the API key text field + clear-checkbox are deleted; the
  `voyage_index_project_notes` toggle stays. The "Voyage embeddings" status
  block in the search pane (l.635-650) stays but re-sources `@voyage_configured`
  / `@voyage_indexing_project_notes`. The `integrations` `<h2>` and the
  remaining rows (Discord/Slack row 2, OAuth/sessions row 3) stay.
- `lib/tasks/youtube_credentials_backfill.rake` — **delete**. The backfill
  direction reverses: credentials are now the source of truth, nothing to
  backfill into AppSetting.
- `db/seeds.rb` — modify (l.24-44). Remove the Voyage AppSetting bootstrap block
  — `voyage_api_key` is no longer an AppSetting column. The
  `voyage_index_project_notes` production-flip can stay (it is a non-secret
  flag) but no longer gates on `voyage_api_key` presence; re-source the gate.
- `app/services/auth/audit_logger.rb` + `app/models/auth_audit_log.rb` — modify.
  The `youtube_credentials_updated` audit action (enum value 7 in
  `auth_audit_log.rb` l.63, allowlisted in `audit_logger.rb` l.36-44) is now
  unreachable. Keep the enum value reserved (do not renumber — enum values are
  durable) but remove it from `audit_logger.rb`'s active allowlist, or leave it
  inert. See Open questions Q2. `voyage_credentials_updated` — the Voyage _flag_
  pane survives, so a `voyage_settings_updated`-style audit row may still be
  emitted on the flag toggle; keep the audit action active for the slimmed-pane
  write path (it no longer represents a _key_ write, just a flag write).

### Settings UI — what survives, what goes

- **YouTube credentials pane — REMOVED.** `index.html.erb` l.186-279, the whole
  YouTube edit pane. The `section=youtube` hidden field and the controller's
  `youtube` `case` branch go with it. No YouTube config surface remains in the
  web UI; YouTube/Google config is deploy-time credentials only.
- **Voyage.ai pane — MODIFIED (slimmed), not removed.** The pane stays on the
  Settings index but renders **only the non-secret `voyage_index_project_notes`
  toggle**. The API key text input and the "clear key" checkbox are deleted (the
  key now lives in `Rails.application.credentials.voyage`). The operator still
  needs to turn project-notes indexing on/off at runtime, so the flag toggle
  stays Settings-UI-managed. The `section=voyage` hidden field stays — the
  slimmed pane still PATCHes the flag. The `[update]` button and the "saved."
  confirmation flash stay.
- **Slack / Discord panes — UNCHANGED rendering** (see Part 4).

### Part 4 — Slack / Discord stay DB-backed, encrypted, delivery bug fixed

- `app/models/notification_delivery_channel.rb` — **keep, no change to the
  encryption.** `encrypts :webhook_url` already in place. The only possible
  touch is the `valid_url?` / regex surface, which is out of scope here.
- `app/models/app_setting.rb` — modify (Part 4 portion). Rewrite
  `slack_delivery_enabled?` / `discord_delivery_enabled?` to return `true` iff a
  `NotificationDeliveryChannel` row exists for the kind with a present
  `webhook_url` and at least one of `everything` / `daily_digest` set. They no
  longer read the dropped `*_enabled` column or
  `credentials.dig(:notifications, ...)`. Remove the
  `notifications_credentials_value` private helper.
- `app/services/notification_delivery_channel/slack.rb` + `discord.rb` — modify
  lightly. `enabled?` keeps calling `AppSetting.slack_delivery_enabled?` /
  `discord_delivery_enabled?` (now rewritten). The `webhook_url` method's
  credentials fallback (`credentials.dig(:notifications, ...)`) can stay as a
  transitional path or be dropped — see Open questions Q3. **No change to
  delivery semantics, retry, payloads** — but note the predicates now return
  `true` on a configured install, so delivery starts working (the intended bug
  fix).
- `app/views/settings/_slack_pane.html.erb` /
  `app/views/settings/_discord_pane.html.erb` — **KEEP UNCHANGED. The
  implementer must not touch the rendered form.** The "webhook URL" text field,
  the "deliver every notification" checkbox, the "daily digest" checkbox, the
  `[update]` button, the `[help]` link, the `totp-modal` wiring, and the
  "saved." confirmation flash all stay byte-for-byte. This is called out
  explicitly because the storage layer is already correct — only the orphaned
  `AppSetting.*_enabled` gate behind it changes.
- `app/controllers/settings/slack_webhooks_controller.rb` /
  `discord_webhooks_controller.rb` — **KEEP UNCHANGED.** They already write the
  `NotificationDeliveryChannel` row correctly.
- `db/migrate/<ts>_reencrypt_notification_webhook_urls.rb` — **new, see
  "Migration outline" — likely a no-op in practice** (Slack/Discord
  `webhook_url` is already encrypted; there is no plaintext data and no
  production data). Spec it as a defensive data migration that re-saves any
  existing rows so any pre-`encrypts` plaintext value is re-encrypted. Given
  inventory shows `encrypts :webhook_url` has been in place since the column was
  created (Phase 26), this migration is purely belt-and-suspenders. See Open
  questions Q4.

### Cross-cutting

- `config/credentials.yml.enc` (edited via `bin/rails credentials:edit`) — the
  implementer populates the per-environment blocks. Not a file the implementer
  "writes" via the editor; document the expected structure (below) so the
  operator / implementer knows what keys to add.
- `.env.example` — verify no YouTube / Voyage keys leaked in; grep showed
  `AppSetting` references only in comments. No change expected; confirm.
- Spec files — see "Regression spec list".

## Credentials structure the implementer must expect

Mirror the `:postgres` block convention (per-environment nested). The
implementer adds / verifies these blocks via `bin/rails credentials:edit`:

```yaml
google_oauth:
  client_id: <YouTube OAuth client ID>
  client_secret: <YouTube OAuth client secret>
  api_key: <YouTube Data API public key>
  redirect_uri: https://app.pitomd.com/auth/google/callback   # optional

voyage:
  development:
    api_key: <Voyage AI key for development>
  test:
    api_key: <Voyage AI key for test — optional, embed job no-ops without it>
  production:
    api_key: <Voyage AI key for production>

notifications:                       # OPTIONAL — transitional fallback only
  slack_webhook_url: <legacy fallback>
  discord_webhook_url: <legacy fallback>
```

Notes:

- `google_oauth` is **not** per-environment in the current credentials file (the
  existing `Rails.application.credentials.google_oauth` block is flat) — keep it
  flat to match what `omniauth.rb`, `token_refresher.rb`, and `public_client.rb`
  already read (`credentials.dig(:google_oauth, :client_id)` etc.). If a future
  install needs per-env Google OAuth, that is a separate change. Confirm the
  flat shape during implementation; do not restructure it.
- `voyage` **is** already per-environment
  (`credentials.dig(:voyage, Rails.env.to_sym, :api_key)` — `embed_job.rb` l.88,
  `seeds.rb` l.34). Keep per-env.
- `notifications` is optional — only needed if Open questions Q3 keeps the
  credentials fallback in the Slack/Discord dispatchers' `webhook_url` method.
  The source of truth for delivery is the `NotificationDeliveryChannel` row.
- Test environment: omniauth must still boot without `master.key`. The
  initializer keeps the `Rails.env.test?` placeholder fallback for `client_id` /
  `client_secret` so request specs boot. The `voyage` test key is optional —
  `Notes::EmbedJob` already no-ops when the key is blank.

## Migration outline(s)

### Migration 1 — `DropCredentialColumnsFromAppSettings`

```
remove_column :app_settings, :voyage_api_key,        :text
remove_column :app_settings, :youtube_api_key,       :text
remove_column :app_settings, :youtube_client_id,     :text
remove_column :app_settings, :youtube_client_secret, :text
remove_column :app_settings, :youtube_redirect_uri,  :text
remove_column :app_settings, :slack_enabled,    :boolean, default: false, null: false
remove_column :app_settings, :discord_enabled, :boolean, default: false, null: false
```

- The `slack_enabled` / `discord_enabled` drops are part of the Part 4 delivery
  bug fix — once the predicates derive from `NotificationDeliveryChannel`, the
  columns are dead and must not linger.
- Reversible — the `remove_column` calls carry their original type / options so
  `down` recreates them. The recreated columns would be plaintext on rollback;
  that is acceptable (rollback is a developer escape hatch, not a production
  path; there is no production data).
- **Drop, do not just stop using.** Recommended call: there is no production
  data and the columns are secrets / dead flags that should not linger in the
  schema. A dropped column also forces every consumer to be updated (a leftover
  read fails loudly in CI rather than silently returning a stale value).
- Order: this migration must land in the same commit as the model + consumer
  changes. If the column is dropped while a consumer still reads
  `AppSetting.youtube_client_id`, the app raises `NoMethodError` at boot — the
  regression specs (below) catch this.
- The `voyage_target_flags_require_key` validation in `AppSetting` references
  `voyage_api_key`. After the column drop, that method must be removed or
  rewritten — the "flag true requires key present" invariant now checks
  credentials presence, or is dropped entirely. The migration spec does not
  cover this; the model spec does.

### Migration 2 — `ReencryptNotificationWebhookUrls` (defensive, likely no-op)

```
NotificationDeliveryChannel.reset_column_information
NotificationDeliveryChannel.find_each do |channel|
  channel.save!(validate: false)   # re-write forces ARE re-encryption
end
```

- Wrapped so it is safe on an empty table (the realistic case — no production
  data).
- Rationale: if any row were ever written before `encrypts :webhook_url` was
  added, this re-saves it through the encrypting writer. Inventory shows
  `encrypts` has been present since the column's creation migration, so this is
  purely belt-and-suspenders — but the regression mandate wants the migration
  specced correctly regardless. See Open questions Q4 — the architect's
  defensible call is to **include this migration** for correctness even though
  it is expected to do nothing; it costs nothing and documents intent.
- `data` migration — no schema change. `disable_ddl_transaction!` not needed (no
  index ops).

## Acceptance

- [ ] `app_settings` no longer has `voyage_api_key`, `youtube_api_key`,
      `youtube_client_id`, `youtube_client_secret`, `youtube_redirect_uri`,
      `slack_enabled`, `discord_enabled` columns (schema.rb reflects the drop).
- [ ] `AppSetting` no longer declares `encrypts :voyage_api_key`,
      `encrypts :youtube_api_key`, `encrypts :youtube_client_secret`; the
      `youtube_*` class accessors and `*_configured?` predicates are gone.
- [ ] `config/initializers/omniauth.rb` resolves Google OAuth config from
      `Rails.application.credentials.google_oauth` (then ENV, then the test
      placeholder) with no `AppSetting` read; `pito_appsetting_youtube_value` is
      removed.
- [ ] `Youtube::TokenRefresher` and `Youtube::PublicClient` read Google config
      from credentials only — no `AppSetting.youtube_*` calls remain.
- [ ] `Notes::EmbedJob#resolve_api_key` reads
      `credentials.dig(:voyage, env, :api_key)` only — no
      `AppSetting...voyage_api_key` read remains.
- [ ] The Settings index no longer renders the YouTube credentials pane; the
      Voyage.ai pane is slimmed to render **only** the
      `voyage_index_project_notes` toggle — no `settings[voyage_api_key]` input
      and no key-clear checkbox remain.
- [ ] `SettingsController` has no `youtube` update branch, no
      `youtube_credentials_status`, no `update_youtube` / `YOUTUBE_FIELDS`. The
      `voyage` update branch writes only the `voyage_index_project_notes` flag —
      no `voyage_api_key` write path remains.
- [ ] `lib/tasks/youtube_credentials_backfill.rake` is deleted; `db/seeds.rb` no
      longer bootstraps `voyage_api_key` onto `AppSetting`.
- [ ] `NotificationDeliveryChannel#webhook_url` is encrypted at rest via Active
      Record Encryption (probabilistic) — verified by a round-trip model spec.
      No view / controller / Stimulus change to the Slack or Discord panes.
- [ ] `AppSetting.slack_delivery_enabled?` / `discord_delivery_enabled?` derive
      from the `NotificationDeliveryChannel` row for the kind (present
      `webhook_url` + at least one routing flag) — not the dropped `*_enabled`
      column. With a configured channel they return `true` and delivery works;
      with no channel they return `false`.
- [ ] The Slack and Discord settings panes render identically to before (URL
      text field + "deliver every notification" checkbox + "daily digest"
      checkbox + `[update]` + `[help]`) and still save with the "... webhook
      saved." confirmation.
- [ ] omniauth still configures the `google_oauth2` strategy at boot — verified
      by an initializer / boot spec.
- [ ] Full RSpec suite green; `rubocop` clean.
- [ ] `docs/` impact flagged for a docs pass (not edited by this unit) — see
      "docs impact".

## Regression spec list (per the lane mandate)

Additive, never substitutive. Enumerated by layer:

### Model specs

- `spec/models/app_setting_spec.rb` — modify. Assert the model no longer
  responds to `youtube_client_id` / `youtube_client_secret` / `youtube_api_key`
  / `youtube_redirect_uri` (class accessors gone) and that `app_settings` has no
  `voyage_api_key` / `youtube_*` / `slack_enabled` / `discord_enabled` columns
  (`AppSetting.column_names` excludes all seven — this is the
  **dead-columns-are-gone regression spec**). Assert `voyage_configured?`
  reflects the credentials presence (stub `Rails.application.credentials`).
  Assert `slack_delivery_enabled?` / `discord_delivery_enabled?` are gated on
  the actual `NotificationDeliveryChannel` config: false with no channel row;
  false with a channel row that has a blank `webhook_url` or no routing flag
  set; **true** with a channel row that has a present `webhook_url` and
  `everything` (or `daily_digest`) set. Prove the predicate does NOT read any
  `AppSetting` column (the columns are gone, so a read would raise — but assert
  the positive path explicitly).
- `spec/models/notification_delivery_channel_spec.rb` — add. **Encryption
  round-trip**: create a row with a `webhook_url`, reload, assert the decrypted
  value matches; assert the raw ciphertext column
  (`NotificationDeliveryChannel.connection.select_value` against the row) is not
  the plaintext. Assert two rows with the same `webhook_url` produce different
  ciphertext (probabilistic, not deterministic).

### Migration specs

- `spec/migrations/drop_credential_columns_from_app_settings_spec.rb` — add.
  Assert the seven columns are absent post-migration; assert `down` restores
  them (reversibility).
- `spec/migrations/reencrypt_notification_webhook_urls_spec.rb` — add. Assert
  the migration runs cleanly on an empty table and on a table with one row,
  leaving the decrypted `webhook_url` intact.

### Request specs

- `spec/requests/settings_spec.rb` — modify. Assert `GET /settings` no longer
  renders the YouTube pane (no "YouTube" `<h2>` in the integrations area, no
  `settings[youtube_client_id]` input) and that the Voyage pane renders the
  `voyage_index_project_notes` toggle but **no** `settings[voyage_api_key]`
  input and no key-clear checkbox. Assert `PATCH /settings` with
  `section=youtube` no longer routes a YouTube write (falls through to legacy
  no-op, redirects with the standard notice — does not 500). Assert
  `PATCH /settings` with `section=voyage` still toggles
  `voyage_index_project_notes` and never touches a key. Assert the Slack and
  Discord panes still render with the webhook URL field + "deliver every
  notification" checkbox.
- `spec/requests/settings/slack_webhook_spec.rb` (or the existing slack/discord
  request specs) — verify still green AND extend:
  `PATCH /settings/slack_webhook` with a valid URL + a stubbed 2xx ping persists
  a `NotificationDeliveryChannel` row and redirects with "Slack webhook saved."
  After that PATCH, assert `AppSetting.slack_delivery_enabled?` is `true` — i.e.
  the delivery gate flips on as a direct consequence of the channel config (the
  bug-fix regression at the request layer). Same for Discord.
- `spec/initializers/omniauth_spec.rb` — modify. Drop the "AppSetting accessor
  surface" describe block and the `pito_appsetting_youtube_value` rescue specs
  (the helper is gone). Keep / adapt "boot-time provider configuration" — the
  `google_oauth2` strategy is registered at boot. Add a focused spec asserting
  the resolver reads `credentials.google_oauth` (stub the credentials block,
  assert the strategy's `options` carry the stubbed `client_id`). This doubles
  as the **initializer / boot smoke check** the prompt mandates.

### System specs

- `spec/system/settings_webhooks_spec.rb` (or extend an existing settings system
  spec) — add / modify. Capybara + JS driver: visit `/settings`, confirm the
  Slack pane shows the "webhook URL" field and the "deliver every notification"
  checkbox; fill the URL, submit, confirm the "Slack webhook saved." flash (stub
  the test ping at the HTTP boundary). Same for Discord. Assert the YouTube pane
  is **absent** from the page and the Voyage pane shows only the indexing toggle
  (no key field).
- `spec/system/settings_spec.rb` — modify if it currently exercises the YouTube
  pane or the Voyage _key_ field; remove those interactions, assert the YouTube
  pane is gone and the Voyage pane is the slimmed toggle-only form.

### Job spec

- `spec/jobs/notes/embed_job_spec.rb` — modify. Where it previously stubbed
  `AppSetting.first.voyage_api_key`, stub `Rails.application.credentials` / the
  `:voyage` block instead. Assert `resolve_api_key` reads credentials and the
  job still no-ops cleanly when the key is blank.

## Removed inbound references checklist

Every link / partial / helper / wire path that points at the removed Settings
panels — verify each is gone or inert after the change:

- [ ] `app/views/settings/index.html.erb` — the YouTube edit pane removed; the
      Voyage.ai pane slimmed (key field + clear-checkbox gone, toggle kept); no
      dangling `render` or ivar reference.
- [ ] `@youtube_credentials` ivar — removed from `SettingsController#index` and
      from the view.
- [ ] `@voyage_configured` / `@voyage_indexing_project_notes` — re-sourced
      (`@voyage_configured` from credentials presence,
      `@voyage_indexing_project_notes` from the surviving column; the "Voyage
      embeddings" status block in the search pane and the slimmed Voyage pane
      both still use them).
- [ ] `section=youtube` hidden field — removed from the view; the controller's
      `youtube` `case` branch removed.
- [ ] `section=voyage` hidden field — **kept**: the slimmed Voyage pane still
      PATCHes the `voyage_index_project_notes` flag through it.
- [ ] `settings_path` `PATCH` with `section=youtube` — no longer a documented
      path; legacy callers fall through to `update_legacy` (no-op, no 500).
- [ ] `lib/tasks/youtube_credentials_backfill.rake` — deleted; grep for
      `pito:backfill_youtube_credentials` across `docs/` and orchestration
      playbooks returns only historical references (leave those, they are
      append-only logs).
- [ ] `youtube_credentials_updated` audit action — removed from
      `Auth::AuditLogger`'s active allowlist; enum value left reserved in
      `AuthAuditLog` (not renumbered). The `voyage` audit action stays active
      for the slimmed-pane flag write. Confirm no view renders a
      YouTube-credentials action label for new rows.
- [ ] No `[help]` link, nav entry, or Settings sub-page links to a YouTube
      credentials surface — grep `youtube` across `app/views/` confirms only the
      search-pane status block remains; grep `voyage` confirms only the
      search-pane status block and the slimmed flag pane remain.
- [ ] `config/initializers/omniauth.rb` raise message — update the operator hint
      string (currently tells the operator to "populate the YouTube fields on
      the AppSetting singleton (Settings -> YouTube -> [update])"); the new
      message points only at `bin/rails credentials:edit` + the ENV vars.

## docs impact (flag for a docs pass — do NOT edit in this unit)

- `CLAUDE.md` — "Configuration strategy" section: the `AppSetting` table line
  currently lists `max_panes`, `pane_title_length`, theme; it is already correct
  in spirit (no secrets) but the realignment note and follow-ups need updating.
  The "Architecture notes" + "Active follow-ups" need:
  - Follow-up 3 (omniauth hot-rotation gap) — **closed** by this unit. The gap
    is resolved by removing hot rotation entirely: Google OAuth config is
    deploy-time credentials config now.
  - Follow-up 9 (Voyage AppSetting revamp / Meilisearch indexing parity) — the
    "Voyage AppSetting revamp" half is resolved; the key is back in credentials,
    the `voyage_index_project_notes` flag stays on a slimmed Settings pane.
- `docs/decisions/0007-youtube-credentials-moved-to-appsetting.md` — this ADR is
  now **reversed**. A new ADR (or an addendum) should record the reversal: the
  one-way trip of credentials onto `AppSetting` was a configuration-strategy
  violation; this unit restores the stated strategy. The architect should author
  this ADR alongside the unit (per `CLAUDE.md`'s ADR criteria — a structural
  commitment / reversal of a prior ADR).
- `docs/setup.md` — if it documents setting YouTube / Voyage via the Settings
  UI, update to point at `credentials:edit` for the keys; the Voyage
  project-notes indexing toggle stays a Settings-UI control.
- `docs/architecture.md` — if it references the `AppSetting` credential columns.
- `config/application.rb` l.61-66 comment — references `voyage_configured?` as
  "DB-backed so the Settings UI flips it at runtime"; the key half is no longer
  DB-backed (the `voyage_index_project_notes` flag still is). Comment-only fix,
  fold into the docs pass or the impl.

## Cross-stack scope

- **MCP** — skipped / no-op. `manage_settings`
  (`app/mcp/tools/ manage_settings.rb`) never exposed YouTube / Voyage / webhook
  config — `ALLOWED_KEYS` is `max_panes` / `pane_title_length` / `theme` only.
  No MCP change. (MCP is paused per the roadmap regardless.)
- **CLI / TUI (`pito` Rust binary)** — skipped. The CLI's `AppSettings` struct
  binds to `max_panes` / `pane_title_length` / `theme` from
  `SettingsController#settings_json`, which is unchanged. No wire-format change.
  (CLI is paused per the roadmap.)
- **Cloudflare website** — not in scope.

No deferred cross-surface items: the dropped columns were never on any non-web
wire contract.

## Open questions

1. **`Youtube::PublicClient` transitional `:youtube, :public_api_key` path.**
   `public_client.rb` l.86 reads a third fallback
   `credentials.dig(:youtube, :public_api_key)` that the inline comment says no
   install ever used. Defensible call: drop it — dead path, and this unit is the
   cleanup moment. Flagging only so the master agent can veto if there is an
   unknown install.
2. **`youtube_credentials_updated` audit enum value.** Enum value 7 in
   `AuthAuditLog`. Defensible call: leave the enum value reserved (do not
   renumber — enum values are durable), just remove it from
   `Auth::AuditLogger`'s active allowlist so nothing emits it. No open question
   if the master agent agrees with "reserve, do not renumber."
3. **Keep the `credentials.notifications.*_webhook_url` fallback in the
   Slack/Discord dispatchers' `webhook_url` method?** The dispatchers read the
   `NotificationDeliveryChannel` row first, credentials second. Defensible call:
   keep the credentials fallback — it is harmless and matches the documented
   "legacy installs that wired the URL through credentials" path. Note this is
   the dispatcher's `webhook_url` _value_ lookup only; the delivery _gate_ is
   now driven solely by the `NotificationDeliveryChannel` row (see Part 4). No
   change needed; flagging only for completeness.
4. **Migration 2 (re-encrypt webhook URLs) — include it given it is a no-op?**
   Inventory confirms `encrypts :webhook_url` has been present since the
   column's creation, so there is no plaintext data to re-encrypt and no
   production data at all. Defensible call: include the migration anyway — the
   regression mandate wants it specced, it costs nothing, and it documents the
   "webhook URLs are encrypted at rest" invariant for any future reader. The
   master agent can drop it if it prefers a leaner changeset.
