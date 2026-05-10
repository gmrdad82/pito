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

## 2026-05-10 — Sign-in-with-Google retired; `GoogleIdentity` renamed

Phase 9 (`docs/plans/beta/09-login-with-google-drop/`) executed ADR 0006 and
retired the dormant sign-in-with-Google branch outright, narrowing Google OAuth
to YouTube channel connection only. The Phase 7 model was renamed in the same
dispatch.

- **Item:** the dormant sign-in-with-Google branch in
  `Auth::GoogleCallbacksController#create` (the `TODO(phase-12)` placeholder
  that redirected to root when the OAuth callback arrived without the
  `youtube_connect` intent in session). Removed entirely; any callback without
  the connect intent now redirects to the failure path with the locked
  stale-intent flash.
- **Rationale:** ADR 0006 — pito is single-install + multi-user (ADR 0003) with
  local-password auth as the canonical login path (Phase 6A → Phase 8). A second
  identity provider buys nothing for the install operator. Google OAuth remains
  as the channel-connection grant only.
- **Plan link:** the Phase 7 plan's "Phase 12 sign-in" stub is moot. The
  callback controller is now `YoutubeConnections::OauthCallbacksController` and
  exists exclusively to mint / refresh `YoutubeConnection` rows.
- **Driver:**
  `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`.

- **Item:** the dev-only `/auth/google` redirect (registered behind
  `if Rails.env.development?` in `config/routes.rb`).
- **Rationale:** the address-bar shortcut existed solely to make the
  sign-in-with-Google dance testable in development. With sign-in retired the
  shortcut has no purpose; the channel-connect flow goes through Settings →
  YouTube. Development GETs to `/auth/google` now 404.
- **Plan link:** Phase 7's routes plan; superseded by Phase 9.
- **Driver:** ADR 0006 + the Phase 9 spec.

- **Item:** the `GoogleIdentity` model name (table `google_identities`, FK
  columns `oauth_identity_id` on `channels`/`videos`, `google_identity_id` on
  `youtube_api_calls`, factory `:google_identity`, every reference site).
- **Rationale:** with sign-in dropped the model's only role is "an OAuth grant
  that gives pito access to one or more YouTube channels." The `Identity`
  framing encoded the dual user-identity-AND-API-grant role that ADR 0006
  retired. Renamed to `YoutubeConnection` (table `youtube_connections`, FK
  column `youtube_connection_id` everywhere, factory `:youtube_connection`).
- **Plan link:** Phase 7's "GoogleIdentity model" section in the plan; the
  underlying schema and behaviour survive verbatim under the new name.
- **Driver:** ADR 0006 + Phase 9 spec §"Resolved design decisions" Q2.

## Cross-references

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
- `docs/realignment-2026-05-09.md`
- `additions.md` in this phase folder for downstream expansion.
