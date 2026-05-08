# Phase 12 — Auth UI + Multi-User Readiness · Session Log

## 2026-05-07 — Step 6A + 6B — Sessions/Login UI + Doorkeeper OAuth Server

**State at start:** Phase 5 (auth foundation) committed: `Tenant`, `User`,
`ApiToken`, `Api::AuthConcern`, `Api::TokenAuthenticator`, `Scopes::ALL`,
`:tokens.pepper` credential, `auth_audit.log`. HTML routes were running on the
implicit pin
(`before_action :set_current_tenant_and_user → Tenant.first / User.first`) — no
real cookie session existed. No OAuth server. The `pito-cli` binary's auth UX
was still manual `ApiToken` paste.

**Inputs:**

- `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6a-sessions-and-login-ui.md`
  — full session table + login UI + active sessions index per the locked
  decisions in §11.
- `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md`
  — Doorkeeper installation, config, custom tenant-tagged models, scope mapping,
  audit subscriber, throttle.
- User-issued constraint: do NOT touch `Api::AuthConcern` or the MCP
  `Mcp::RackApp` (Doorkeeper is a parallel auth path for future third-party
  clients, not a replacement for ApiToken-based bearer auth).

**What landed (file-level):**

Phase 6A — Sessions & Login UI:

- `db/migrate/20260507200000_create_sessions.rb` — server-side `sessions` table
  per §6.1.
- `app/models/session.rb` — `BelongsToTenant`, `create_for!`, `touch_activity!`
  (5-minute debounce), `revoke!`, `current?`.
- `app/models/current.rb` — added `:session` attribute.
- `app/models/user.rb` — `has_many :sessions, dependent: :destroy`, minimum
  8-character password validation gated on `password.present?`.
- `app/lib/pito/token_digest.rb` — single-source-of-truth HMAC helper shared by
  `ApiToken` and `Session`. `ApiToken.digest` now forwards through this helper
  while preserving the existing `ApiToken.pepper` override hook for specs.
- `app/lib/sessions/authenticator.rb` — Result-struct cookie resolver (success /
  `:missing` / `:unknown_token` / `:revoked` / `:auth_misconfigured`).
- `app/lib/session_throttle.rb` — failed-login bucket (10 / 5min / IP).
- `app/controllers/concerns/sessions/auth_concern.rb` — replaces the implicit
  pin with cookie-session resolution, intended-URL stash, and `Current.reset`
  around-action.
- `app/controllers/application_controller.rb` — includes
  `Sessions::AuthConcern`; the legacy `set_current_tenant_and_user` method is
  gone.
- `app/controllers/sessions_controller.rb` — `new` / `create` / `destroy`,
  dummy-bcrypt timing equalizer, `yes`/`no` `remember_me`, generic error
  message, throttle integration.
- `app/controllers/settings/sessions_controller.rb` — index / `revoke`
  action-screen / `destroy` (revoking the current session bounces to /login).
- `app/views/sessions/new.html.erb`,
  `app/views/settings/sessions/{index,revoke}.html.erb` — bracketed-link
  buttons, monospace inputs, no JS confirm.
- `app/views/layouts/application.html.erb` — `[ logout ]` button via
  `button_to method: :delete` when `Current.user.present?`.
- `config/routes.rb` — `/login`, `/session`, `/settings/sessions`.
- `config/initializers/rack_attack.rb` — failed-login throttle (10 / 5min / IP,
  mirroring the Phase 5B failed-token-lookup bucket).
- `app/controllers/api/footages_controller.rb` — replaced the obsolete
  `skip_before_action :set_current_tenant_and_user` line with
  `skip_before_action :authenticate_session!`. JSON path stays bearer- only via
  `Api::AuthConcern` as before.
- `app/views/settings/index.html.erb` + `settings_controller.rb` — added two new
  panes (sessions + oauth applications) with active counts.
- Specs: `spec/factories/sessions.rb`, `spec/models/session_spec.rb`,
  `spec/models/user_spec.rb` (extended), `spec/lib/pito/token_digest_spec.rb`,
  `spec/lib/sessions/authenticator_spec.rb`, `spec/requests/sessions_spec.rb`,
  `spec/requests/settings/sessions_spec.rb`,
  `spec/requests/application_controller_current_spec.rb` (rewritten),
  `spec/support/auth.rb` (the `sign_in_as(user)` helper + auto-sign-in hooks for
  request and system specs that pre-existed the cookie surface).

Phase 6B — Doorkeeper OAuth Server:

- `Gemfile` — `gem "doorkeeper", "~> 5.8"` (resolved to 5.9.0).
- `db/migrate/20260507200001_create_doorkeeper_tables.rb` — Doorkeeper installer
  output, modified to (a) flip `confidential` default to `false` and (b) add
  `tenant_id` (NOT NULL, FK, indexed) on all three Doorkeeper tables.
- `app/models/oauth_application.rb`, `app/models/oauth_access_token.rb`,
  `app/models/oauth_access_grant.rb` — custom Doorkeeper subclasses with
  `belongs_to :tenant` + a `before_validation` that denormalizes `tenant_id`
  from the owning application onto tokens and grants.
- `config/initializers/doorkeeper.rb` — Authorization Code + PKCE ONLY,
  refresh-token rotation, 2h access token TTL, `Scopes::ALL`-aware default +
  optional scopes, `enforce_configured_scopes`, `force_pkce`, custom model
  wiring, resource-owner block resolves the cookie session via
  `Sessions::Authenticator`.
- `config/initializers/doorkeeper_audit.rb` — subscribes to `create_token` /
  `refresh_token` / `revoke_token` Doorkeeper notifications and writes JSON
  lines to `auth_audit.log`.
- `config/routes.rb` — `use_doorkeeper` (skips bundled applications +
  authorized_applications admin), `/settings/oauth_applications` (index / new /
  create / show / destroy / revoke).
- `config/initializers/rack_attack.rb` — `/oauth/token` throttle (30 / 5min /
  IP).
- `app/controllers/settings/oauth_applications_controller.rb` — CRUD + `revoke`
  action-screen, plaintext `client_secret` shown-once on `create`.
- `app/views/settings/oauth_applications/{index,new,_form,create, show,revoke}.html.erb`
  — bracketed-link forms, no JS confirm.
- `app/views/doorkeeper/authorizations/{new,error}.html.erb` — styled consent
  screen + error page; bundled admin views deleted to avoid drift.
- Specs: `spec/factories/oauth_applications.rb`,
  `spec/models/oauth_application_spec.rb`,
  `spec/models/oauth_access_token_spec.rb`,
  `spec/requests/oauth_authorization_spec.rb`,
  `spec/requests/settings/oauth_applications_spec.rb`.

**Decisions captured during execution (deviations from the spec body):**

- **Per the user-issued constraint, `Api::AuthConcern` was NOT extended to
  dispatch on Doorkeeper-issued tokens.** The spec body §6.4 calls for that
  dispatch but the user explicitly overrode it ("DO NOT touch Api::AuthConcern.
  Doorkeeper is a parallel auth path for future third-party clients, not a
  replacement for ApiToken-based bearer auth"). Issued OAuth tokens currently
  work against the Doorkeeper endpoints themselves (introspect / revoke) but
  cannot authenticate against `/api/*` or MCP. Step C should either revisit this
  or document the parallel-only state in `docs/auth.md`.
- **`OauthApplication`, `OauthAccessToken`, `OauthAccessGrant` do NOT include
  `BelongsToTenant`.** Spec §6.3 calls for it, but the Doorkeeper plumbing
  queries these models from the `/oauth/token`, `/oauth/authorize`, and
  `/oauth/revoke` endpoints — none of which have a cookie session in scope, so
  `Current.tenant` is unset and the default scope's "raise on missing tenant"
  trip wire breaks the OAuth flow. Each model still has `belongs_to :tenant` and
  a `before_validation` callback that denormalizes the column from the owning
  application; tenant attribution at the data level is intact. The
  `/settings/oauth_applications` controller scopes its queries explicitly with
  `where(tenant_id: Current.tenant_id)`. Documented at the top of each model
  file.
- **No `refresh_token_expires_in` knob.** Doorkeeper 5.9 has no first-class
  option for it; refresh-token lifetime is governed by rotation. The "14d
  refresh" spec target is approximated by clients refreshing within the 2h
  access-token window; abandoned chains end when the application is destroyed
  (cascade). Documented inline.
- **`pito-cli` seed application not minted in this dispatch.** §6.9 calls for a
  seed mint in `db/seeds.rb`. Held off to keep the seed idempotency contract
  stable while the new tables settle in. Manual registration via
  `/settings/oauth_applications/new` works today; a follow-up dispatch can add
  the seed.
- **`introspect` endpoint not directly spec-tested.** The endpoint is mounted
  (Doorkeeper's default) but the spec covers
  `authorize / token / refresh / revoke` only. Adding an introspect test is a
  small follow-up.
- **System and request specs auto-sign-in by default** via a `before(:each)`
  hook in `spec/support/auth.rb`. Specs that need to assert on `/login` redirect
  / unauthenticated state use `metadata[:unauthenticated] => true`.

**Verification:**

- `bundle exec rspec` — 1650 examples, 0 failures, 0 pending.
- `bundle exec rubocop` — 371 files, 0 offenses (one
  `Layout/SpaceBeforeFirstArg` in the Doorkeeper migration was auto-corrected).
- `bundle exec brakeman -q -w2` — 0 security warnings, 0 errors.

**Files for the reviewer to focus on:**

- `app/lib/pito/token_digest.rb` and `app/models/api_token.rb` — the digest
  refactor changed `ApiToken.digest`'s implementation but kept its public
  contract; verify no Phase 5 spec regressed.
- `app/controllers/concerns/sessions/auth_concern.rb` — the `intended_url`
  cookie semantics + `Current.reset` around-action ordering vs. `Current.reset`
  in `rails_helper.rb`'s `after(:each)`.
- `config/initializers/doorkeeper.rb` — `resource_owner_authenticator` resolves
  the cookie session directly (Doorkeeper's controllers inherit from
  `ActionController::Base` by default, so `Sessions::AuthConcern`'s
  `before_action` doesn't run). Confirm the `Current.reset` discipline holds for
  `/oauth/authorize` requests.
- `app/views/layouts/application.html.erb` — `[ logout ]` `button_to` styling;
  confirm the form / button layout matches the design system in browser.

**Manual playbook (user to validate before commit):**

1. `bundle install` (already done; only doorkeeper 5.9 added).
2. `bin/rails db:migrate` (already done locally).
3. Open `/` in a fresh browser → 302 to `/login`. Log in with the seeded
   credentials.
4. Verify `[ logout ]` appears top-right; click → land at `/login`,
   `pito_session` cookie cleared.
5. `/settings` — confirm two new panes appear (sessions, oauth applications)
   with counts.
6. `/settings/sessions` — list shows the active session annotated
   `(this session)`. Open another browser, log in same user, verify two
   sessions. Revoke the other one from the first browser; in the other browser,
   click any link → bounce to `/login`.
7. `/settings/oauth_applications/new` — register a test app
   (`http://127.0.0.1:8765/callback`, scopes `dev:read project:read`,
   `confidential: no`). Save the client_id + client_secret from the
   show-secrets-once page.
8. From a terminal, run the manual PKCE round-trip from the spec's §9 manual
   playbook: open `/oauth/authorize?...` → consent → capture code → exchange at
   `/oauth/token` → refresh → `tail -f log/auth_audit.log` shows
   `oauth.token.created` and `oauth.token.refreshed` lines.
9. Hammer 11 failed logins from one IP — 11th returns 429.
10. Hit `/api/footages` with no Authorization header → 401 (verifies Phase 5
    bearer surface still active in parallel).
