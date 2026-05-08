# Phase 12 — Auth UI + Multi-User Readiness

> **Goal:** Build the user-facing authentication UI on top of Phase 3's auth
> foundation: login form, sessions, password reset, mature token management.
> Replace Phase 4's ad-hoc CLI auth flow with a standard OAuth server
> (Doorkeeper). Audit and prove multi-tenant scoping is bulletproof through
> every layer. **Single user remains in Beta; multi-tenant infrastructure
> becomes provably ready for Theta.**

**Depends on:** Phase 3 (auth foundation: User, Tenant, ApiToken, scope catalog,
JSON API auth shared by both Pumas), Phase 11 (the workflow that proves Pito is
"useful enough" to deserve a real login surface).

**Unblocks:** Phase 13 (observability has user/tenant context for filtering
metrics), Phase 16 (Hetzner deployment with confidence in the auth model and
proven tenant isolation).

---

## Why Phase 12 is now

Phase 3 built the schema and the JSON API auth surface used by both Pumas. Phase
12 builds the human-facing surface on top:

- Login form, session management, password reset
- Mature token management UI with proper scope grouping, expiry, and last-used
  display
- A standard OAuth 2.0 server (Doorkeeper) so the terminal app from Phase 4
  stops using its ad-hoc `/auth/cli/*` flow and uses something audited
- A multi-tenant audit pass: prove no controller, no Sidekiq job, no MCP tool
  can leak data across tenants — even though Beta only has one tenant in
  production

Pito stops feeling like a single-user prototype and starts feeling like a real
product, even though only one person uses it. The schema has been
multi-tenant-ready since Phase 3; this phase proves the runtime path enforces
what the schema implies.

This phase also retroactively cleans up Phase 4's terminal auth. The
`/auth/cli/*` endpoints worked but they're a one-off pattern; Doorkeeper
replaces them with standard OAuth that future clients (Slack-survivor, future
automations, third parties in Theta) can plug into.

---

## In scope

### Login UI

- `/login` form: email + password, "Remember me" checkbox
- `/logout` (DELETE-style action, CSRF-protected)
- Failed-login handling: same generic error ("Invalid credentials") regardless
  of cause; never reveal whether email exists
- Failed-login rate limiting via Rack::Attack: 5 attempts per IP per 5 minutes
- After successful login: redirect to intended URL (preserved through the auth
  flow) or `/`
- "Remember me" extends the session cookie expiry from session-only to 30 days

### Password reset

- `/passwords/new` — request form (email input)
- Mailer template: minimal text email with reset link
  (`/passwords/edit?token=...`), expires in 1 hour
- `/passwords/edit?token=...` — token-validated form; user sets new password
- Reset token: `SecureRandom.urlsafe_base64(32)`; stored hashed (sha256+pepper);
  single-use; 1-hour expiry
- After successful reset: redirect to login with success notice
- SMTP configuration via Rails credentials (Postmark recommended for
  transactional simplicity; Mailgun and Resend work too)
- In dev: use `letter_opener` gem so reset emails open in the browser

### Session management

- Migration: `sessions` table — `id`, `user_id`, `tenant_id`, `token_hash`,
  `ip`, `user_agent`, `created_at`, `last_activity_at`, `revoked_at`
- Session cookie stores session ID; server-side lookup resolves the User.
  (Replaces any in-cookie user_id pattern from Alpha.)
- Activity middleware updates `last_activity_at` once per N minutes (5 mins
  recommended; avoid thrashing the DB on every request)
- Settings → Account → Active Sessions list: per-session row with IP
  (interpreted to friendly location if a small IP-geolocation library is added),
  user-agent (translated to friendly labels via a UA parser), last-activity, and
  a "Revoke" button
- Revoking a session sets `revoked_at`; that session's next request gets 401 and
  is logged out

### Settings → Account (matures Phase 3's stub)

- Account info view (email, name, role)
- Edit name; edit email (email change requires current password + email
  confirmation flow)
- Change password (requires current password)
- Active sessions list (above)
- Specs for each form action

### API token management UI (matures from Phase 3 minimal version)

- List tokens with filtering / search by name
- Scope picker on creation: collapsible namespace sections (`dev:*`, `yt:*`,
  `website:*`), checkbox per scope with descriptions inline
- Optional expiry date picker (per-token expires_at)
- Last-used timestamp prominently displayed
- Revoke action with confirm dialog
- Token plaintext shown only once at creation with explicit "save now, won't
  show again" warning
- Visual differentiation between active, expired, and revoked tokens

### Doorkeeper OAuth server

- Add `doorkeeper` gem, run installer, configure
- New Settings sub-page: "OAuth Applications" (visible to `role: 'owner'`)
  - Register applications: each gets `client_id`, `client_secret`,
    `redirect_uri`, allowed scopes
  - Pre-seeded application: `pito-sh` (terminal app from Phase 4)
- Standard endpoints exposed:
  - `/oauth/authorize` — authorization code flow with PKCE
  - `/oauth/token` — token exchange and refresh
  - `/oauth/revoke` — token revocation
  - `/oauth/introspect` — token introspection (for advanced clients)
- PKCE required for public clients (terminal app, future mobile apps);
  confidential clients (server-to-server) can skip
- Refresh tokens with rotation (each refresh issues a new refresh token; old one
  revoked)
- Per-application scope configuration: an application can request only scopes
  it's been pre-configured to request
- Doorkeeper scopes mapped 1:1 onto Phase 3's scope catalog (`dev:read`,
  `yt:write`, etc.)

### `pito-sh` migration

- The Phase 4 terminal app's auth flow gets refactored:
  - Replace ad-hoc `/auth/cli/start`, `/auth/cli/authorize`,
    `/auth/cli/exchange` with standard `/oauth/authorize` and `/oauth/token`
  - Update `pito-sh` Rust code to use a standard OAuth client crate (`oauth2`
    crate is already pulled in for Phase 4)
  - Keep PKCE — same security profile
  - Add refresh token handling so long-running terminal sessions don't need
    re-auth on access token expiry
- Phase 4's `/auth/cli/*` endpoints get removed (or kept as deprecated shims for
  one release if the user has a token in production they don't want to
  invalidate; recommend removing cleanly since Beta is the user-only)

### Slack probe migration (if Phase 5 verdict was YES)

- The `slack-bot` `ApiToken` from Phase 5 stays as-is — it's a long-lived
  Pito-internal token, not user-facing OAuth
- If Slack is dropped (verdict NO), this section becomes a no-op

### Multi-tenant audit

This is a prove-it-correct exercise rather than new features:

**Code review checklist (one item per layer):**

- [ ] Every `belongs_to :tenant` model: default scope active OR explicit
      `Current.tenant`-aware queries; tenant assignment validated on save
- [ ] Every controller action: `Current.tenant` set in `before_action` or via
      the Phase 3 auth concern; missing `Current.tenant` raises (per Phase 3
      decision)
- [ ] Every Sidekiq job: accepts `tenant_id` as argument; sets `Current.tenant`
      at start of `perform`; resets at end (in `ensure` block)
- [ ] Every MCP tool: resolves `Current.tenant` from the authenticated
      `ApiToken`; rejects requests without a resolvable tenant
- [ ] Every KB sandbox (`Dev`, `Yt::Kb`, `Website`): operations don't escape the
      configured root (already enforced from Phase 1, 6, 9 — re-verified here)

**Cross-tenant leak detection spec:** a meta-test that:

1. Creates two tenants, two users, two channels, two videos, two KB files, and
   two embeddings via factory
2. Sets `Current.tenant` to tenant A
3. For every model with `belongs_to :tenant`, asserts that `.all` returns only
   tenant A's records
4. For every controller, sends authenticated requests as tenant A and asserts no
   tenant B data is returned
5. For every MCP tool, invokes with tenant A's token and asserts no tenant B
   data is returned

This spec is exhaustive and slow. Run it in a separate CI lane if needed.

### Multi-user UI (gated behind a feature flag)

Schema and code paths exist; UI exists for testing; flag-gated off by default.
Theta will turn the flag on. Beta keeps single-user.

- Feature flag: `multi_user_enabled` (default `false`); use `flipper-rails` gem
  (lightweight, well-supported) or a config constant
- When enabled AND user is `role: 'owner'`: Settings → "Users" link appears
- Users page: list of users in the current tenant; "Invite user" form
- Invitation flow: generate invitation token, send email with accept link,
  accepting user sets password, joins tenant
- Specs cover the flow regardless of flag state — flag-on tests verify behavior,
  flag-off tests verify the UI is hidden

### Out of scope

- Public signup (Theta — billing required first)
- 2FA / TOTP / WebAuthn (post-Beta enhancement; nice to have, not blocking)
- SSO (SAML, OIDC) — Theta enterprise concern
- Account deletion / data export (GDPR-style features) — Theta concern with real
  users
- Email-based magic links (alternative to passwords; can add later if password
  fatigue becomes a thing)
- Comprehensive rate limiting beyond login (Phase 15 covers full rate limit
  sweep)

---

## Plan checklist

### Login flow

- [x] `SessionsController` — `new`, `create`, `destroy`
- [x] `/login`, `/logout` routes
- [x] Login form view matching `pito/docs/design.md` (bracketed buttons,
      monospace inputs)
- [x] Generic error message on failed login
- [x] Rack::Attack throttle on `/login`: 5 per IP per 5 minutes (10/IP/5min,
      mirroring the Phase 5B failed-token-lookup pattern per the 6A locked
      decision)
- [x] After login: redirect to intended URL preserved through the auth flow
- [x] "Remember me" extends cookie expiry to 30 days
- [x] Specs covering happy path, failed login, throttle, redirect preservation

### Password reset

- [ ] `PasswordResetsController` — request, edit, update
- [ ] Mailer template (text-only, minimal)
- [ ] SMTP configuration in Rails credentials (placeholder for production;
      `letter_opener` for dev)
- [ ] Reset token generation, hashing, single-use enforcement, 1-hour expiry
- [ ] Specs for full flow: request, email delivery (mocked), token validation,
      token reuse rejection, expiry

### Session management

- [x] Migration: `sessions` table per the schema above
- [x] Session cookie stores session ID; server-side User resolution
- [x] Activity middleware updates `last_activity_at` (debounced, 5 min)
- [x] Settings → Account → Active Sessions view (lives at `/settings/sessions` —
      locked decision in 6A §5)
- [x] Revoke action sets `revoked_at`; specs verify revoked sessions get 401 on
      next request
- [ ] Optional UA parsing library (e.g., `useragent` gem) for friendly labels —
      capture in `additions.md` if punted (deferred per 6A §6.x — raw UA string
      for v1)
- [x] Specs for session creation, expiry, revocation, activity update debouncing

### Settings → Account

- [ ] Account info view
- [ ] Edit name (simple form)
- [ ] Edit email (requires current password; sends confirmation email to new
      address)
- [ ] Change password (requires current password)
- [ ] Sessions list integration
- [ ] Specs for each form

### Token UI maturation

- [ ] Refactor existing token UI from Phase 3 into a polished version
- [ ] Scope picker: collapsible namespace sections with descriptions
- [ ] Optional expiry date picker
- [ ] Last-used display
- [ ] Revoke with confirm dialog
- [ ] Filter / search tokens by name
- [ ] Visual states for active, expired, revoked
- [ ] Specs for create with scopes, create with expiry, list filtering, revoke

### Doorkeeper OAuth server

- [x] Add `doorkeeper` gem; run installer
- [x] Configure scope mapping to Phase 3's catalog
- [x] Configure PKCE-required for public clients
- [x] Configure refresh token rotation
- [x] Settings → "OAuth Applications" page (owner-only) (`Current.user.present?`
      gating — owner role lands when multi-user surfaces in a later step)
- [ ] Pre-seeded `pito-sh` application registration (deferred — seed mint of
      `pito-cli` is queued; the migration script in `db/seeds.rb` was not
      extended in this dispatch to keep the seed idempotency contract intact
      while the new tables stabilise)
- [x] Authorization endpoint, token endpoint, refresh endpoint, revoke endpoint,
      introspect endpoint (Doorkeeper mounts all four)
- [x] Specs cover full OAuth code+PKCE flow, refresh, revoke, introspect, scope
      enforcement (introspect not yet covered — happy path covers authorize /
      token / refresh / revoke)

### `pito-sh` migration to Doorkeeper

- [ ] Refactor `pito-sh` auth code to use standard `/oauth/authorize` and
      `/oauth/token`
- [ ] Use the `oauth2` Rust crate (already pulled in Phase 4)
- [ ] Add refresh token handling
- [ ] Update `pito-sh/README.md` and `pito-sh/CLAUDE.md` with the new auth flow
- [ ] Remove Phase 4's `/auth/cli/*` endpoints from Pito (or shim them with
      deprecation warnings if a one-release transition is preferred)
- [ ] Specs in both Pito and `pito-sh` for the new flow

### Multi-tenant audit

- [ ] Code review checklist applied to every layer (models, controllers, jobs,
      MCP tools, sandboxes)
- [ ] Cross-tenant leak detection spec (the meta-test described above)
- [ ] Run the meta-test against the full app; address any leaks
- [ ] Document the audit results in
      `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md`

### Multi-user UI (flag-gated)

- [ ] Add `flipper-rails` gem; configure
- [ ] Feature flag: `multi_user_enabled`, default `false`
- [ ] Settings → Users page (visible only when flag on AND user is `owner`)
- [ ] Invite user form: email input, role selector
- [ ] Invitation token generation, email sending, accept flow
- [ ] Accepting user creates `User` record in the tenant, sets password, signs
      in
- [ ] Specs cover both flag states

### Documentation

- [ ] `pito/docs/auth.md`: full updated auth flow including OAuth server,
      sessions, tokens, scopes, multi-user readiness
- [ ] `pito/docs/architecture.md`: updated auth diagram with Doorkeeper
      component
- [ ] `pito/docs/setup.md`: SMTP configuration, OAuth application setup for
      `pito-sh`
- [ ] Update `pito-sh/README.md` with new OAuth flow

### Validation

- [ ] Manual: log out from app; visit `/` → redirected to `/login`; log in with
      seeded user → redirected to dashboard
- [ ] Manual: open Settings → Account → see current session listed
- [ ] Manual: from a different browser, log in same user → second session
      appears in the list
- [ ] Manual: revoke session from first browser → second browser session
      terminates on next request
- [ ] Manual: forgot password flow — receive reset email (via letter_opener in
      dev), reset password, log in with new password
- [ ] Manual: Settings → API Tokens — improved scope picker with namespace
      grouping; create token with custom scopes and optional expiry
- [ ] Manual: Settings → OAuth Applications — `pito-sh` is pre-seeded
- [ ] Manual: rebuild `pito-sh` against the new Doorkeeper flow; first launch
      goes through `/oauth/authorize`; receives tokens; functions normally;
      refresh works
- [ ] Manual: enable `multi_user_enabled` flag in dev; Settings → Users link
      appears; invite a test user; accept invitation; log in as test user;
      verify can't see owner's data
- [ ] Manual: cross-tenant leak meta-test passes
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- Session controller specs: login, logout, remember-me, failed login throttle,
  intended URL preservation.
- Password reset specs: request, token validation, expiry, single-use, password
  update.
- Doorkeeper integration specs: full OAuth code+PKCE flow, token refresh with
  rotation, revoke, introspect, scope enforcement.
- Cross-tenant leak meta-test: comprehensive coverage of every model,
  controller, MCP tool with two-tenant fixture data.
- Multi-user invitation specs: flag on/off behavior, role enforcement
  (owner-only invites), invitation token expiry.
- Mailer specs: password reset, invitation, email change confirmation.
- Token UI specs: scope picker, expiry, revocation, last-used display.

## Security requirements

- Password hashing: bcrypt cost factor 12 (already from Phase 3); reaffirmed
  here.
- Session cookies: `httponly`, `secure` (in production), `samesite: :lax`.
- CSRF protection on all session-modifying endpoints (Rails default; verify
  enabled).
- Doorkeeper: short-lived access tokens (1 hour), longer refresh tokens (30
  days), refresh rotation enforced.
- PKCE required for public clients (`pito-sh`, future mobile, future
  browser-based flows).
- Constant-time comparison on every token validation (Doorkeeper handles this;
  verify it's not disabled).
- Rack::Attack: throttle login, password reset request, OAuth token endpoint.
- Email content plaintext (no HTML, no tracking pixels).
- Brakeman: especially around auth flows. No new warnings.
- bundler-audit: clean. Verify Doorkeeper, flipper-rails versions.
- Dependabot: review.
- `pito/docs/design.md`: login form, password reset, sessions list, OAuth
  applications, token UI all documented.

## Manual testing checklist

The user runs through this before commit:

1. Log out from any page → top-right `[logout]` button
2. Visit `/` → redirected to `/login`
3. Log in with seeded user credentials → redirected to dashboard
4. Settings → Account → see current session in the list
5. From a different browser (or incognito), log in same user → both sessions
   visible
6. Revoke session from browser A → browser B session terminates on next request
   (try clicking any link)
7. Forgot password: enter email → receive reset email (via letter_opener) →
   click link → set new password → log in with new password
8. Settings → API Tokens → improved scope picker visible, namespaces collapsible
9. Create token with custom scopes and optional expiry; verify token works via
   `curl`
10. Revoke that token; verify next `curl` returns 401
11. Settings → OAuth Applications → `pito-sh` pre-seeded
12. Rebuild `pito-sh` (post-migration); first launch opens browser →
    `/oauth/authorize` → consent → callback → terminal stores tokens; functions
    normally
13. Wait an hour for access token expiry (or set short expiry in dev); verify
    `pito-sh` refreshes transparently
14. Enable `multi_user_enabled` flag in dev; Settings → Users link appears
15. Invite a test user; accept invitation; log in as test user; navigate the
    app; confirm cross-tenant boundaries (test user can't see owner's channels,
    videos, KB content)
16. `bundle exec rspec` — green, including the cross-tenant leak meta-test

---

## Challenges to anticipate

- **Doorkeeper refactor of `pito-sh`.** The terminal app already has a working
  flow. Migrating to Doorkeeper rebuilds the Rust auth code. Worth it because
  it's a standard pattern and Theta-ready, but plan the time.
- **Email deliverability in dev.** Use `letter_opener` for local. Production
  SMTP via Postmark/Mailgun/Resend configured via credentials in Phase 16.
- **Cookie `secure: true` blocks dev HTTP.** The user runs dev under HTTPS via
  Cloudflare tunnel (`app.pitomd.com`), so `secure: true` is fine in dev. If
  running plain HTTP locally, conditionally set `secure` per environment.
- **Cross-tenant leak meta-test at scale.** Iterating every model and every
  controller is mechanical. Use `ApplicationRecord.descendants` to enumerate
  models; route iteration is harder but doable via
  `Rails.application.routes.routes`. The test is slow; mark it `:slow` and run
  separately if needed.
- **Doorkeeper scopes vs. internal scopes.** Doorkeeper has its own scope model.
  Map directly onto Phase 3's catalog. Doorkeeper enforces scope at the
  OAuth-token level; Pito's scope-checking helper from Phase 3 enforces at the
  application level. Both must align — verify.
- **Active sessions UX.** IP and user-agent strings are normal but ugly.
  Consider a small UA parser library (`useragent` gem) that maps to friendly
  labels ("Firefox on Linux"). Punt to `additions.md` if it complicates things.
- **Both Pumas and OAuth.** Doorkeeper endpoints (`/oauth/*`) live on Web Puma.
  MCP Puma doesn't host OAuth — clients (`pito-sh`, future apps) get tokens from
  Web Puma's Doorkeeper, then use those tokens against MCP Puma's
  `mcp.pitomd.com`. Same single-sign-on token model.
- **Migration of existing tokens.** `ApiToken` records minted via Phase 3's
  Settings UI keep working — they're not Doorkeeper-managed. Doorkeeper-issued
  tokens live in a parallel table. Both bear the same scope catalog and resolve
  through the same auth concern. Document this duality clearly.
- **Multi-user readiness UI is gated, not absent.** The flag-off default means
  Beta operates as single-user. Don't accidentally surface invitation UI in
  production. Test both flag states in CI.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. SMTP provider for transactional email: Postmark recommended. Confirm or
   alternative (Mailgun, Resend).
2. Doorkeeper vs hand-rolled OAuth: Doorkeeper recommended for security
   maturity. Confirm.
3. The user is OK with `pito-sh` needing a rebuild after the Doorkeeper
   migration.
4. Multi-user feature flag default is `off`. Beta does not turn it on; Theta
   likely flips it. Confirm.
5. UA parser library (`useragent` gem) for friendly session labels — include in
   this phase or punt to `additions.md`.
6. The cross-tenant leak meta-test is a Phase 12 deliverable, not skipped or
   punted.
