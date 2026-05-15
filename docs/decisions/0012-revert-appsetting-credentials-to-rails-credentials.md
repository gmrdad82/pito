# ADR 0012 — Revert YouTube / Voyage / Google credentials from `AppSetting` back to `Rails.application.credentials`

## Status

Accepted, 2026-05-15. Supersedes ADR 0007. [skipci]

## Context

ADR 0007 (2026-05-11) moved the YouTube OAuth + API credentials from
`Rails.application.credentials.google_oauth` onto the `AppSetting` singleton row
(encrypted via Active Record Encryption), with a Settings UI form to rotate
them. The stated goals were operator hot-rotation without a deploy and storage
pattern consistency with the Voyage API key, which already lived on
`AppSetting`.

The hot-rotation promise turned out to be hollow:

- `config/initializers/omniauth.rb` reads the AppSetting columns at **boot**.
  Rotating the YouTube client id / secret through Settings still required a Puma
  restart for the new value to reach the omniauth middleware — flagged
  immediately after ADR 0007 landed as the "YouTube credentials hot-rotation
  gap" follow-up. A real hot-rotation would have required swapping omniauth
  provider config to lambda options that resolve `AppSetting` per request, a
  separate piece of work that never landed.
- The Settings UI form for credentials drifted off the project's stated
  configuration strategy. The hard rule in `CLAUDE.md` ("secrets live
  exclusively in `Rails.application.credentials`") had to be rewritten to extend
  the secret-storage surface to encrypted `AppSetting` columns. The rewrite was
  an accommodation, not a clean fit — every secret surface (YouTube, Voyage,
  Slack/Discord webhook URLs, future Discord bot tokens, IGDB client ids, etc.)
  now had two possible homes and the choice was load-bearing on rotation
  ergonomics that did not exist in practice.
- The Phase 27 settings revamp made the inconsistency worse, not better — the
  YouTube pane and the Voyage pane were the only two surfaces under `/settings`
  that edited install-wide credentials. The Slack / Discord webhook panes live
  on a different model (`NotificationDeliveryChannel`), with different rotation
  semantics (per-channel, not install-wide). Three rotation patterns, one mental
  model.
- Phase 29 Unit A1 audited the surface and discovered a latent delivery bug
  caused by the same drift — the Slack/Discord delivery gate read orphaned
  `AppSetting.slack_enabled` / `discord_enabled` columns the webhook controllers
  never wrote. Delivery had been silently dead. The fix required deriving the
  gate from the `NotificationDeliveryChannel` row directly. Once that audit ran,
  the cost of keeping a parallel-but-different storage pattern for YouTube and
  Voyage credentials was no longer worth the absent hot-rotation benefit.

## Decision

Move the YouTube OAuth + API credentials, the Voyage embedding key, and the
Google console credentials off `AppSetting` and back into
`Rails.application.credentials`. Accept the tradeoff: credentials become
deploy-time config, rotated via `bin/rails credentials:edit` + redeploy. The
hot-rotation goal that motivated ADR 0007 is withdrawn.

Concretely (Phase 29 Unit A1):

- Migration `DropCredentialColumnsFromAppSettings` removes five
  credential-bearing columns from `app_settings`: `voyage_api_key`,
  `youtube_api_key`, `youtube_client_id`, `youtube_client_secret`,
  `youtube_redirect_uri`. The same migration drops the two orphaned columns
  `slack_enabled` / `discord_enabled` that the latent-delivery-bug fix retired.
  Reversible — `remove_column` carries the original type and options.
- A second defensive data migration `ReencryptNotificationWebhookUrls` re-saves
  every `notification_delivery_channels` row through the encrypting writer.
  No-op in practice, included for safety.
- `app/models/app_setting.rb` drops every credential `encrypts` declaration,
  every `youtube_*` accessor, and `voyage_target_flags_require_key`.
  `voyage_configured?` is re-sourced from
  `Rails.application.credentials.dig(:voyage, Rails.env, :api_key)`. The
  Slack/Discord delivery gate now derives from the `NotificationDeliveryChannel`
  row (existence + present `webhook_url` + at least one routing flag).
- `config/initializers/omniauth.rb` collapses to a three-tier credentials-first
  resolver: `credentials.google_oauth` first, then `PITO_GOOGLE_OAUTH_CLIENT_ID`
  / `_CLIENT_SECRET` ENV vars for CI / local-no-DB workflows, then a test-mode
  placeholder so request specs boot without `master.key`.
- `Youtube::TokenRefresher` and `Youtube::PublicClient` read
  `credentials.google_oauth` directly.
- `Notes::EmbedJob` reads `credentials.voyage[Rails.env].api_key`.
- The Settings YouTube pane is removed entirely. The Voyage pane is slimmed to
  the non-secret `voyage_index_project_notes` indexing toggle plus the
  configured-status display block.
- `lib/tasks/youtube_credentials_backfill.rake` is deleted — the migration
  direction reversed.
- `AuthAuditLog.action` keeps `youtube_credentials_updated` as a reserved enum
  value (slot 7) for historical rows, but `Auth::AuditLogger`'s active allowlist
  drops it. `voyage_credentials_updated` (slot 8) stays in the allowlist for the
  Voyage indexing-flag write.

The credentials shape in `config/credentials.yml.enc` is:

```yaml
google_oauth:
  project_id: pito-<n>
  client_id: <client-id>.apps.googleusercontent.com
  client_secret: <client-secret>
  api_key: <api-key>
  redirect_uri: <optional>
voyage:
  development:
    api_key: <key>
  production:
    api_key: <key>
```

`google_oauth` is a flat block (not per-env) because dev and prod share the same
Google Cloud OAuth client via the Cloudflare tunnel mapping (see `docs/setup.md`
"Dev and prod share OAuth credentials"). `voyage` is per-env because the
development and production keys are different.

## Consequences

- **Configuration strategy is restored.** Secrets live exclusively in
  `Rails.application.credentials`. The hard rule in `CLAUDE.md` no longer has
  the "extends to encrypted `AppSetting` columns" carve-out. Future integration
  credentials (Slack bot tokens, Discord bot tokens, IGDB client ids, etc.)
  inherit the same single-store discipline.
- **Rotating YouTube / Voyage credentials requires a redeploy.**
  `bin/rails credentials:edit` → re-encrypt → ship. Acceptable for a
  single-install application that already follows a redeploy-to-rotate posture
  for every other secret (`tokens.pepper`, `:postgres`, Active Record Encryption
  keys).
- **The Settings UI shrinks.** One fewer credential pane (YouTube gone), one
  slimmer pane (Voyage's key field gone — only the indexing toggle remains).
  Operators discover credential config through `docs/setup.md`, not the web UI.
- **The latent Slack/Discord delivery bug is fixed in the same pass.** The
  delivery gate now derives from the `NotificationDeliveryChannel` row, which is
  what the controllers actually write. Slack/Discord notifications that silently
  dropped for the lifetime of the orphaned-`*_enabled`-columns code path now
  deliver.
- **Operators on a pre-A1 install must add credentials before boot.** The
  omniauth initializer raises at boot without `google_oauth.client_id` +
  `google_oauth.client_secret`. CI substitutes ENV vars; the test environment
  has a placeholder. Production operators run `bin/rails credentials:edit`
  during the upgrade window.
- **ADR 0007 is superseded.** A pointer at the top of 0007 references this ADR;
  the body of 0007 is left intact as historical record.

## Alternatives considered

- **Keep credentials on `AppSetting` and fix omniauth hot-rotation properly.**
  Rejected. The omniauth-per-request lambda options work was never scheduled,
  and the operator-facing benefit (rotate without redeploy) was speculative —
  the install has never rotated YouTube credentials in production. Paying the
  storage-pattern complexity cost for a benefit nobody used was the wrong trade.
- **Half-move: leave Voyage on `AppSetting`, move YouTube back.** Rejected. The
  whole point is to collapse to one storage pattern. Splitting the decision
  keeps two.
- **Move credentials to ENV.** Rejected on the same grounds ADR 0007 considered
  it. ENV is the right surface for infrastructure connection info (host / port),
  not for OAuth secrets.

## Date

2026-05-15. [skipci]

## Related

- `docs/decisions/0007-youtube-credentials-moved-to-appsetting.md` — the ADR
  this one supersedes.
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` — scopes
  Google OAuth to YouTube-only; the credentials this ADR moves back are the
  credentials that OAuth dance uses.
- `docs/plans/beta/29-screen-polish-sweep/specs/appsetting-credentials-consolidation.md`
  — the unit spec that drove the implementation.
- `docs/plans/beta/29-screen-polish-sweep/log.md` — the 2026-05-14 Unit A1 entry
  recording the landing.
- `docs/setup.md` "Configure credentials" — the operator walkthrough for the
  restored `:google_oauth` / `:voyage` blocks.
