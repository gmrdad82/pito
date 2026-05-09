# Phase 7 — Google OAuth + YouTube API Foundation · Dropped

> Items removed from this phase's scope by the 2026-05-09 realignment. See
> `docs/realignment-2026-05-09.md` and
> `docs/decisions/0003-drop-tenant-single-install-multi-user.md`.

## 2026-05-09 — Tenant column drops

### `google_identities.tenant_id`

Phase 7's plan included `tenant_id` as a denormalized column on
`google_identities` for default-scoping consistency with the rest of the schema.
ADR 0003 drops tenant scoping entirely. The column drops in the same migration
sweep that removes `tenant_id` from every other domain table.

`GoogleIdentity` continues to belong to `User`. The `Current.user` context
resolves the identity in the OAuth flow; `Current.tenant` goes away.

### `youtube_api_calls.tenant_id`

Same treatment. The audit table currently keys by
`(tenant_id, user_id, google_identity_id)`. After the drop, it keys by
`(user_id, google_identity_id)`. The "how much quota did this identity burn
today" calculation in `Youtube::Client` already runs against
`google_identity_id`; nothing in the quota logic depends on `tenant_id`.

### `belongs_to_tenant` on Phase 7 models

`GoogleIdentity` no longer includes `BelongsToTenant`. The concern goes away
entirely per ADR 0003.

## What stays

The Phase 7 plan's substantive work is unchanged:

- Google Cloud project setup (consent screen, OAuth web client, redirect URI
  `https://app.pitomd.com/auth/google/callback`)
- `GoogleIdentity` model with encrypted access / refresh tokens via Active
  Record Encryption (`encrypts :access_token, :refresh_token`)
- The `needs_reauth` flag + Settings banner
- The OAuth authorization-code flow at `/auth/google/*`
- `Youtube::Client` + `Youtube::PublicClient`
- The quota chokepoint inside the client tier
- The `youtube_api_calls` audit table (just minus the `tenant_id` column)
- Per-environment Rails credentials under
  `Rails.application.credentials.google_oauth`

## Cross-references

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/realignment-2026-05-09.md`
- `additions.md` in this phase folder for downstream expansion.
