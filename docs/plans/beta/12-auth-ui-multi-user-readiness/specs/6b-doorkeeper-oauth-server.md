# Phase 6 — Step B — Doorkeeper OAuth Server

> Second deliverable for Phase 6. Adds Doorkeeper as Pito's OAuth 2.0
> authorization server, exposes `/oauth/authorize` / `/oauth/token` /
> `/oauth/revoke` / `/oauth/introspect`, maps Doorkeeper scopes onto Phase 5's
> `Scopes::ALL` catalog, registers a pre-seeded `pito-cli` application, and
> wires Doorkeeper-issued access tokens through the SAME `Api::AuthConcern` that
> already authenticates Phase 5's `ApiToken` records. Programmatic clients (the
> Rust `pito` CLI, future mobile apps, future automations) will move from
> manual-mint `ApiToken`s to Doorkeeper-issued tokens via Authorization Code +
> PKCE flow. Manual `ApiToken`s remain valid in parallel — long-lived service
> tokens stay in their own lane. Date: 2026-05-05. Locked decisions are pinned
> exactly — do not reinvent.

---

## 1. Goal

Stand up a standard OAuth 2.0 authorization server inside Pito so any external
client (current: the Rust CLI; future: anything else) can get a scoped access
token via the canonical browser-redirect-and-exchange flow instead of asking the
user to manually paste a token. The authentication boundary that Phase 5
cemented stays exactly where it is — bearer header, scope check, `Current`
populated — but the token issuance surface gets a second producer alongside the
manual `/settings/tokens` mint flow.

This step intentionally **does not** retire the manual `ApiToken` flow.
Long-lived integration tokens (e.g., a future Slack bot, a backup automation)
live as manually-minted `ApiToken`s; OAuth-issued tokens are for
browser-mediated client authorization with refresh semantics. Both shapes are
first-class.

This step also intentionally **does not** migrate the existing CLI auth surface.
Phase 5 closed without an `/auth/cli/*` endpoint pair (the Phase 4 CLI uses
manual `ApiToken` paste); the CLI migration to OAuth is a small follow-up,
captured in §11.

## 2. Depends on

- Phase 5 Step A — `Tenant`, `User`, `BelongsToTenant`, `Current.tenant_id`
  default scoping.
- Phase 5 Step B — `ApiToken`, `Api::AuthConcern`, `Scopes::ALL` /
  `Scopes::DESCRIPTIONS`, `:tokens.pepper` credential, audit log.
- Phase 5 Step C — `/settings/tokens` UI (this step adds a sibling
  `/settings/oauth_applications` page; nav patterns are reused).
- Step A (`6a-sessions-and-login-ui.md`) — `/oauth/authorize` requires a
  logged-in human to render the consent screen. Doorkeeper expects a session.
  Step A's `SessionsController` and cookie-based `Current.user` are required.
- The existing `Confirmable` concern + action-screen framework — the application
  revoke flow on `/settings/oauth_applications` reuses it.

## 3. Unblocks

- The Rust CLI's auth UX upgrade — once Doorkeeper is live, the CLI's planned
  PKCE flow has a real backend. (Implementation of the CLI side is a follow-up,
  not this step's deliverable; this step ensures the server endpoints exist and
  are correct.)
- Future mobile apps / browser extensions / third-party integrations in Theta —
  all standard OAuth 2.0 clients.
- Phase 7 — Google OAuth + YouTube API Foundation. Phase 7 is separate (Pito as
  an OAuth **client** to Google), but its consent / token-store patterns will
  mirror what Doorkeeper installs here. Sharing the mental model helps.

## 4. Why now

Three converging needs:

1. **Standard surface for programmatic clients.** Manual paste of a plaintext
   token works once but doesn't scale to multiple clients, refresh, or any
   future "authorize this app" UX. Doorkeeper is the audited, well-understood,
   Rails-native way.
2. **Refresh tokens.** Phase 5 `ApiToken`s are non-expiring by default. That's
   fine for service accounts and acceptable for the single-user dev token, but a
   long-lived client deserves a short-lived access token + refresh-token
   rotation pattern. Doorkeeper handles this idiomatically.
3. **The Rust CLI is the immediate consumer.** The CLI today asks the user to
   paste a manually-minted token; that's friction every time. Doorkeeper closes
   the loop: `pito` CLI → opens browser to `/oauth/authorize` → user consents →
   callback delivers code → CLI exchanges code for tokens → CLI persists tokens
   locally. The server side of that loop is this step.

The "tenant-leak audit" and "multi-user readiness" concerns are deferred to Step
C, not folded in here. Step B scope-check is: Doorkeeper installed, configured,
scope-mapped, endpoints live, consent UI styled per design system, application
CRUD UI under Settings.

---

## 5. Locked decisions

- **Gem: `doorkeeper`.** Use the canonical
  [doorkeeper-gem/doorkeeper](https://github.com/doorkeeper-gem/doorkeeper) gem.
  Pin to the latest 5.x release at implementation time. Do NOT hand-roll OAuth.
- **Grant types enabled:** Authorization Code (with PKCE required for public
  clients) + Refresh Token. **Disable** Implicit, Resource Owner Password
  Credentials, and Client Credentials in v1. Reasoning: Authorization Code+PKCE
  covers every Beta use case (CLI, future mobile, future browser); Implicit is
  deprecated; ROPC is dangerous; Client Credentials (M2M) is real but unused
  right now and adding it expands the threat surface without a caller. **Capture
  as Open Question:** if the user wants Client Credentials for some future M2M
  case (e.g., a Sidekiq worker on a separate host), enable then.
- **PKCE: required for public clients, optional for confidential.** Doorkeeper's
  `force_pkce` option is enabled. Public clients (`pito-cli`, future mobile)
  declare `confidential: false`; confidential clients (none in v1) can skip
  PKCE. Default new-app registration is `confidential: false` to nudge toward
  PKCE.
- **Access token TTL: 1 hour.** Refresh token TTL: 30 days. Refresh token
  rotation: enabled (every refresh issues a new refresh token, old one revoked
  immediately). Mirrors the Phase 6 plan recommendations.
- **Manual `ApiToken` TTL stays unchanged.** Phase 5's manual tokens remain
  non-expiring by default with optional `expires_at`. The policy difference
  between manual and OAuth tokens is documented in `docs/auth.md` (Step C of
  this phase).
- **Single tokens table or two?** Two. Doorkeeper installs its own
  `oauth_access_tokens`, `oauth_access_grants`, `oauth_applications` tables. We
  DO NOT merge them with `api_tokens`. Reasoning: Doorkeeper's schema is
  upstream-managed; touching it ties us to the gem's internal contracts. Keep
  the surfaces parallel and let `Api::AuthConcern` resolve either via a small
  dispatch (see §6.4).
- **Scope mapping.** Doorkeeper `default_scopes` and `optional_scopes`
  configuration both reference `Scopes::ALL`. `Scopes::ALL` remains the single
  source of truth; Doorkeeper just knows them. No new scopes added in this step.
- **Application registration UI: owner-only.** `/settings/oauth_applications` is
  gated behind a future role check (Phase 5 dropped `users.role` by formal
  decision; in single-user Beta this gate is a no-op because there is one user).
  The placeholder check is `Current.user.present?` in v1; Step C documents the
  migration path when multi-user lands.
- **Pre-seeded application: `pito-cli`.** Seed creates one Doorkeeper
  application named `pito-cli` with
  `redirect_uri: "http://127.0.0.1:0/callback"` (CLI-style loopback range; the
  actual port is dynamic, so the redirect_uri is registered as a wildcard
  `http://127.0.0.1` per Doorkeeper's loopback handling — see §6.5),
  `confidential: false`, scopes `Scopes::ALL.join(" ")`. Plaintext `client_id`
  and `client_secret` printed once during `bin/setup` (idempotent: prints only
  on the run that creates the application; subsequent runs see "exists,
  skipped").
- **Consent screen styling.** Doorkeeper's default views are not styled.
  Override via `rails generate doorkeeper:views`, then edit the generated
  `app/views/doorkeeper/authorizations/new.html.erb` to match `docs/design.md` —
  bracketed-link buttons, monospace, no JS confirm. Cancel routes to `/`.
  Approve uses Doorkeeper's default POST.
- **Revocation flow.** Doorkeeper exposes `/oauth/revoke` per RFC 7009. Wire it.
  Also: revoking an OAuth application from `/settings/oauth_applications`
  cascades to revoking every active token for that application (Doorkeeper's
  `Doorkeeper::AccessToken .revoke_all_for(application_id, resource_owner)`
  helper).
- **Audit log integration.** Every Doorkeeper-issued token grant
  (`oauth.grant`), refresh (`oauth.refresh`), and revoke (`oauth.revoke`) writes
  one JSON line to the existing `log/auth_audit.log` file. Implementation:
  subscribe to Doorkeeper's `ActiveSupport::Notifications` events
  (`doorkeeper.token.created`, `doorkeeper.token.revoked`) in a new initializer.
- **Throttling.** Apply the existing `rack-attack` infrastructure to
  `/oauth/token` (token exchange + refresh). Limit: 30 requests per IP per 5
  minutes. Higher than the login throttle (10 / 5min) because legitimate clients
  may retry on transient errors and refreshing happens hourly.

---

## 6. In scope

### 6.1 Gem install + Doorkeeper migrations

`Gemfile` gains `gem "doorkeeper"`. Run `rails generate doorkeeper:install` —
produces an initializer at `config/initializers/doorkeeper.rb` and a migration
that creates `oauth_applications`, `oauth_access_grants`, `oauth_access_tokens`
tables.

Migration adjustments before it runs:

- `oauth_applications.confidential` defaults to `false` (PKCE-encouraged).
- Add `tenant_id` (`bigint`, NOT NULL, FK to `tenants`) to `oauth_applications`.
  Reasoning: applications are tenant-scoped primitives; multi-tenant readiness
  (Step C concern) requires this. Add the same `(tenant_id, ...)` indexes Phase
  5 Step A applied to every other tenanted table.
- Add `tenant_id` to `oauth_access_tokens` and `oauth_access_grants` for the
  same reason. Backfill from the application's `tenant_id` in the data migration
  step.
- `oauth_access_tokens.scopes` is already a string column; Doorkeeper validates
  against the configured scope catalog. We do not migrate to jsonb (different
  shape than `ApiToken.scopes`, but acceptable — `Api::AuthConcern`'s scope
  check normalizes both).

`OauthApplication`, `Doorkeeper::AccessToken`, `Doorkeeper::AccessGrant` get the
`BelongsToTenant` concern via custom model classes (Doorkeeper allows
`Doorkeeper.configure { custom_model_classes }` to inject our own subclasses).

### 6.2 Doorkeeper configuration

`config/initializers/doorkeeper.rb`:

```ruby
Doorkeeper.configure do
  orm :active_record

  resource_owner_authenticator do
    if Current.user
      Current.user
    else
      cookies.signed[:pito_intended_url] = request.fullpath
      redirect_to(login_path) and return
    end
  end

  resource_owner_from_credentials do
    nil  # ROPC disabled; explicitly returns nil
  end

  admin_authenticator do |routes|
    if Current.user.present?
      Current.user
    else
      redirect_to(login_path)
    end
  end

  # Scopes — sourced from Phase 5 catalog
  default_scopes Scopes::DEV_READ
  optional_scopes(*Scopes::ALL.reject { |s| s == Scopes::DEV_READ })

  # Grant flows
  grant_flows %w[authorization_code]
  use_refresh_token
  reuse_access_token
  enforce_configured_scopes
  force_pkce  # required for public clients

  # Token TTLs
  access_token_expires_in 1.hour
  refresh_token_expires_in 30.days

  # Custom models: tenant-aware subclasses
  application_class "OauthApplication"
  access_token_class "OauthAccessToken"
  access_grant_class "OauthAccessGrant"

  # Disabled grants (explicit)
  skip_authorization do |resource_owner, client|
    false  # always show consent in v1
  end
end
```

(Pseudo-shape; implementer adapts to the gem's exact API at install time.)

### 6.3 Custom models

- `app/models/oauth_application.rb` — subclasses `Doorkeeper::Application`.
  Includes `BelongsToTenant`. Adds `belongs_to :tenant`.
- `app/models/oauth_access_token.rb` — subclasses `Doorkeeper::AccessToken`.
  Includes `BelongsToTenant`.
- `app/models/oauth_access_grant.rb` — subclasses `Doorkeeper::AccessGrant`.
  Includes `BelongsToTenant`.

Each model's `create` callback denormalizes `tenant_id` from the `application`
(for tokens / grants) at the model layer:
`before_validation :denormalize_tenant_from_application`. Mirrors the Phase 5
Step A pattern for `Footage` / `ProjectReference`.

### 6.4 `Api::AuthConcern` extension — dispatch on token type

`app/controllers/concerns/api/auth_concern.rb` (Phase 5) currently looks up
`ApiToken.unscoped.find_by(token_digest: digest)`. Extend it to also try
Doorkeeper:

1. Compute the digest (Phase 5 `Pito::TokenDigest.call(plaintext)`).
2. `ApiToken.unscoped.find_by(token_digest: digest)` — if hit, proceed as
   before.
3. If miss, attempt Doorkeeper resolution:
   `Doorkeeper.config.access_token_model.by_token(plaintext)` (the plaintext is
   what Doorkeeper stores; their schema is plaintext- indexed, not digested —
   Doorkeeper's design choice).
4. If a Doorkeeper token is found:
   - Verify `accessible?` (not revoked, not expired).
   - `Current.tenant = token.application.tenant` (via the custom model's
     `belongs_to :tenant`).
   - `Current.user = token.resource_owner` (the User who consented).
   - `Current.token` is set to a small adapter object that exposes `.scopes` as
     an array (Doorkeeper stores space-separated string), so `require_scope!`
     works unchanged.
5. If neither hit → 401 as before.

Audit log lines distinguish the source: `auth.success.api_token` vs
`auth.success.oauth`.

**Important.** The Doorkeeper token is plaintext-stored. That's a known
Doorkeeper trade-off; the plaintext lives in the database, the cookie / network
surfaces never see the digest. Acceptable under our threat model (DB compromise
= full breach regardless of hashing scheme; the hashing on `ApiToken` is a
defense-in-depth narrower than what Doorkeeper provides). **Document this** in
Step C's `docs/auth.md` update.

### 6.5 Routes

`config/routes.rb`:

```ruby
use_doorkeeper do
  controllers tokens: "oauth/tokens"  # only if we override
  skip_controllers :applications      # custom UI under /settings
end

namespace :settings do
  resources :oauth_applications, only: %i[index new create show destroy]
end
```

Doorkeeper's default routes mount under `/oauth`:

- `GET /oauth/authorize` — consent screen.
- `POST /oauth/authorize` — consent action.
- `POST /oauth/token` — exchange + refresh.
- `POST /oauth/revoke` — revoke.
- `POST /oauth/introspect` — introspect (RFC 7662).

`skip_controllers :applications` removes Doorkeeper's bundled admin UI; we
replace it with our own under `/settings/oauth_applications`.

### 6.6 `/settings/oauth_applications` controller and views

`app/controllers/settings/oauth_applications_controller.rb`:

- `index` — lists `OauthApplication.all` for `Current.tenant` (default scope
  handles it). Columns: name, `client_id`, `redirect_uri`, scopes, confidential
  (yes/no — boolean wire), active token count, `[ revoke all ]` link,
  `[ delete ]` link.
- `new` — form. Fields: name, redirect_uri (textarea, one URI per line), scopes
  (checkboxes from `Scopes::DESCRIPTIONS` — identical pattern to
  `/settings/tokens/new`), confidential (yes/no select).
- `create` — creates an `OauthApplication`. Renders `create.html.erb` (the
  show-secret-once page) with `client_id` and `client_secret` rendered in a
  monospace block, "save now" notice. **Same plaintext-shown-once ceremony as
  `/settings/tokens`.** `[ I have saved them ]` bracketed link returns to index.
- `show` — read-only detail view. Lists active tokens for this application,
  last-used timestamps, the user(s) who consented. `[ revoke ]` per token
  (cascades through `Confirmable`).
- `destroy` — deletes the application AND revokes every active token issued
  through it. Confirmation flow via `Confirmable`. Soft-revoke:
  `oauth_applications.deleted_at` if Doorkeeper supports it; otherwise actual
  delete (Doorkeeper does cascade the tokens automatically).

### 6.7 Settings nav update

`app/views/settings/_nav.html.erb` (or wherever the nav lives) gains a
`[ oauth applications ]` entry next to `[ tokens ]`. Same bracketed-link
styling.

### 6.8 Doorkeeper consent view styling

`rails generate doorkeeper:views` creates the override files. Edit:

- `app/views/doorkeeper/authorizations/new.html.erb` — consent screen. Layout
  matches the rest of the app (use the `application` layout, not Doorkeeper's
  default). Show: app name, requested scopes (each rendered with its
  `Scopes::DESCRIPTIONS` text in muted color), redirect_uri preview. Two
  bracketed-link buttons: `[ authorize ]` (POST) and `[ cancel ]` (link to `/`).
  No red — neither button is destructive at the surface level (token issuance is
  reversible).
- `app/views/doorkeeper/authorizations/error.html.erb` — error page (denied,
  invalid scope, etc.). Plain text, monospace, bracketed `[ back to home ]`
  link.
- `app/views/doorkeeper/applications/**` — generated but not used (we skipped
  Doorkeeper's bundled admin); delete those after the generator runs to avoid
  confusion.

### 6.9 Seeds — pre-seeded `pito-cli` application

Update `db/seeds.rb`:

```ruby
unless OauthApplication.unscoped.exists?(name: "pito-cli")
  Current.tenant = Tenant.first
  Current.user = User.first

  app = OauthApplication.create!(
    name: "pito-cli",
    redirect_uri: "http://127.0.0.1\nurn:ietf:wg:oauth:2.0:oob",
    scopes: Scopes::ALL.join(" "),
    confidential: false,
    tenant: Tenant.first
  )

  puts ""
  puts "=" * 64
  puts "OAuth application 'pito-cli' created (save these now):"
  puts "  client_id:     #{app.uid}"
  puts "  client_secret: #{app.secret}"
  puts "=" * 64
  puts ""
end
```

(Multiple redirect_uris are allowed by Doorkeeper as newline-separated list. The
loopback shape `http://127.0.0.1` matches RFC 8252 native-app patterns; the OOB
shape supports a copy-paste fallback.)

Idempotent: re-running `db:seed` is a no-op once the row exists.

### 6.10 `Doorkeeper` audit log subscriber

New initializer `config/initializers/doorkeeper_audit.rb`:

```ruby
ActiveSupport::Notifications.subscribe(/^doorkeeper\./) do |name, _, _, _, payload|
  AUTH_AUDIT_LOGGER.info({
    ts: Time.current.iso8601,
    event: name.sub("doorkeeper.", "oauth."),
    application_id: payload[:application]&.id,
    application_name: payload[:application]&.name,
    user_id: payload[:resource_owner]&.id,
    scopes: payload[:scopes]&.to_s,
    grant_type: payload[:grant_type],
    result: payload[:success] ? "ok" : "fail"
  }.to_json)
end
```

(Pseudo-shape — exact payload keys depend on Doorkeeper's notification API.
Implementer adjusts at install time.)

### 6.11 `rack-attack` extension

Extend `config/initializers/rack_attack.rb` with one new throttle:

```ruby
Rack::Attack.throttle("oauth/token", limit: 30, period: 5.minutes) do |req|
  req.ip if req.path == "/oauth/token" && req.post?
end
```

### 6.12 Specs

New / updated:

- `spec/models/oauth_application_spec.rb` — `BelongsToTenant` integration, scope
  validation, plaintext-secret returned exactly once.
- `spec/models/oauth_access_token_spec.rb` — `BelongsToTenant` integration,
  denormalization callback.
- `spec/requests/doorkeeper/authorizations_spec.rb` — full Auth Code + PKCE
  flow:
  1. Unauthenticated GET `/oauth/authorize?...` → 302 to `/login`, intended URL
     preserved.
  2. After login, GET `/oauth/authorize?...` → consent page renders.
  3. POST consent → redirect to `redirect_uri` with `code`.
  4. POST `/oauth/token` with code + PKCE verifier → access + refresh tokens.
  5. Use access token against a JSON endpoint → 200, scope check passes.
  6. POST `/oauth/token` with the refresh token → new access + new refresh; old
     refresh revoked.
  7. POST `/oauth/revoke` with the access token → token revoked; subsequent use
     → 401.
  8. POST `/oauth/introspect` with a valid token → JSON body with
     `active: true`, scopes, exp.
- `spec/requests/api/auth_concern_oauth_spec.rb` — `Api::AuthConcern` resolves a
  Doorkeeper-issued token, populates `Current.tenant` / `.user`, runs
  `require_scope!` correctly.
- `spec/requests/settings/oauth_applications_spec.rb` — index / new / create
  (secret rendered once) / destroy via `Confirmable`.
- `spec/system/oauth_consent_spec.rb` — Capybara end-to-end consent flow.
- `spec/initializers/doorkeeper_audit_spec.rb` — verifies the notification
  subscriber writes JSON lines on token grant / refresh / revoke.
- Existing Phase 5 specs — verify no regressions; manual `ApiToken` flow
  continues to work alongside Doorkeeper.

### 6.13 Audit log events (Step C documents)

New events emitted by this step:

- `oauth.token.created` — `{application_id, user_id, scopes, grant_type}`.
- `oauth.token.refreshed` —
  `{application_id, user_id, scopes, refresh_token_id}`.
- `oauth.token.revoked` — `{application_id, user_id, token_id, source}`. Source:
  `user`, `application_revoke`, `client_revoke`.
- `oauth.consent.granted` — `{application_id, user_id, scopes}`.
- `oauth.consent.denied` — `{application_id, user_id, scopes, reason}`.

Step C's `docs/auth.md` update enumerates them in the audit log section.

---

## 7. Out of scope

- **CLI client side** — refactoring `extras/cli/` to use the OAuth flow.
  Captured as a follow-up; once Doorkeeper is live, a small CLI dispatch
  (`cli-impl` agent) implements the loopback PKCE flow.
- **Phase 4's `/auth/cli/*` endpoints** — they don't exist (Phase 4 closed
  without that endpoint pair). Nothing to retire.
- **Manual `ApiToken` retirement** — manual tokens stay. The two surfaces
  coexist forever (or until a future phase deprecates one).
- **Tenant-leak audit** — Step C.
- **Multi-user invitation flow** — Step C.
- **Client Credentials grant** — captured in Open Questions; not enabled in v1.
- **OAuth application icons / branding** — Theta concern.
- **Admin role / per-application ownership** — single-user Beta; not surfaced.
- **Rate limit tuning** — initial limits set by this step are a starting point;
  Phase 15 polish revisits.
- **`docs/auth.md` / `docs/architecture.md` / `docs/setup.md` updates** — Step C
  owns. This step emits the events; the docs capture them.
- **Email notifications for OAuth events** ("New device authorized your
  account") — defer to Theta; requires SMTP.

---

## 8. Acceptance criteria

- [ ] `doorkeeper` gem installed, `oauth_applications`, `oauth_access_grants`,
      `oauth_access_tokens` tables exist with `tenant_id` columns (NOT NULL, FK,
      indexed).
- [ ] `OauthApplication`, `OauthAccessToken`, `OauthAccessGrant` custom models
      include `BelongsToTenant`.
- [ ] Doorkeeper configured: Auth Code + Refresh only, PKCE enforced for public
      clients, scopes mapped to `Scopes::ALL`, access token TTL 1h, refresh
      token TTL 30d, refresh rotation enabled.
- [ ] `GET /oauth/authorize` redirects to `/login` when unauthenticated; renders
      the styled consent screen when authenticated.
- [ ] `POST /oauth/authorize` issues a code and redirects to the registered
      `redirect_uri`.
- [ ] `POST /oauth/token` exchanges code for access + refresh tokens; refresh
      exchange rotates the refresh token.
- [ ] `POST /oauth/revoke` revokes the token; subsequent use returns 401.
- [ ] `POST /oauth/introspect` returns RFC 7662-shaped JSON.
- [ ] `Api::AuthConcern` resolves both `ApiToken` records and Doorkeeper-issued
      tokens through a single dispatch; `Current.tenant / .user / .token`
      populated identically.
- [ ] `/settings/oauth_applications` index / new / create / show / destroy work;
      `client_id` and `client_secret` shown exactly once at creation.
- [ ] Application destroy cascades: every active token for the application is
      revoked.
- [ ] `db/seeds.rb` mints `pito-cli` application (idempotent), prints
      `client_id` + `client_secret` to STDOUT once.
- [ ] `rack-attack` throttles `POST /oauth/token` at 30/IP/5min.
- [ ] `log/auth_audit.log` receives JSON lines on every Doorkeeper token grant /
      refresh / revoke / consent event.
- [ ] All previously-green specs (Phase 5 + 6A) remain green.
- [ ] New specs cover every flow listed in §6.12.
- [ ] Brakeman, bundler-audit, Dependabot — clean. Doorkeeper version pinned and
      audited.
- [ ] Manual `/settings/tokens` flow continues to work in parallel.

---

## 9. Manual playbook

1. `bundle install`. `bin/rails db:migrate` — `oauth_applications`,
   `oauth_access_tokens`, `oauth_access_grants` created.
2. `bin/rails db:seed` — STDOUT prints `client_id` and `client_secret` for
   `pito-cli`. Save them.
3. `bin/dev` boots both Pumas.
4. `/settings/oauth_applications` lists exactly one application: `pito-cli`,
   with the seeded `redirect_uri` lines.
5. Click `[ new ]`. Form. Name: `manual-test`. Redirect URI:
   `http://127.0.0.1:8765/callback`. Scopes: `dev:read` `project:read`.
   Confidential: no. Submit. Success page shows `client_id` + `client_secret` in
   monospace. Copy them. Click `[ I have saved them ]`. Land back on the index —
   the new app is there.
6. **Authorization Code + PKCE flow.** From a terminal:
   ```bash
   # Generate PKCE pair
   verifier=$(openssl rand -base64 96 | tr -d "=+/" | cut -c -64)
   challenge=$(echo -n $verifier | openssl dgst -sha256 -binary \
     | base64 | tr -d "=" | tr "+" "-" | tr "/" "_")
   # Open the authorization URL in browser
   open "https://app.pitomd.com/oauth/authorize?\
   response_type=code&\
   client_id=<client_id>&\
   redirect_uri=http://127.0.0.1:8765/callback&\
   scope=dev:read%20project:read&\
   code_challenge=$challenge&\
   code_challenge_method=S256"
   ```
7. The browser asks you to log in (if you weren't already) → land on the styled
   consent screen showing app name, scopes with descriptions. Click
   `[ authorize ]`. Browser redirects to
   `http://127.0.0.1:8765/callback?code=...`. Capture the `code`.
8. Exchange:
   ```bash
   curl -i -X POST https://app.pitomd.com/oauth/token \
     -d "grant_type=authorization_code" \
     -d "client_id=<client_id>" \
     -d "redirect_uri=http://127.0.0.1:8765/callback" \
     -d "code=<code>" \
     -d "code_verifier=$verifier"
   ```
   → 200 with `{access_token, refresh_token, expires_in, scope}`.
9. Use the access token against a JSON endpoint:
   ```bash
   curl -i -H "Authorization: Bearer <access_token>" \
     https://app.pitomd.com/api/footages
   ```
   → 200 if scope satisfied; 403 with `insufficient_scope` if not.
10. Refresh:
    ```bash
    curl -i -X POST https://app.pitomd.com/oauth/token \
      -d "grant_type=refresh_token" \
      -d "client_id=<client_id>" \
      -d "refresh_token=<refresh_token>"
    ```
    → 200 with NEW access + NEW refresh (old refresh now revoked).
11. Revoke:
    ```bash
    curl -i -X POST https://app.pitomd.com/oauth/revoke \
      -d "token=<access_token>" \
      -d "client_id=<client_id>"
    ```
    → 200. Subsequent use of the access token → 401.
12. From `/settings/oauth_applications`, click `[ delete ]` on `manual-test`.
    Confirmation screen. Confirm. Back on the index — `manual-test` gone, all
    its tokens revoked.
13. Hammer 31 token requests in 5 minutes — 31st returns 429.
14. `tail log/auth_audit.log` — JSON lines for `oauth.consent.granted`,
    `oauth.token.created`, `oauth.token.refreshed`, `oauth.token.revoked`.
15. Sanity: `/settings/tokens` (Phase 5 manual flow) still works. Mint a manual
    token; `curl` with it; works.
16. `bundle exec rspec` — green.

---

## 10. File-scope inventory

Implementer (Lane 1 rails-impl) touches:

- `Gemfile`, `Gemfile.lock` — add `doorkeeper`.
- `db/migrate/<ts>_install_doorkeeper.rb` — Doorkeeper's installer output, with
  `confidential` default flipped to `false`.
- `db/migrate/<ts>_add_tenant_id_to_oauth_tables.rb` — three-step pattern (add
  nullable, backfill, NOT NULL) per table.
- `app/models/oauth_application.rb`, `app/models/oauth_access_token.rb`,
  `app/models/oauth_access_grant.rb` — new (custom Doorkeeper subclasses).
- `app/controllers/concerns/api/auth_concern.rb` — extend with Doorkeeper
  dispatch.
- `app/controllers/settings/oauth_applications_controller.rb` — new.
- `app/views/settings/oauth_applications/index.html.erb` — new.
- `app/views/settings/oauth_applications/new.html.erb` — new.
- `app/views/settings/oauth_applications/create.html.erb` — new
  (show-secrets-once page).
- `app/views/settings/oauth_applications/show.html.erb` — new.
- `app/views/settings/oauth_applications/_form.html.erb` — new.
- `app/views/doorkeeper/authorizations/new.html.erb` — overridden, styled.
- `app/views/doorkeeper/authorizations/error.html.erb` — overridden, styled.
- `app/views/settings/_nav.html.erb` — add `[ oauth applications ]`.
- `config/initializers/doorkeeper.rb` — new (generated, then edited).
- `config/initializers/doorkeeper_audit.rb` — new.
- `config/initializers/rack_attack.rb` — extend with `oauth/token` throttle.
- `config/routes.rb` — `use_doorkeeper`, namespaced settings resource.
- `db/seeds.rb` — `pito-cli` application mint (idempotent, prints credentials
  once).
- `spec/factories/oauth_applications.rb` — new.
- `spec/factories/oauth_access_tokens.rb` — new.
- `spec/models/oauth_application_spec.rb` — new.
- `spec/models/oauth_access_token_spec.rb` — new.
- `spec/requests/doorkeeper/authorizations_spec.rb` — new.
- `spec/requests/api/auth_concern_oauth_spec.rb` — new.
- `spec/requests/settings/oauth_applications_spec.rb` — new.
- `spec/system/oauth_consent_spec.rb` — new.
- `spec/initializers/doorkeeper_audit_spec.rb` — new.

Out of bounds for this step:

- `extras/cli/**` — CLI side migration is a follow-up dispatch, not this step.
  The server endpoints are the deliverable here; the CLI consumer follows.
- `app/mcp/**` — MCP tools continue to receive bearer tokens via
  `Api::AuthConcern`'s extended dispatch; no MCP-specific changes needed.
- `app/views/sessions/**`, `app/controllers/sessions_controller.rb` — owned by
  Step A.
- `docs/auth.md`, `docs/architecture.md`, `docs/mcp.md`, `docs/setup.md` — Step
  C owns the doc updates.
- `app/lib/scopes.rb` — Phase 5 owns; this step references.

## 11. Open questions

- **Client Credentials grant (M2M).** Spec disables it in v1. The user should
  confirm: any future M2M case (a Sidekiq worker on a separate host calling the
  JSON API on behalf of "the system", not a user) that wants Client Credentials?
  If yes, enable; if no, punt to Theta. **Default if not answered: keep
  disabled.**
- **Doorkeeper plaintext access tokens.** Doorkeeper stores access tokens
  plaintext in `oauth_access_tokens.token`. This is a documented Doorkeeper
  trade-off. Spec accepts it. The user should acknowledge: Pito's threat model
  allows this (DB compromise = full breach regardless; the digest on `ApiToken`
  is defense-in-depth, not a hard requirement). If the user disagrees, options
  are (a) override Doorkeeper's storage with a hashed variant — increases
  ongoing maintenance, or (b) drop Doorkeeper and hand-roll — rejected upstream.
  Spec assumes (acknowledged, accepted).
- **Pre-seeded `pito-cli` redirect URIs.** Spec proposes `http://127.0.0.1`
  (loopback wildcard) + `urn:ietf:wg:oauth:2.0:oob` (OOB copy-paste). Confirm
  whether OOB is wanted or just loopback. (OOB is deprecated by RFC 8252 but
  occasionally useful.)
- **CLI follow-up sequencing.** After Step B ships, the Rust CLI still uses
  manual `ApiToken` paste. Confirm whether the CLI migration to OAuth is part of
  Phase 6 (then it's a fourth sub-step 6D), or punted to a Phase 7+ polish
  window. Spec defers.
- **Consent screen "remember this app for 30 days" checkbox.** Doorkeeper
  supports skipping consent on subsequent grants for the same scopes
  (`skip_authorization` block). Spec disables in v1 (always show consent).
  Confirm or relax.
- **Application admin gating.** Spec uses `Current.user.present?` as the
  placeholder admin check. Confirm: in single-user Beta, is "any logged-in user
  can manage applications" acceptable, or do we want the placeholder to fail
  closed (only the seeded owner)? **Default: any logged-in user, since there is
  one.**
