# Phase 7 — Step 7A — Google OAuth Sign-In and `GoogleIdentity`

> First of three Phase 7 specs. Lands the OAuth plumbing and the encrypted
> identity record before any YouTube API call is made. Sibling specs:
> `7b-youtube-client-and-audit.md`, `7c-settings-youtube-ui.md`. Locked
> decisions are pinned exactly — do not reinvent.

---

## Goal

Wire up the OmniAuth-based Google OAuth flow so a Pito `User` (Phase 5) can
authorize the app against their Google account and have the resulting tokens
persisted as an encrypted `GoogleIdentity` row. This step delivers the OAuth
round-trip, the `GoogleIdentity` model + migration, the callback controller, the
routes, and the credentials wiring. **It does not call the YouTube API** (7B)
and **does not render any Settings UI** (7C). The sole user-visible surface here
is the redirect chain `/auth/google → Google → callback → redirect target`.

This spec also reserves — but does not light up — the dedicated **sign-in**
entry point that Phase 12 (Auth UI) will surface. Phase 7 only needs the
**connection** entry point (used by 7C); the sign-in route exists as a thin
wrapper requesting only userinfo scopes, so Phase 12 inherits a working flow.
For Phase 7 itself, the sign-in callback path leaves a TODO and redirects to
`root_path` — real session establishment is Phase 12 work.

## Files touched

Rails (Lane 1):

- `Gemfile` — add `omniauth-google-oauth2`, `omniauth-rails_csrf_protection`.
- `config/initializers/omniauth.rb` — register the Google provider, point at
  Rails credentials, configure state + PKCE.
- `config/routes.rb` — `/auth/google`, `/auth/google/callback`, `/auth/failure`,
  `/settings/youtube/connect` (redirector that re-enters OmniAuth with the
  YouTube scope set).
- `app/controllers/auth/google_callbacks_controller.rb` — callback handling,
  identity upsert, redirect dispatch.
- `app/controllers/concerns/google_oauth_redirect.rb` — small helper to compute
  return-to paths between the sign-in flow and the connect flow.
- `app/models/google_identity.rb` — model with encrypted token columns,
  associations, expiry helpers.
- `db/migrate/<ts>_create_google_identities.rb` — table per §"Schema".
- `config/credentials/development.yml.enc`, `config/credentials/test.yml.enc`,
  `config/credentials/production.yml.enc` — `:google` block per §"Credentials".
- `.env.example` — note that no env var lives here for OAuth (credentials only);
  document the redirect URI registered with Google.
- `spec/factories/google_identities.rb`
- `spec/models/google_identity_spec.rb`
- `spec/requests/auth/google_callbacks_spec.rb`
- `spec/system/google_oauth_flow_spec.rb` (with OmniAuth test mode)

Documentation (parallel docs-keeper dispatch — out of this spec's lane):

- `docs/setup.md` — Google Cloud project bootstrap steps for fresh installs.
  **Manual one-shot setup**, click-by-click instructions captured for
  repeatability. Sole user (single-tenant Beta); automation revisits if/when a
  team scales.
- `docs/architecture.md` — "Google OAuth" subsection wired into the auth map.

Cross-stack scope: Rails-only.

## Schema

`google_identities` — one row per (User, Google account) pair.

| Column                 | Type     | Constraints                                            |
| ---------------------- | -------- | ------------------------------------------------------ |
| id                     | bigint   | pk                                                     |
| tenant_id              | bigint   | not null, fk → tenants, default-scoped via `Current`   |
| user_id                | bigint   | not null, fk → users                                   |
| google_subject_id      | string   | not null, unique within (tenant_id)                    |
| email                  | citext   | not null                                               |
| access_token           | text     | not null, encrypted (Active Record Encryption)         |
| refresh_token          | text     | nullable, encrypted (Google may omit on re-grant)      |
| expires_at             | datetime | not null                                               |
| scopes                 | jsonb    | not null, default `[]`, array of granted scope strings |
| needs_reauth           | boolean  | not null, default `false`                              |
| last_refreshed_at      | datetime | nullable                                               |
| last_authorized_at     | datetime | not null (set on every successful callback)            |
| created_at, updated_at | datetime | not null                                               |

Indexes:

- `(tenant_id, google_subject_id)` unique.
- `(tenant_id, user_id)` non-unique (the schema permits N identities per user to
  keep options open for Theta; the Beta UI in 7C enforces 1).
- `(tenant_id, needs_reauth)` partial where `needs_reauth = true` — fast lookup
  for the "needs reauth" banner check in 7C.

Encryption:

- `encrypts :access_token`
- `encrypts :refresh_token`
- Deterministic encryption is **not** used; tokens are not searchable.
- Active Record Encryption keys live in Rails credentials per environment; reuse
  the keys established in Phase 5 / earlier. Do **not** generate a new key for
  this phase.

Validation:

- `google_subject_id`, `email`, `access_token`, `expires_at` presence.
- `scopes` must be an Array (validate type, not contents — the contents come
  from Google).

Helpers on `GoogleIdentity`:

- `access_token_expired?(skew: 60.seconds)` → returns true when
  `expires_at <= Time.current + skew`.
- `needs_reauth?` → returns the column directly. Used by 7C banner.
- `has_scope?(scope)` → membership in `scopes`.
- `scope_string` → `scopes.join(" ")` (the format Google's authorization
  endpoint expects).

## OAuth scopes

Two scope sets are configured. The flow that triggers OmniAuth picks one set in
the request phase via the `scope:` option.

**Sign-in scope set** (Phase 12 surfaces; Phase 7 just wires the route):

- `openid`
- `email`
- `profile`

**YouTube connection scope set** (Phase 7 surfaces via 7C):

- `openid`
- `email`
- `profile`
- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/yt-analytics.readonly`

**Locked decision — Beta YouTube scopes are read-only.** The YouTube connection
flow requests `youtube.readonly` and `yt-analytics.readonly` ONLY. No write
scope (`youtube`, `youtube.upload`) in Phase 7. Write scopes are reserved for
the phase that actually needs them (Phase 10 — Video Workflow Features); the
re-consent screen at that point is acceptable cost.

`access_type: "offline"` and `prompt: "consent"` are passed on every
authorization request. **Locked decision — `prompt: "consent"` always.** This
guarantees Google returns a refresh token on every reconnect, even if the user
previously granted offline access. The cost is one extra consent screen on
re-auth; the benefit is deterministic refresh-token semantics (no "Google
sometimes omits the refresh token" branch in `TokenRefresher`).

## Routes

```
GET  /auth/google                   → OmniAuth request phase, sign-in scopes
GET  /auth/google/callback          → callback controller (handles BOTH flows)
GET  /auth/failure                  → omniauth-rails_csrf_protection failure page
GET  /settings/youtube/connect      → redirects into OmniAuth with YouTube scopes
                                       via session-stashed state
```

The connect flow is implemented as a small Rails action (not an OmniAuth
provider variant): it stores `session[:google_oauth_intent] = "youtube_connect"`
and redirects to OmniAuth's request phase with `scope: <youtube scope set>`. The
callback controller dispatches on the stashed intent.

`POST /auth/google` is also exposed because `omniauth-rails_csrf_protection`
requires POST for the request phase from inside the app. The "Connect Google
account" button in 7C uses a `button_to` (POST) → 302 → Google. The bare
`GET /auth/google` is allowed for direct address-bar entry during dev, gated
behind `Rails.env.development?` (do not expose in production — this is the
csrf-protection bypass the gem warns about).

## Callback controller

`Auth::GoogleCallbacksController#create` (mounted at `/auth/google/callback`).

Flow:

1. Read `request.env["omniauth.auth"]` (the OmniAuth auth hash).
2. Read `session.delete(:google_oauth_intent)` → `"youtube_connect"` or `nil`
   (default sign-in flow).
3. Find or create `GoogleIdentity` keyed on `(tenant_id, google_subject_id)`:
   - On **create**: scope to `Current.user` (Phase 5 sets this; if for some
     reason `Current.user` is nil, redirect to `/` with a flash error).
   - On **update**: refresh `access_token`, `refresh_token` (Google returns one
     on every reconnect because we force `prompt: "consent"`), `expires_at`,
     `scopes` (union with existing), `last_authorized_at`, set
     `needs_reauth: false`.
4. Dispatch by intent:
   - `"youtube_connect"` → redirect to `/settings/youtube` (7C lights this up).
   - `nil` (sign-in) → **placeholder for Phase 7**: leave a TODO comment at the
     dispatch and redirect to `root_path`. Real session establishment lands in
     Phase 12. A passing spec asserts the redirect target is `root_path` and a
     TODO marker exists in the source.
5. On `request.env["omniauth.auth"]` missing or `omniauth.error` present:
   redirect to `/auth/failure` with a flash describing the failure
   (`access_denied`, `invalid_credentials`, `timeout`, etc.).

CSRF: OmniAuth's state parameter is enabled (default in
`omniauth-google-oauth2 >= 1.0`). The controller does **not** bypass
`protect_from_forgery`; the callback is a GET, and OmniAuth handles state
verification before the controller runs.

## Credentials

`bin/rails credentials:edit --environment <env>` — add a `:google` block per
environment:

```yaml
google:
  client_id: "<google web client id>.apps.googleusercontent.com"
  client_secret: "<google web client secret>"
  redirect_uri: "https://app.pitomd.com/auth/google/callback"
```

Production and development share the redirect URI because the Cloudflare tunnel
exposes the local Web Puma at `app.pitomd.com` (per the Phase 7 plan). The test
environment uses OmniAuth's test mode and never reaches Google — credentials can
be placeholder strings (`"test-client-id"`, `"test-client-secret"`).

## Acceptance

- [ ] `omniauth-google-oauth2` and `omniauth-rails_csrf_protection` added to
      Gemfile; `bundle install` succeeds.
- [ ] Migration creates `google_identities` with all columns, types, indexes,
      and encryption per §"Schema".
- [ ] `GoogleIdentity` model has the four helpers (`access_token_expired?`,
      `needs_reauth?`, `has_scope?`, `scope_string`) covered by specs.
- [ ] `encrypts :access_token` and `encrypts :refresh_token` are in place; a
      model spec asserts that
      `GoogleIdentity.last.access_token_before_type_cast` (raw column read) is
      **not** equal to the plaintext value passed in.
- [ ] Routes per §"Routes" exist; `bin/rails routes | grep google` shows them.
- [ ] `:google` credentials block exists in development, test, production
      encrypted credentials files (test values may be placeholders).
- [ ] Callback creates a new `GoogleIdentity` on first authorization (request
      spec with OmniAuth test mode).
- [ ] Callback updates an existing `GoogleIdentity` on re-authorization; because
      `prompt: "consent"` is forced, the refresh token is always present in the
      auth hash and is rewritten on every reconnect.
- [ ] Callback unions newly granted scopes into the `scopes` jsonb array rather
      than replacing.
- [ ] Callback resets `needs_reauth: false` on a successful re-authorization.
- [ ] Callback redirects to `/settings/youtube` when the intent stash is
      `"youtube_connect"`.
- [ ] Callback redirects to `root_path` when the intent stash is nil (sign-in
      flow); a TODO marker is present in the controller pointing at Phase 12
      session establishment.
- [ ] Callback redirects to `/auth/failure` with a flash on `omniauth.error`
      set.
- [ ] State parameter validation is on (test by spoofing a mismatched state and
      asserting OmniAuth rejects).
- [ ] Tenant-scoping spec: a `GoogleIdentity` created under tenant A is not
      visible to a `Current.tenant = B` query.
- [ ] System spec drives the full flow in OmniAuth test mode end-to-end: click
      `[ connect google ]` (rendered by 7C — for this spec, point at a stub
      button) → mocked Google response → identity persisted → redirect.
- [ ] No JS `alert` / `confirm` / `prompt` introduced (it shouldn't be — OAuth
      is server redirects).
- [ ] Brakeman clean (especially: callback CSRF, open redirect on
      `session[:return_to]`).

## Manual test recipe

Prereq: the user has completed the Google Cloud setup checklist documented in
`docs/setup.md`. This is a manual one-shot the user runs once during initial
project bootstrap; the steps live in the doc for repeatability.

1. `bin/rails credentials:edit --environment development` — add the `:google`
   block with the real client id / secret. Save.
2. `bin/dev` — Web Puma + Sidekiq + Tailwind start.
3. From the Cloudflare tunnel host: visit `https://app.pitomd.com/auth/google`
   (dev-only direct GET — see §"Routes"). The browser bounces to Google's
   consent screen.
4. Approve. Browser returns to `https://app.pitomd.com/auth/google/callback`,
   which redirects to `/` (the placeholder sign-in target until Phase 12 lights
   up real session establishment).
5. `bin/rails console` — confirm:

   ```ruby
   GoogleIdentity.last.email           # the user's google email
   GoogleIdentity.last.scopes          # ["openid", "email", "profile"]
   GoogleIdentity.last.expires_at      # ~ 1 hour from now
   GoogleIdentity.last.read_attribute_before_type_cast(:access_token)
   # encrypted blob, NOT the plaintext access token
   ```

6. Visit `https://app.pitomd.com/settings/youtube/connect` — bounces back to
   Google. Approve YouTube scopes. Returns to `/settings/youtube` (7C surfaces a
   "not implemented" placeholder page in this spec; 7C makes it real).
7. `bin/rails console`:

   ```ruby
   GoogleIdentity.last.scopes
   # ["openid", "email", "profile",
   #  "https://www.googleapis.com/auth/youtube.readonly",
   #  "https://www.googleapis.com/auth/yt-analytics.readonly"]
   ```

8. Connect to psql; verify `SELECT access_token FROM google_identities` shows
   ciphertext, not the plaintext bearer token.
9. `bundle exec rspec spec/models/google_identity_spec.rb spec/requests/auth/google_callbacks_spec.rb spec/system/google_oauth_flow_spec.rb`
   — all green.

Teardown: `GoogleIdentity.destroy_all` in console (real disconnect-with-revoke
is a 7C concern). Manually revoke the grant from
https://myaccount.google.com/permissions if you want to re-test from scratch.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI (`extras/cli/`) — **skipped.** The CLI does not need a Google
  identity in Phase 7. When Phase 8 (Data Sync) lands, the CLI may surface sync
  state, but no OAuth flow runs through the CLI itself.
- MCP — **skipped.** No `yt:*` MCP tools call Google in Phase 7. (Phase 8
  introduces sync tools that consume `GoogleIdentity` server-side.)
- Cloudflare Pages website — **skipped.** OAuth happens entirely on
  `app.pitomd.com`.

## Decisions (locked)

The following decisions are confirmed and pinned. Implementation does not
re-litigate them.

- **OAuth scopes for Phase 7** — `youtube.readonly` and `yt-analytics.readonly`
  ONLY (plus the userinfo scopes `openid email profile`). NO write scope
  (`youtube`, `youtube.upload`) in Phase 7. Write scopes land in Phase 10 (Video
  Workflow Features). The re-consent screen at that point is the accepted cost.
- **Refresh-token re-grant policy** — `prompt: "consent"` is passed on EVERY
  authorization request. This guarantees Google returns a refresh token on every
  reconnect, eliminating the "Google sometimes omits the refresh token" branch
  in `TokenRefresher`. The cost is one extra consent screen on re-auth; the
  benefit is deterministic refresh semantics.
- **Google Cloud project setup** — manual, one-shot. The user completes the
  Google Cloud setup checklist by hand once during initial project bootstrap.
  Click-by-click instructions live in `docs/setup.md` for repeatability. Sole
  user / single-tenant Beta; automation via `gcloud` CLI is revisited if/when a
  team scales the project.
- **Sign-in flow target during Phase 7** — TODO placeholder. The callback's
  sign-in branch redirects to `root_path` and leaves a TODO marker in the source
  pointing at Phase 12. Real session establishment (signing the user into a Pito
  session, populating `Current.user`, redirecting to the intended URL) lands in
  Phase 12 (Auth UI) — that's the phase that owns the user-facing session
  lifecycle.
- **Connection model** — one `GoogleIdentity` per User. The schema permits N
  (the `(tenant_id, user_id)` index is non-unique to keep options open for
  Theta), but the Beta UI in 7C enforces 1: at most one identity per user is
  surfaced and reachable.
