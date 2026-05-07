# Phase 7 — Step 7A — Google OAuth Sign-In and `GoogleIdentity`

> First of three Phase 7 specs. Lands the OAuth plumbing and the encrypted
> identity record before any YouTube API call is made. Sibling specs:
> `7b-youtube-client-and-audit.md`, `7c-settings-youtube-ui.md`. Locked decisions
> are pinned exactly — do not reinvent.

---

## Goal

Wire up the OmniAuth-based Google OAuth flow so a Pito `User` (Phase 5) can
authorize the app against their Google account and have the resulting tokens
persisted as an encrypted `GoogleIdentity` row. This step delivers the OAuth
round-trip, the `GoogleIdentity` model + migration, the callback controller,
the routes, and the credentials wiring. **It does not call the YouTube API**
(7B) and **does not render any Settings UI** (7C). The sole user-visible
surface here is the redirect chain `/auth/google → Google → callback →
redirect target`.

This spec also reserves — but does not light up — the dedicated **sign-in**
entry point that Phase 12 (Auth UI) will surface. Phase 7 only needs the
**connection** entry point (used by 7C); the sign-in route exists as a thin
wrapper requesting only userinfo scopes, so Phase 12 inherits a working flow.

## Files touched

Rails (Lane 1):

- `Gemfile` — add `omniauth-google-oauth2`, `omniauth-rails_csrf_protection`.
- `config/initializers/omniauth.rb` — register the Google provider, point at
  Rails credentials, configure state + PKCE.
- `config/routes.rb` — `/auth/google`, `/auth/google/callback`,
  `/auth/failure`, `/settings/youtube/connect` (redirector that re-enters
  OmniAuth with the YouTube scope set).
- `app/controllers/auth/google_callbacks_controller.rb` — callback handling,
  identity upsert, redirect dispatch.
- `app/controllers/concerns/google_oauth_redirect.rb` — small helper to
  compute return-to paths between the sign-in flow and the connect flow.
- `app/models/google_identity.rb` — model with encrypted token columns,
  associations, expiry helpers.
- `db/migrate/<ts>_create_google_identities.rb` — table per §"Schema".
- `config/credentials/development.yml.enc`, `config/credentials/test.yml.enc`,
  `config/credentials/production.yml.enc` — `:google` block per §"Credentials".
- `.env.example` — note that no env var lives here for OAuth (credentials
  only); document the redirect URI registered with Google.
- `spec/factories/google_identities.rb`
- `spec/models/google_identity_spec.rb`
- `spec/requests/auth/google_callbacks_spec.rb`
- `spec/system/google_oauth_flow_spec.rb` (with OmniAuth test mode)

Documentation (parallel docs-keeper dispatch — out of this spec's lane):

- `docs/setup.md` — Google Cloud project bootstrap steps for fresh installs.
- `docs/architecture.md` — "Google OAuth" subsection wired into the auth map.

Cross-stack scope: Rails-only.

## Schema

`google_identities` — one row per (User, Google account) pair.

| Column                 | Type      | Constraints                                            |
| ---------------------- | --------- | ------------------------------------------------------ |
| id                     | bigint    | pk                                                     |
| tenant_id              | bigint    | not null, fk → tenants, default-scoped via `Current`   |
| user_id                | bigint    | not null, fk → users                                   |
| google_subject_id      | string    | not null, unique within (tenant_id)                    |
| email                  | citext    | not null                                               |
| access_token           | text      | not null, encrypted (Active Record Encryption)         |
| refresh_token          | text      | nullable, encrypted (Google may omit on re-grant)      |
| expires_at             | datetime  | not null                                               |
| scopes                 | jsonb     | not null, default `[]`, array of granted scope strings |
| needs_reauth           | boolean   | not null, default `false`                              |
| last_refreshed_at      | datetime  | nullable                                               |
| last_authorized_at     | datetime  | not null (set on every successful callback)            |
| created_at, updated_at | datetime  | not null                                               |

Indexes:

- `(tenant_id, google_subject_id)` unique.
- `(tenant_id, user_id)` non-unique (a user may, in Theta, hold multiple
  Google identities; Beta UI enforces one).
- `(tenant_id, needs_reauth)` partial where `needs_reauth = true` — fast lookup
  for the "needs reauth" banner check in 7C.

Encryption:

- `encrypts :access_token`
- `encrypts :refresh_token`
- Deterministic encryption is **not** used; tokens are not searchable.
- Active Record Encryption keys live in Rails credentials per environment;
  reuse the keys established in Phase 5 / earlier. Do **not** generate a new
  key for this phase.

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

Two scope sets are configured. The flow that triggers OmniAuth picks one set
in the request phase via the `scope:` option.

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

**Locked decision — minimum YouTube scopes for Beta.** The YouTube connection
flow requests `youtube.readonly` and `yt-analytics.readonly` ONLY. The full
`youtube` (write) and `youtube.upload` scopes are reserved for Phase 10
(Video Workflow Features). Adding write scopes earlier triggers a Google
re-consent screen later anyway, so we may as well stage it correctly. See
"Open questions" §1 — confirm with user before building.

`access_type: "offline"` and `prompt: "consent"` are passed on every
authorization request so Google reliably returns a refresh token.

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
and redirects to OmniAuth's request phase with `scope: <youtube scope set>`.
The callback controller dispatches on the stashed intent.

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
2. Read `session.delete(:google_oauth_intent)` → `"youtube_connect"` or
   `nil` (default sign-in flow).
3. Find or create `GoogleIdentity` keyed on `(tenant_id, google_subject_id)`:
   - On **create**: scope to `Current.user` (Phase 5 sets this; if for some
     reason `Current.user` is nil, redirect to `/` with a flash error).
   - On **update**: refresh `access_token`, `refresh_token` (only if Google
     returned one — preserve previous on absence), `expires_at`, `scopes`
     (union with existing), `last_authorized_at`, set `needs_reauth: false`.
4. Dispatch by intent:
   - `"youtube_connect"` → redirect to `/settings/youtube` (7C lights this up).
   - `nil` (sign-in) → redirect to `session.delete(:return_to) || root_path`.
     Phase 12 will plug a real session establishment in here; Phase 7 leaves
     a TODO comment and a passing spec that asserts the redirect target.
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
environment uses OmniAuth's test mode and never reaches Google — credentials
can be placeholder strings (`"test-client-id"`, `"test-client-secret"`).

## Acceptance

- [ ] `omniauth-google-oauth2` and `omniauth-rails_csrf_protection` added to
      Gemfile; `bundle install` succeeds.
- [ ] Migration creates `google_identities` with all columns, types, indexes,
      and encryption per §"Schema".
- [ ] `GoogleIdentity` model has the four helpers (`access_token_expired?`,
      `needs_reauth?`, `has_scope?`, `scope_string`) covered by specs.
- [ ] `encrypts :access_token` and `encrypts :refresh_token` are in place;
      a model spec asserts that `GoogleIdentity.last.access_token_before_type_cast`
      (raw column read) is **not** equal to the plaintext value passed in.
- [ ] Routes per §"Routes" exist; `bin/rails routes | grep google` shows them.
- [ ] `:google` credentials block exists in development, test, production
      encrypted credentials files (test values may be placeholders).
- [ ] Callback creates a new `GoogleIdentity` on first authorization
      (request spec with OmniAuth test mode).
- [ ] Callback updates an existing `GoogleIdentity` on re-authorization,
      preserving the previous `refresh_token` if Google omits it.
- [ ] Callback unions newly granted scopes into the `scopes` jsonb array
      rather than replacing.
- [ ] Callback resets `needs_reauth: false` on a successful re-authorization.
- [ ] Callback redirects to `/settings/youtube` when the intent stash is
      `"youtube_connect"`, else to `root_path`.
- [ ] Callback redirects to `/auth/failure` with a flash on
      `omniauth.error` set.
- [ ] State parameter validation is on (test by spoofing a mismatched state
      and asserting OmniAuth rejects).
- [ ] Tenant-scoping spec: a `GoogleIdentity` created under tenant A is not
      visible to a `Current.tenant = B` query.
- [ ] System spec drives the full flow in OmniAuth test mode end-to-end:
      click `[ connect google ]` (rendered by 7C — for this spec, point at a
      stub button) → mocked Google response → identity persisted → redirect.
- [ ] No JS `alert` / `confirm` / `prompt` introduced (it shouldn't be —
      OAuth is server redirects).
- [ ] Brakeman clean (especially: callback CSRF, open redirect on
      `session[:return_to]`).

## Manual test recipe

Prereq: the user has completed the Phase 7 plan's Google Cloud setup
checklist (`docs/setup.md` will document this; see "Open questions" §3 for
ownership).

1. `bin/rails credentials:edit --environment development` — add the
   `:google` block with the real client id / secret. Save.
2. `bin/dev` — Web Puma + Sidekiq + Tailwind start.
3. From the Cloudflare tunnel host: visit
   `https://app.pitomd.com/auth/google` (dev-only direct GET — see
   §"Routes"). The browser bounces to Google's consent screen.
4. Approve. Browser returns to `https://app.pitomd.com/auth/google/callback`,
   which redirects to `/`.
5. `bin/rails console` — confirm:

   ```ruby
   GoogleIdentity.last.email           # the user's google email
   GoogleIdentity.last.scopes          # ["openid", "email", "profile"]
   GoogleIdentity.last.expires_at      # ~ 1 hour from now
   GoogleIdentity.last.read_attribute_before_type_cast(:access_token)
   # encrypted blob, NOT the plaintext access token
   ```

6. Visit `https://app.pitomd.com/settings/youtube/connect` — bounces back to
   Google. Approve YouTube scopes. Returns to `/settings/youtube` (7C
   surfaces a "not implemented" placeholder page in this spec; 7C makes it
   real).
7. `bin/rails console`:

   ```ruby
   GoogleIdentity.last.scopes
   # ["openid", "email", "profile",
   #  "https://www.googleapis.com/auth/youtube.readonly",
   #  "https://www.googleapis.com/auth/yt-analytics.readonly"]
   ```

8. Connect to psql; verify `SELECT access_token FROM google_identities` shows
   ciphertext, not the plaintext bearer token.
9. `bundle exec rspec spec/models/google_identity_spec.rb
   spec/requests/auth/google_callbacks_spec.rb spec/system/google_oauth_flow_spec.rb`
   — all green.

Teardown: `GoogleIdentity.destroy_all` in console (real disconnect-with-revoke
is a 7C concern). Manually revoke the grant from
https://myaccount.google.com/permissions if you want to re-test from scratch.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI (`extras/cli/`) — **skipped.** The CLI does not need a Google
  identity in Phase 7. When Phase 8 (Data Sync) lands, the CLI may surface
  sync state, but no OAuth flow runs through the CLI itself.
- MCP — **skipped.** No `yt:*` MCP tools call Google in Phase 7. (Phase 8
  introduces sync tools that consume `GoogleIdentity` server-side.)
- Cloudflare Pages website — **skipped.** OAuth happens entirely on
  `app.pitomd.com`.

## Open questions

1. **YouTube scope set.** Beta starts with `youtube.readonly` +
   `yt-analytics.readonly`. Phase 10 will need `youtube` (full read/write) +
   `youtube.upload`. Should Phase 7 request the wider set up front to avoid
   a re-consent later, or accept the re-consent in exchange for a smaller
   blast radius now? The plan's `## In scope` says request the full set
   (`youtube.readonly`, `youtube`, `yt-analytics.readonly`); this spec
   defaults to the minimum and asks the master agent to confirm.
2. **Refresh-token-absent on re-auth.** Google sometimes omits the refresh
   token on a subsequent consent if the user previously granted offline
   access. The spec preserves the previous refresh token in that case. Is
   that the correct policy, or should we force `prompt: "consent"` to
   guarantee a fresh refresh token on every re-auth (at the cost of an
   extra user-visible consent screen)? Default in this spec: force
   `prompt: "consent"`, accept the consent UX, refresh token is always
   returned.
3. **Google Cloud setup ownership.** The plan's `### Google Cloud setup`
   checklist lists six items. Are these the user's manual one-time tasks
   (architect-spec records them in `docs/setup.md` for repeatability), or
   should an agent automate any of them via `gcloud` CLI? Default
   assumption: user does this by hand once, docs-keeper records the steps.
4. **Sign-in flow target.** Phase 12 plugs real session establishment into
   the sign-in callback path. Phase 7 leaves a TODO. Confirm the master
   agent is OK with a TODO landing in this phase (alternative: gate the
   sign-in route behind a feature flag until Phase 12).
