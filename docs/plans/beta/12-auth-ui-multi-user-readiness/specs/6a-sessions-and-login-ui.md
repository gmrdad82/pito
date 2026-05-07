# Phase 6 — Step A — Sessions and Login UI

> First deliverable for Phase 6 (Auth UI + Multi-User Readiness). Lands the
> human-facing session surface on top of Phase 5's bearer-token foundation: a
> real `/login` form, server-side `sessions` table, cookie-stored session id,
> sign-out, "Remember me", redirect-after-login, an Active Sessions list under
> Settings → Account, and `rack-attack` throttling on failed logins. Step A
> intentionally **defers password reset and email change** to a follow-up
> sub-step (6A.5) so this step ships without introducing transactional email —
> Pito has no SMTP wiring yet, and bolting it on here would balloon the surface
> area. Date: 2026-05-05. Locked decisions are pinned exactly — do not reinvent.

---

## 1. Goal

Replace the implicit single-user session
(`before_action :set_current_tenant_and_user → Tenant.first / User.first`) with
a real cookie-backed session whose source of truth is a server-side `sessions`
row. The user logs in via `/login`, the controller verifies the password against
`User#authenticate` (already wired via `has_secure_password` in Phase 5),
creates a `Session` row, sets a signed cookie holding the session token, and
`Current.user` / `Current.tenant` are populated from that row on every
subsequent request to an HTML route. Logout deletes the cookie and revokes the
row. A list of active sessions in Settings → Account lets the user revoke any
other session remotely.

This step **does not** touch JSON-API or MCP auth — those remain
bearer-token-only via Phase 5's `Api::TokenAuthenticator` / `Api::AuthConcern`.
Cookie session is the HTML lane; bearer is the programmatic lane. The two
coexist.

## 2. Depends on

- Phase 5 Step A — `Tenant`, `User`, `BelongsToTenant`, `Current.tenant_id`
  default scoping, the `tenants` and `users` tables.
- Phase 5 Step B — `Api::TokenAuthenticator`, `Api::AuthConcern`, `rack-attack`
  initializer, `auth_audit.log` logger, `Scopes` catalog, `:tokens.pepper`
  credential.
- Phase 5 Step C — `docs/auth.md` (this step extends §1, §4, §6, and §11), the
  dev-token seed pattern (this step adds a session-token analogue under the same
  idempotent shape).
- The existing `before_action :set_current_tenant_and_user` (the parallel
  pre-Phase-5 patch that pins `Current.tenant = Tenant.first` and
  `Current.user = User.first`). This step replaces that filter.

## 3. Unblocks

- Step B (`6b-doorkeeper-oauth-server.md`) — Doorkeeper's authorization endpoint
  needs a logged-in human to consent. Until `/login` exists, the consent screen
  has no caller. Step B's `/oauth/authorize` requires Step A to be live.
- Step C (`6c-tenant-leak-audit-and-multi-user-readiness.md`) — the cross-tenant
  leak meta-test exercises both bearer and cookie auth. Cookie auth has to exist
  first.
- Phase 6.5 (or a sub-step inside 6A) — password reset, email change, invitation
  flow. All need transactional email; gated behind that landing.
- Every later phase — once HTML auth is real, the implicit-singleton shortcut
  goes away and the rest of the codebase stops pretending it has no users.

## 4. Why now

Phase 5 left the JSON / MCP auth surface enforced and documented but the HTML
surface untouched: `before_action :set_current_tenant_and_user` is still a
hardcoded `Tenant.first / User.first` populator. That's harmless in single-user
Beta, but it leaves three things unworkable:

1. **Doorkeeper's consent flow needs a logged-in human.** Step B can't proceed
   without a session model.
2. **The tenant-leak audit (Step C) is incomplete without cookie auth in
   scope.** Half the runtime paths (HTML controllers) bypass any auth check at
   all — there is no auth check, just an implicit pin. The audit is a no-op
   against that surface.
3. **The implicit pin hides bugs.** Any controller that forgets to call
   `before_action :set_current_tenant_and_user` (or whose subclass skips it)
   silently falls through to the application controller's general handling,
   which does nothing helpful. A real auth check fails loud instead.

This step is the smallest move that closes those three gaps. Password reset and
email change are sequenced after — they require SMTP and a mailer, neither of
which exists yet. Splitting them off keeps Step A shippable without the email
rabbit hole.

---

## 5. Locked decisions

- **Session storage: server-side row, signed-cookie token.** A `sessions` table
  holds one row per active session; the cookie holds the session's `token` (not
  its database id, not the user id). Token is `SecureRandom.urlsafe_base64(32)`.
  Server-side resolution looks up the row by token. **Do not** use Rails'
  default in-cookie session store for user identity; cookies hold one
  short-lived opaque token only. Reasoning: server-side rows make remote
  revocation trivial (the Active Sessions list deletes a row; the next request
  from that browser hits a missing row and is logged out), give us a real audit
  trail (IP, UA, last-activity), and leave the door open to future per-session
  expirations / 2FA factor binding. A signed cookie wrapping a user id has none
  of those properties.
- **Cookie attributes.** `httponly: true`, `same_site: :lax`,
  `secure: Rails.env.production? || Rails.env.development?` (dev runs under
  HTTPS via Cloudflare tunnel — the default is `secure: true` in both prod and
  dev; tests run plain HTTP and skip the flag). Cookie name: `pito_session`.
  **Do NOT** wait for Phase 15's hardening pass to add `httponly` / `secure` —
  they are day-one defaults here.
- **Session lifetime.** Session-only (browser close = cookie expires) unless
  "Remember me" was ticked, in which case the cookie's `expires` is set to 30
  days from creation. The server-side row has no `expires_at` in v1; revocation
  is the only end state. (A background sweep for stale rows is a Phase 15 /
  observability concern.)
- **Activity update debounce: 5 minutes.** The `Sessions::ActivityTracker`
  before-action updates `last_activity_at` only if it's been ≥ 5 minutes since
  the last update. Avoids one DB write per request.
- **Login throttle: 10 failed attempts per IP per 5 minutes.** Mirrors the Phase
  5 bearer-token throttle (10 / 5min). Reuse the existing `rack-attack`
  initializer; add a discriminator on the `/login` POST path. Successful logins
  do not count.
- **Generic error message on failed login.** "Invalid email or password." Same
  string regardless of whether the email exists. Never reveal account existence.
- **Logout is `DELETE /session`.** Singular resource (one current session).
  CSRF-protected by Rails defaults. The form is a `button_to` rendering a hidden
  `_method=delete`.
- **Routes:** `/login` (GET, POST) and `/session` (DELETE). Underlying
  controller is `SessionsController` (plural class, singular resource — the
  standard Rails idiom). **Locked over `/sessions/new`.** Reasoning: `/login` is
  the user-facing convention every other product uses; the Settings page lists
  active sessions at `/settings/sessions`, not `/sessions`, so the namespace
  doesn't collide.
- **Active Sessions UI lives at `/settings/sessions`.** Mirrors Phase 5's
  `/settings/tokens` shape — its own dedicated nav entry, its own index page.
  `[ revoke ]` per row goes through the existing `Confirmable` framework. The
  current session row is highlighted with a "(this session)" annotation.
- **No password change form in this step.** Phase 5 left `User` with
  `has_secure_password` plus seeded credentials; the user logs in with the
  seed-time password. Changing it is a Step A.5 / 6A.5 deliverable alongside
  password reset.
- **UA / IP display: store strings, defer prettifying.** `sessions.ip` is
  `inet`; `sessions.user_agent` is `text`. The index renders them raw in v1
  (e.g., "192.168.1.42" / `Mozilla/5.0 (...)`). Optional UA-parser gem is
  captured in Open Questions, not blocking.
- **`Current.session` attribute.** Add to `app/models/current.rb`. The HTML auth
  concern populates it; controllers can read it for the "(this session)"
  annotation in the index.
- **Audit log reuse.** `Sessions::Authenticator` writes the same
  `auth_audit.log` lines as `Api::TokenAuthenticator`. New events:
  `session.login.success`, `session.login.failed`, `session.login.throttled`,
  `session.logout`, `session.revoked`, `session.expired_cookie`. JSON shape
  unchanged from Phase 5 (timestamp, event, user_id, session_id, ip, route,
  result).

---

## 6. In scope

### 6.1 `sessions` table migration

Single migration, reversible:

```ruby
create_table :sessions do |t|
  t.references :user, null: false, foreign_key: true, index: true
  t.references :tenant, null: false, foreign_key: true, index: true
  t.string :token_digest, null: false
  t.inet :ip
  t.text :user_agent
  t.boolean :remember, null: false, default: false
  t.datetime :last_activity_at
  t.datetime :revoked_at
  t.timestamps
end
add_index :sessions, :token_digest, unique: true
add_index :sessions, [ :tenant_id, :user_id ]
```

Notes:

- `token_digest` stores the HMAC-SHA256 of the cookie token using the same
  `:tokens.pepper` credential Phase 5 wired. **Reuse the pepper, do not
  introduce a new one.** Reasoning: keeps the credential surface small; both
  digests are computed by the same helper (`Pito::TokenDigest.call(plaintext)` —
  see §6.5).
- `last_activity_at` is nullable until first activity tick. After login it is
  set in the same request as session creation.
- `revoked_at` is the soft-delete marker; the row stays for audit.
- `tenant_id` is denormalized from `user.tenant_id` so cross-tenant queries (the
  leak audit in Step C) can use the same `BelongsToTenant` pattern as every
  other tenanted model. **Include `BelongsToTenant` on `Session`.**
- No `expires_at` column — the cookie carries the expiration; the row's lifetime
  is "until revoked".

### 6.2 `Session` model

`app/models/session.rb`:

- `belongs_to :user`, `belongs_to :tenant`. Includes `BelongsToTenant`.
- `validates :token_digest, presence: true, uniqueness: true`.
- `validates :user_id, presence: true`.
- Class method `Session.create_for!(user:, ip:, user_agent:, remember:)` →
  returns `[record, plaintext]`. Mirrors `ApiToken.generate!`.
- `revoked?` → `revoked_at.present?`.
- `current?` → `id == Current.session&.id`. Used by the index view.
- `touch_activity!` → `update_columns(last_activity_at: Time.current)` if
  `last_activity_at.nil? || last_activity_at < 5.minutes.ago`. Otherwise no-op.
  **Use `update_columns`** to skip validations and callbacks (and the default
  scope, since the row's tenant is already set; activity ticks should never
  trigger a tenant re-check).

### 6.3 `Sessions::Authenticator` (Rack-level helper)

Plain Ruby class at `app/lib/sessions/authenticator.rb`. Mirrors the shape of
`Api::TokenAuthenticator` so the HTML side has the same "input env, output
Result" contract.

Behavior:

1. Read the `pito_session` cookie value from the request.
2. If missing → return `Result.unauthenticated`.
3. Compute `Pito::TokenDigest.call(plaintext)`.
4. `Session.unscoped.find_by(token_digest: digest)` (`unscoped` because the
   request has no `Current.tenant` yet — the row defines the tenant).
5. If row missing or `revoked?` → return `Result.invalid(reason: ...)`. Audit
   log line written.
6. On success → return `Result.ok(session: row)`. The caller is responsible for
   setting `Current.session / .user / .tenant` and calling
   `session.touch_activity!`.

`Result` is a small struct with `success?`, `failure?`, `session`, `reason`. No
exceptions for control flow.

### 6.4 `Sessions::AuthConcern` (controller concern)

`app/controllers/concerns/sessions/auth_concern.rb`. Replaces the existing
`set_current_tenant_and_user` behavior.

Behavior on every HTML request:

1. Call `Sessions::Authenticator.call(request)`.
2. On success: pin `Current.session = result.session`,
   `Current.user = result.session.user`,
   `Current.tenant = result.session.tenant`. Call
   `result.session.touch_activity!`.
3. On unauthenticated / invalid:
   - If the route requires auth (default), redirect to `/login` with
     `flash[:alert] = "Please log in."` and stash the original URL in the
     session for post-login redirect. **Use the cookie session store for this
     one ephemeral string** —
     `cookies.signed[:pito_intended_url] = request.fullpath`, expires in 10
     minutes. Avoid co-mingling with the auth cookie.
   - If the route is allow-listed (login form, password reset request,
     OAuth-public assets), pass through with `Current` unset.
4. `ensure` block in the surrounding `around_action` calls `Current.reset` to
   mirror Phase 5's discipline.

`ApplicationController` includes the concern globally. Allow-listed controllers
(`SessionsController#new` / `#create`, `PasswordResetsController` once it
exists, public health-check) skip the auth requirement via `skip_before_action`
or an explicit `allow_anonymous` class method on the concern.

`Current.reset` already runs after every spec via the support patch landed in
Phase 5; that stays.

### 6.5 `Pito::TokenDigest` helper (shared)

`app/lib/pito/token_digest.rb`:

```ruby
module Pito
  module TokenDigest
    def self.call(plaintext)
      pepper = Rails.application.credentials.dig(:tokens, :pepper)
      raise "Missing :tokens.pepper credential" if pepper.blank?

      OpenSSL::HMAC.hexdigest("SHA256", pepper, plaintext)
    end
  end
end
```

Refactor: `ApiToken` and `Sessions::Authenticator` both call this helper. Phase
5's inline digest computation moves here as part of this step's implementation.
**One credential, one helper, two callers.**

### 6.6 `SessionsController`

`app/controllers/sessions_controller.rb`. Inherits from `ApplicationController`.
Skips the auth requirement for `new` and `create`.

Actions:

- `new` — renders the login form. Pre-populates `email` from the query param if
  present (e.g., post-password-reset redirect; not used in v1 but the slot is
  there).
- `create` — `POST /login`:
  1. Find `User.find_by(email: params[:email])`. If nil, run a dummy
     `BCrypt::Password.create("noop").is_password?("noop")` to keep timing
     roughly constant. Mark `env["pito.auth_failed"] = true`. Audit log
     `session.login.failed`. Re-render `new` with the generic error.
  2. If `user.authenticate(params[:password])` fails: same dummy-flow and
     re-render path.
  3. On success:
     - `session, plaintext = Session.create_for!(...)`.
     - Set
       `cookies.signed[:pito_session] = { value: plaintext, httponly: true, same_site: :lax, secure: !Rails.env.test?, expires: params[:remember_me] == "yes" ? 30.days.from_now : nil }`.
     - Pull intended URL from `cookies.signed[:pito_intended_url]` or fall back
       to `/`.
     - Delete the intended-URL cookie.
     - Audit log `session.login.success`.
     - Redirect to the captured URL.
- `destroy` — `DELETE /session`:
  1. Mark `Current.session.update_columns(revoked_at: Time.current)`.
  2. Delete the `pito_session` cookie.
  3. Audit log `session.logout`.
  4. Redirect to `/login` with `flash[:notice] = "Signed out."`.

**Yes/no boolean wire format.** The `remember_me` form field follows the
project's hard-rule wire format: `"yes"` / `"no"` strings (not `true` /
`false`). Internal storage is Boolean as always.

### 6.7 Settings → Sessions controller and views

`app/controllers/settings/sessions_controller.rb`. Owner-only is not gated yet
(single-user Beta); concern is added in Step C.

Actions:

- `index` — lists
  `Current.user.sessions.order(revoked_at: :asc, last_activity_at: :desc)`.
  Active sessions first; revoked grayed out, sorted last. Columns: IP,
  user-agent, last_activity_at (humanized via `time_ago_in_words`), remember
  (yes/no), revoked_at (or "(active)" / "(this session)"), `[ revoke ]` link per
  row.
- `destroy` — confirmation flow via `Confirmable` concern. On confirm, sets
  `revoked_at = Time.current`. If the destroyed row IS the current session, also
  delete the cookie and redirect to `/login`. If not, redirect back to the
  index.

Routes:

```ruby
resource :session, only: %i[new create destroy], path_names: { new: "login" }
get "/login" => "sessions#new"
post "/login" => "sessions#create"
delete "/session" => "sessions#destroy"

namespace :settings do
  resources :sessions, only: %i[index destroy]
end
```

(The two route shapes coexist; `/session` is the singleton current-session
endpoint, `/settings/sessions` is the plural management surface.)

### 6.8 Views

- `app/views/sessions/new.html.erb` — login form. Email + password + "Remember
  me" (yes/no select or checkbox; yes/no string at the wire). Generic error
  rendered above the form when present. `[ log in ]` bracketed-link submit
  button per `docs/design.md`. **Monospace inputs**, no red, `[ log in ]` is
  plain bracketed style — login is not destructive.
- `app/views/settings/sessions/index.html.erb` — list of sessions. Table layout
  matching `/settings/tokens` index: name-equivalent column shows the UA, then
  IP, last_activity_at, remember-yes/no, revoked_at, `[ revoke ]` link. Current
  session row gets a `(this session)` annotation; revoked rows grayed and sorted
  last.
- Shared layout chrome: `app/views/layouts/application.html.erb` gains a
  `[ logout ]` bracketed link in the top-right nav (when
  `Current.user.present?`). The link renders as a `button_to` with
  `method: :delete` so it goes through standard CSRF, no JS confirm.

### 6.9 `rack-attack` extension

Extend `config/initializers/rack_attack.rb` with one new throttle:

```ruby
Rack::Attack.throttle("login/failed", limit: 10, period: 5.minutes) do |req|
  req.ip if req.path == "/login" && req.post? && req.env["pito.auth_failed"] == true
end
```

`SessionsController#create` sets `request.env["pito.auth_failed"] = true` on
every failure path. 429 response body:
`{error: "rate_limited", retry_after: <seconds>}` — same shape as the Phase 5
bearer throttle for consistency, even though this endpoint returns HTML
normally. (For HTML requests, the response is a 429 with an HTML body explaining
the throttle and a "try again in N seconds" message. Implementer's choice on
whether to render via a small `shared/_rate_limited.html.erb` partial or inline;
spec accepts either.)

Audit log entry `session.login.throttled` written from inside the controller's
rate-limit catch (rack-attack callback or a `rescue` on
`ActiveSupport::Notifications.subscribe("rack.attack")`).

### 6.10 `Current.session` attribute

`app/models/current.rb`:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :user, :token, :session
end
```

The Phase 5 attributes (`tenant`, `user`, `token`) stay; this step adds
`session`. `Current.reset` already clears all attributes between requests /
specs.

### 6.11 Replace the implicit pin

`app/controllers/application_controller.rb` currently has (or its parent
equivalent):

```ruby
before_action :set_current_tenant_and_user

def set_current_tenant_and_user
  Current.tenant = Tenant.first
  Current.user   = User.first
end
```

Replace with:

```ruby
include Sessions::AuthConcern
```

The concern owns the `before_action`, the unauthenticated redirect, and the
`Current` population. The old method is deleted.

**API controllers untouched.** `Api::*` controllers continue to use
`Api::AuthConcern` (Phase 5). They do not include `Sessions::AuthConcern`. The
shared parent (if any — `ApplicationController`) does NOT auto-include the HTML
concern; it includes a base "auth required, by either path" hook that delegates:
bearer header present → bearer auth; session cookie present → cookie auth;
neither → redirect (HTML) or 401 (JSON). Implementer's call on the exact
dispatch shape; the spec's contract is "JSON requests still 401 without a
bearer; HTML requests still 302 to /login without a session cookie."

### 6.12 Seeds — login-ready user

`db/seeds.rb` already mints a `User` from `:owner` credentials. This step
verifies / adjusts:

1. The seed `User.password=` is set from `:owner.password` (the existing shape).
2. After seed, `bin/setup` echoes the login email + a "use your
   `:owner.password`" reminder to STDOUT. **Do NOT** echo the plaintext password
   — it's in credentials, the user already has it.

No new session row is seeded. Sessions exist only after a real login.

### 6.13 Specs

New / updated:

- `spec/models/session_spec.rb` — `BelongsToTenant` integration, `create_for!`
  returns plaintext exactly once, `touch_activity!` debounce works (≥ 5min
  triggers update, < 5min no-op), `revoked?` / `current?`.
- `spec/lib/sessions/authenticator_spec.rb` — Result shapes for missing cookie,
  invalid token, revoked session, success path.
- `spec/lib/pito/token_digest_spec.rb` — refactored from Phase 5's inline digest
  tests; assert `ApiToken` and `Session` produce identical digests for the same
  plaintext.
- `spec/requests/sessions_spec.rb` — login happy path (cookie set, session row
  created, redirect followed); login wrong password; login non-existent email
  (timing-equivalent + same generic error); logout (cookie deleted, row revoked,
  redirect to `/login`); login with `remember_me=yes` extends cookie expires to
  30 days; intended URL preserved through the round trip; throttle returns 429
  after 11 failures.
- `spec/requests/settings/sessions_spec.rb` — index lists current user's
  sessions, marks current, revoke flow via `Confirmable`, revoking the current
  session signs the user out and redirects to `/login`.
- `spec/system/login_spec.rb` — Capybara end-to-end. Visit `/` unauthenticated →
  redirected to `/login`. Log in. Redirected to `/`. Click `[ logout ]`. Land
  back at `/login`.
- Existing controller specs — every spec that previously relied on the implicit
  `Tenant.first / User.first` pin now needs to either log in via a
  `sign_in_as(user)` request-spec helper OR the `spec/support/tenant_context.rb`
  global hook (which Phase 5 already ships). **Add a `sign_in_as(user)` helper**
  to `spec/support/auth.rb` for explicit authenticated request specs; the global
  hook continues to default `Current.tenant` / `.user` for model and unit specs.

### 6.14 Audit log events

Add the following event types to `docs/auth.md` §8 (the audit log section). Step
C (this phase's docs sub-step) owns the doc edits; Step A just emits them:

- `session.login.success` — `{user_id, session_id, ip, ua, remember}`.
- `session.login.failed` — `{email_attempted, ip, reason}`. Reason is one of
  `unknown_email`, `wrong_password`.
- `session.login.throttled` — `{ip}`.
- `session.logout` — `{user_id, session_id, ip}`.
- `session.revoked` — `{user_id, session_id, revoked_by_session_id}`
  (`revoked_by` differs from `session_id` when the user revokes another session
  from the index).
- `session.cookie.invalid` — `{ip, reason}`. Reason is one of `missing`,
  `unknown_token`, `revoked`.

---

## 7. Out of scope

- **Password reset** — sub-step 6A.5, after SMTP wiring.
- **Email change confirmation flow** — sub-step 6A.5.
- **Password change form (in Settings)** — sub-step 6A.5. (User can change via
  `bin/rails credentials:edit` and re-seed in v1; ugly but acceptable for
  single-user Beta.)
- **Doorkeeper / OAuth server** — Step B.
- **Multi-user invitation flow** — Step C.
- **2FA / TOTP / WebAuthn** — Theta.
- **Email-based magic links** — out of scope, possibly never.
- **Background sweep of stale `sessions` rows** — Phase 11 / 15 (the audit /
  observability phases).
- **UA parser library** — Open Question; if punted, no work here.
- **Public signup** — Theta.
- **`docs/auth.md` updates** — owned by Step C's docs deliverable (which is
  sequenced after the implementations, same as Phase 5 Step C).
- **CSP, HSTS, full security headers** — Phase 15. Cookie hardening (`httponly`,
  `secure`, `samesite`) is in scope here; the rest is not.

---

## 8. Acceptance criteria

- [ ] `sessions` table exists with the columns and indexes in §6.1.
- [ ] `Session` model includes `BelongsToTenant`, `create_for!` returns
      `[record, plaintext]`, `touch_activity!` debounces by 5 minutes.
- [ ] `Pito::TokenDigest.call(plaintext)` is the single source of truth for
      HMAC-SHA256 with `:tokens.pepper`. `ApiToken` and `Session` both use it.
- [ ] `Sessions::Authenticator` returns a Result struct, never raises on
      auth-flow control paths.
- [ ] `Sessions::AuthConcern` populates `Current.session / .user /     .tenant`,
      redirects unauthenticated HTML requests to `/login`, preserves the
      intended URL via a signed cookie, and resets `Current` on response.
- [ ] `GET /login` renders the login form. `POST /login` creates a session on
      valid credentials, sets the `pito_session` cookie (`httponly`,
      `samesite=lax`, `secure` outside test), redirects to the intended URL or
      `/`. Wrong credentials and unknown email both render the generic error
      message.
- [ ] `DELETE /session` revokes the current session and clears the cookie.
- [ ] "Remember me" form field uses `"yes"` / `"no"` wire strings; `"yes"`
      extends cookie expires to 30 days.
- [ ] `/settings/sessions` lists the current user's sessions, marks the current
      row, supports revoke via the `Confirmable` framework. Revoking the current
      session signs the user out.
- [ ] `[ logout ]` link in the top-right nav of every authenticated page;
      renders as `button_to method: :delete`, no JS confirm.
- [ ] `rack-attack` throttles `POST /login` failures at 10 per IP per 5 minutes;
      11th attempt returns 429.
- [ ] Audit log file receives one JSON line per session event listed in §6.14.
- [ ] `Current.reset` runs after every HTML response.
- [ ] All previously-green specs remain green (the `tenant_context` hook + the
      new `sign_in_as` helper preserve fixture ergonomics).
- [ ] New specs cover every path in §6.13.
- [ ] Brakeman, bundler-audit, Dependabot — clean.
- [ ] `Api::*` controllers and `Mcp::RackApp` are unchanged behaviorally —
      bearer-only as before.

---

## 9. Manual playbook

1. `bin/setup` succeeds; `bin/dev` boots both Pumas.
2. Open `/` in a fresh browser → 302 to `/login`. URL bar shows `/login`; an
   `?from=...` or equivalent intended-URL trace is captured (cookie or query
   param).
3. Submit blank form → 422 with the generic error and the form re-rendered. No
   DB writes.
4. Submit wrong password (existing email) → same generic error.
   `tail log/auth_audit.log` shows
   `{"event":"session.login.failed","reason":"wrong_password",...}`.
5. Submit correct credentials → 302 back to `/` (or wherever the intended URL
   pointed). A `pito_session` cookie is set (`httponly`, `secure`,
   `samesite=lax`). Devtools confirms.
6. `bin/rails console` —
   `Session.last.attributes.slice("user_id","ip","remember","last_activity_at","revoked_at")`
   → ip set, remember `false`, last_activity_at within seconds, no revoked_at.
7. Visit `/`, `/channels`, `/videos` — all load. `Current.user` is the seeded
   user (verify by inspecting any page that renders the user's email or
   username).
8. Open a second browser (or incognito), log in same user. Two sessions in
   `Session.count`.
9. `/settings/sessions` — both sessions listed; the one in this browser
   annotated `(this session)`. Click `[ revoke ]` on the OTHER session. Action
   screen renders. Confirm. Land back on the index — the other session is grayed
   and sorted last with a `revoked_at` timestamp.
10. In the OTHER browser, click any link → 302 to `/login`. Audit log shows
    `{"event":"session.cookie.invalid","reason":"revoked"...}`.
11. Click `[ logout ]` from the current browser → 302 to `/login`. Cookie
    cleared. Audit log shows `{"event":"session.logout"...}`.
12. POST `/login` with bad credentials 11 times via curl:
    `for i in $(seq 1 11); do curl -i -X POST -d "email=x@y.z&password=bad" https://app.pitomd.com/login; done`
    → the 11th returns 429.
13. Tick "Remember me", log in, close browser, reopen → still logged in
    (cookie's `expires` is 30 days out; verify in devtools).
14. JSON regression — `curl -i https://app.pitomd.com/api/footages` (no header,
    no cookie) → 401 with `{"error":"missing_token"}`. The cookie session does
    NOT bypass bearer auth.
15. `bundle exec rspec` — green, including new specs.

---

## 10. File-scope inventory

Implementer (Lane 1 rails-impl) touches:

- `db/migrate/<ts>_create_sessions.rb` — new.
- `app/models/session.rb` — new.
- `app/models/current.rb` — add `:session` attribute.
- `app/models/user.rb` — `has_many :sessions, dependent: :destroy`.
- `app/lib/pito/token_digest.rb` — new.
- `app/lib/pito/api_token.rb` (or wherever Phase 5 placed digest helpers) —
  refactor to call `Pito::TokenDigest`.
- `app/lib/sessions/authenticator.rb` — new.
- `app/controllers/concerns/sessions/auth_concern.rb` — new.
- `app/controllers/application_controller.rb` — replace implicit pin with
  concern include, add bearer-or-cookie dispatch helper if needed.
- `app/controllers/sessions_controller.rb` — new.
- `app/controllers/settings/sessions_controller.rb` — new.
- `app/views/sessions/new.html.erb` — new.
- `app/views/settings/sessions/index.html.erb` — new.
- `app/views/layouts/application.html.erb` — add `[ logout ]` link in the nav.
- `app/views/settings/_nav.html.erb` (or equivalent) — add `[ sessions ]` entry
  next to `[ tokens ]`.
- `config/routes.rb` — `/login`, `/session`, namespaced `settings/sessions`.
- `config/initializers/rack_attack.rb` — extend with login throttle.
- `spec/factories/sessions.rb` — new.
- `spec/models/session_spec.rb` — new.
- `spec/lib/sessions/authenticator_spec.rb` — new.
- `spec/lib/pito/token_digest_spec.rb` — new.
- `spec/requests/sessions_spec.rb` — new.
- `spec/requests/settings/sessions_spec.rb` — new.
- `spec/system/login_spec.rb` — new.
- `spec/support/auth.rb` — new (`sign_in_as(user)` helper).
- `spec/support/tenant_context.rb` — adjust if needed so the global hook
  coexists with `sign_in_as`.

Out of bounds for this step:

- `app/mcp/**` — Step B may touch this for OAuth-issued tokens; this step does
  not.
- `app/controllers/api/**` — Phase 5 owns. No changes.
- `db/seeds.rb` — only the `bin/setup` echo line is added; no new seed records.
- `docs/auth.md`, `docs/architecture.md`, `docs/setup.md` — Step C owns the doc
  updates.
- `extras/cli/**`, `extras/website/**` — out of scope; CLI and website do not
  consume the cookie session.

## 11. Open questions

- **Password reset / email change scheduling.** This spec defers both to
  "sub-step 6A.5" gated on SMTP wiring. The user should confirm whether to land
  6A.5 inside Phase 6 (delays the phase, enables full flows) or punt to a Phase
  6.5 polish window (ships 6A faster, leaves a hole until then). The spec
  assumes punt-to-6.5 unless told otherwise.
- **UA parser gem (`useragent`).** Add now for friendly session labels ("Firefox
  on Linux"), or punt to a follow-up entry? The spec writes raw strings in v1
  either way.
- **Cookie `secure` flag in dev.** Spec assumes `secure: true` in dev because
  dev runs under HTTPS via the Cloudflare tunnel. If the user occasionally runs
  `bin/dev` against `http://localhost:3027` directly (no tunnel), `secure: true`
  will silently drop the cookie and log-in won't work. Confirm: is the tunnel
  always on, or do we need a `secure: Rails.env.production?` carve-out?
- **`/login` vs `/sessions/new` route.** Spec locks `/login`. Confirm this
  matches the user's preference — the alternative is the strict Rails-RESTful
  `/sessions/new`.
- **Bearer-or-cookie dispatch shape.** When `ApplicationController` needs to
  handle both auth styles, where does the dispatch live? Two options: (a) HTML
  controllers include `Sessions::AuthConcern`, JSON controllers include
  `Api::AuthConcern`, the parent does nothing; or (b) the parent runs both
  concerns and lets the first one populate `Current` win. Spec assumes (a) —
  explicit per-controller — but flags this for confirmation.
- **`sign_in_as` helper in request specs.** Concrete implementation question for
  the implementer: does the helper set the cookie via
  `ActionDispatch::Cookies::SignedCookieJar` directly, or does it POST to
  `/login` per-spec? Trade-off between speed (direct cookie set) and realism
  (POST round-trip). Spec accepts either; implementer picks.
