# Phase 3 — Auth Foundation

> **Goal:** Establish Beta's auth model from a clean start: `User` and `Tenant`
> schema, multi-tenant-ready columns on every data-holding model, header-based
> JSON authentication shared by both Puma processes, and a unified scoped-token
> model (`ApiToken`) with the full Beta scope catalog. **No login UI in this
> phase.** Single user, single tenant, seeded.

**Depends on:** Phase 2 (Postgres for `jsonb`, `citext`, encrypted columns).

**Unblocks:** Phase 4 (terminal app token auth), Phase 5 (Slack probe auth),
Phase 6 (`website:*` tools), Phase 7 (Google OAuth tied to a User), Phase 12
(login UI built on top of this foundation).

---

## Why Phase 3 is now

Auth schema decisions ripple through every model that holds data. Channels,
videos, tokens, settings, saved views, bulk operations — all need `user_id` and
`tenant_id` columns when multi-tenancy arrives in Theta. Adding those columns
now, while the dataset is seeds only, costs hours; adding them after real
YouTube data and embeddings would cost weeks of careful migration.

Token-based auth with scopes also unifies the surface for every programmatic
client that arrives in later phases:

- Phase 4's terminal app needs to authenticate
- Phase 5's Slack probe needs a token
- Phase 6's in-app landing-page editor needs `website:write` scope
- Phase 7's Google OAuth flow ties tokens to users
- Phase 9's `yt:*` markdown tools need `yt:read`/`yt:write` scopes (the Phase 1
  `dev:*` scopes already exist; this phase formalizes the catalog)

Building it once, well, here means none of those phases needs to invent its own
auth.

This phase also introduces the shared auth concern that **both Puma processes**
consume. Web Puma uses session cookies (added in Phase 12) plus optional bearer
tokens; MCP Puma uses bearer tokens exclusively. Same model, same scope
enforcement, two entry points.

---

## In scope

### Models

**`Tenant`** — `id`, `slug` (citext, unique), `name`, `created_at`,
`updated_at`. Seeded with one tenant for the user.

**`User`** — `id`, `tenant_id`, `email` (citext, unique-per-tenant),
`password_digest` (bcrypt via `has_secure_password`), `name`, `role` (string,
default `"owner"`), `created_at`, `updated_at`. Seeded with the user's account;
password from Rails credentials.

**`ApiToken`** — `id`, `tenant_id`, `user_id`, `name`, `token_digest`,
`last_token_preview` (last 4 chars), `scopes` (jsonb array of scope strings),
`created_at`, `last_used_at`, `revoked_at` (nullable), `expires_at` (nullable).
Each token belongs to a user (and through the user, to a tenant). Scope strings
follow the `namespace:permission` pattern established in `beta.md`'s scope
catalog.

### Multi-tenant columns

Add `tenant_id` (and `user_id` where appropriate) to every existing data-holding
model from the Alpha codebase that survives into Beta. Each migration backfills
existing seeded rows to the seeded tenant + user. Indexes on `tenant_id` for
query performance.

### Scope catalog — the Beta authoritative list

This phase establishes the scope catalog declared in `beta.md`. The catalog
lives in a single Ruby module (`app/models/concerns/scopes.rb` or similar) so
every controller, tool, and spec references one source:

```
dev:read         (already in use from Phase 1)
dev:write        (already in use from Phase 1)
yt:read
yt:write
yt:destructive
website:read     (added in Phase 6 — declared here, no tools yet)
website:write    (added in Phase 6 — declared here, no tools yet)
```

The Phase 1 `dev:*` scopes get formalized into this catalog (no behavioral
change; they were ad-hoc before and are now part of the official list). The
`yt:*` scopes are introduced here and applied to every existing MCP tool that
operates on channels, videos, stats, dashboards, and settings (the relational
tools from the Alpha codebase). The `website:*` scopes are _declared_ in the
catalog now so Phase 6 has them ready, but no `website:*` tools exist yet.

### Tool-to-scope mapping

Every existing MCP tool gets assigned its required scope:

- Read-only tools (list, search, dashboard read) → `yt:read`
- Mutating tools (create, update) → `yt:write`
- Destructive tools (delete, bulk-delete, purge) → `yt:destructive`
- The Phase 1 `dev:*` tools already enforce `dev:read`/`dev:write`

The mapping is documented in `pito/docs/mcp.md` as the authoritative reference.

### Tenant scoping

Introduce a `Current` model (`ActiveSupport::CurrentAttributes`) with `tenant`,
`user`, `token` attributes. Every request — whether to Web Puma or MCP Puma —
sets `Current.tenant` and `Current.user` at the start of the request lifecycle
and resets at the end.

Every tenant-scoped model gets a default scope (or equivalent enforcement) that
filters by `Current.tenant_id`. Cross-tenant queries are not possible through
normal ActiveRecord usage.

The recommended enforcement: a small concern (`belongs_to_tenant` or similar)
that sets
`default_scope { where(tenant_id: Current.tenant_id) if Current.tenant_id }` and
validates `tenant_id` on save. Document the pattern; apply uniformly.

### JSON API auth (shared by both Pumas)

Add `Api::AuthConcern` (or equivalent) that:

- Extracts the bearer token from the `Authorization: Bearer <token>` header
- Looks up the matching `ApiToken` by digest (constant-time comparison)
- Rejects with 401 if missing, invalid, revoked, or expired
- Sets `Current.user`, `Current.tenant`, `Current.token` for the request
- Updates `last_used_at` on success (skip on revoked/expired to avoid leaking
  validity info)

Web Puma applies the concern to JSON endpoints. MCP Puma applies it to all MCP
HTTP transport requests. Both Pumas use the exact same concern — single source
of truth.

The concern includes a tool/controller-level scope check helper:
`require_scope!('yt:write')` raises a structured error if `Current.token` lacks
the required scope. Every MCP tool calls this; every JSON controller action
calls it.

### Settings UI for tokens (minimal)

Token management UI gets a minimal form in this phase: list tokens, generate new
token (name + scope checkboxes), revoke token. Scope picker shows scopes grouped
by namespace. Plaintext token shown once at creation with clear "save now, won't
show again" warning. Phase 12 matures this UI significantly (better picker,
expiry date, sessions, password change, OAuth applications).

### Web sessions remain unchanged

The web UI continues working without login — single-user assumption holds
throughout Beta. Login UI is Phase 12. The web app currently uses the seeded
user implicitly (via a `before_action` setting `Current.user` to
`User.find_by(role: 'owner')`); that implicit session continues. JSON endpoints
and MCP HTTP require explicit bearer tokens.

### Out of scope

- Login form, signup form, session UI (Phase 12)
- OAuth server endpoints for clients — Phase 12 introduces Doorkeeper. Until
  then, tokens are minted via the Settings UI established here.
- Google OAuth for YouTube tokens (Phase 7 — different concern, different model:
  `GoogleIdentity`)
- Multi-tenant admin tooling (Theta)
- Token expiry enforcement automation — the model supports it; UI to set custom
  expiry comes in Phase 12
- Rate limiting beyond a basic Rack::Attack rule for failed lookups —
  comprehensive rate limiting is Phase 15

---

## Plan checklist

### Models and migrations

- [~] Migration: create `tenants` table (`slug` citext unique, `name`,
  timestamps) — delivered in Channel Revamp with `name` only (no `slug`); slug
  deferred
- [~] Migration: create `users` table with `tenant_id` FK, `email` citext
  (unique within tenant), `password_digest`, `name`, `role` (default `'owner'`),
  timestamps — delivered in Channel Revamp with
  `username + email + password_digest` (no `name`, no `role`); email + username
  globally unique (single-column), not scoped to tenant
- [x] `Tenant` model: `has_many :users`, `has_many :api_tokens`, validations on
      slug and name — delivered without `has_many :api_tokens` (no ApiToken in
      this phase) and validates name only
- [~] `User` model: `belongs_to :tenant`, `has_secure_password`, validations,
  `has_many :api_tokens` — delivered without `has_many :api_tokens`; username
  regex `\A[A-Za-z][A-Za-z0-9]*\z` and `find_by_username_or_email` added
- [ ] Migration: add `tenant_id` (and `user_id` where appropriate) to every
      existing data-holding table; backfill existing rows in the same migration
      to the seeded tenant + user (deferred to future Auth Foundation phase —
      only `channels.tenant_id` was added in Channel Revamp;
      videos/playlists/saved_views remain untenanted)
- [~] Add `belongs_to :tenant` to every affected model — only
  `Channel belongs_to :tenant` so far; remaining models deferred
- [ ] Add the `belongs_to_tenant` concern (or equivalent) and apply uniformly
      (deferred to future Auth Foundation phase)
- [ ] Migration: drop the Alpha-era token table (whatever it was called) and
      create `api_tokens` with the full Beta schema. No data preservation needed
      — Alpha tokens are not contracts. (deferred to future Auth Foundation
      phase — `mcp_access_tokens` from a separate MCP HTTP transport phase
      remains in place)
- [ ] `ApiToken` model: associations, token digest, scope validation, expiry
      helper (deferred to future Auth Foundation phase)
- [x] Add `Current` model with `tenant`, `user`, `token` attributes — delivered
      in Channel Revamp; `before_action :set_current_tenant_and_user` populates
      from `Tenant.first` / `User.first` singletons

### Scope catalog

- [ ] Define scope catalog as a single Ruby constant or module — list of valid
      scopes with descriptions (deferred to future Auth Foundation phase)
- [ ] Add `require_scope!(scope)` helper used by both controllers and tools
      (deferred to future Auth Foundation phase)
- [ ] Map every existing MCP tool to its required scope (`yt:read`, `yt:write`,
      or `yt:destructive`) (deferred to future Auth Foundation phase)
- [ ] Phase 1's `dev:*` tools continue to require `dev:read`/`dev:write`; the
      formalization is just listing them in the catalog (deferred to future Auth
      Foundation phase)
- [ ] Declare `website:read` and `website:write` in the catalog (no tools yet —
      Phase 6 adds them) (deferred to future Auth Foundation phase)

### JSON API auth concern

- [ ] Implement `Api::AuthConcern` (or equivalent name) — bearer extraction,
      lookup by digest, scope check, `Current` population (deferred to future
      Auth Foundation phase)
- [ ] Apply to every JSON endpoint in Web Puma's controllers (deferred to future
      Auth Foundation phase)
- [ ] Apply to every MCP HTTP transport endpoint in MCP Puma (deferred to future
      Auth Foundation phase)
- [ ] Constant-time digest comparison (deferred to future Auth Foundation phase
      — partial: McpAccessToken from MCP HTTP transport phase already uses
      HMAC-SHA256 secure compare)
- [ ] Update `last_used_at` on success (deferred to future Auth Foundation phase
      — partial: McpAccessToken already does this)
- [ ] Basic Rack::Attack throttle on failed lookups (5 per minute per IP) — full
      rate limiting is Phase 15 (deferred to future Auth Foundation phase)
- [ ] Specs covering: missing token, invalid token, revoked token, expired
      token, valid token with required scope, valid token without required scope
      (deferred to future Auth Foundation phase)

### Existing MCP tool refactor

- [ ] Each existing MCP tool calls `require_scope!('yt:read')` (or
      write/destructive as appropriate) at the top of its execute method
      (deferred to future Auth Foundation phase — Channel-touching MCP tools
      were refactored for the new shape but no scope enforcement yet)
- [ ] Each tool sets `Current.tenant` and `Current.user` from the resolved token
      (or relies on the auth concern having done so) (deferred to future Auth
      Foundation phase — Current is set from `Tenant.first` / `User.first`
      singletons in Channel Revamp)
- [ ] Tool specs assert scope rejection: a token without the right scope is
      rejected before any work happens (deferred to future Auth Foundation
      phase)

### Seeds

- [x] Seed one Tenant (`slug: "primary"`, `name: <user's name or handle>`) —
      delivered with `name` only (no slug); seed reads from `:owner` credentials
      block
- [~] Seed one User (the user's own account, role `owner`, password from Rails
  credentials) — delivered with `username + email + password_digest` from
  `:owner` credentials; no `role` column
- [ ] Seed a default `ApiToken` for development with
      `dev:read dev:write yt:read yt:write` scopes (no `yt:destructive` by
      default; user opts in) (deferred to future Auth Foundation phase)
- [~] All existing seed records get `tenant_id` and `user_id` assigned to the
  seeded tenant + user — only Channel seeds got `tenant_id`;
  videos/playlists/saved_views remain untenanted

### Settings UI (minimal)

- [ ] List tokens (name, scopes, last-used, created-at, revoke button) (deferred
      to future Auth Foundation phase)
- [ ] Generate token form: name input + scope checkboxes grouped by namespace
      (deferred to future Auth Foundation phase)
- [ ] Token creation response shows plaintext exactly once with a clear "save
      now, won't show again" notice (deferred to future Auth Foundation phase)
- [ ] Revoke action sets `revoked_at`; subsequent uses of the token return 401
      (deferred to future Auth Foundation phase)
- [ ] Apply the existing Pito design system (bracketed buttons, monospace,
      dark/light theme) (deferred to future Auth Foundation phase)

### Documentation

- [ ] Update `pito/docs/architecture.md`: auth section, multi-tenant scoping
      pattern, token lifecycle, the `belongs_to_tenant` concern (deferred to
      future Auth Foundation phase — Channel Revamp's tenant-scoping pass should
      also touch this file in a follow-up docs pass)
- [ ] Update `pito/docs/mcp.md`: scope requirements per tool, scope catalog
      reference (deferred to future Auth Foundation phase — note: mcp.md is also
      stale on Channel shape after Channel Revamp; flagged for follow-up)
- [ ] Add `pito/docs/auth.md`: authoritative reference for the auth model —
      User, Tenant, ApiToken, scopes, JSON API auth flow, dual-Puma auth sharing
      (deferred to future Auth Foundation phase)
- [ ] Update `pito/docs/design.md` with the token UI patterns if visually
      distinct from existing forms (deferred to future Auth Foundation phase)

### Validation

- [x] All Alpha specs continue to pass with `Current.tenant` populated in test
      setup helpers — Channel Revamp set `Current.tenant = Tenant.first` via
      `before_action`; specs green
- [~] New specs for `Tenant`, `User`, `ApiToken`, scope enforcement, `Current`
  lifecycle, default scoping — Tenant + User specs delivered; ApiToken / scope /
  default-scoping specs deferred
- [ ] Cross-tenant leak spec: create a second tenant + user via factory; assert
      all queries scoped to `Current.tenant` exclude the other tenant's records
      (deferred to future Auth Foundation phase — single-tenant only for now)
- [x] Web UI works as before (the seeded user is implicitly current) — verified
      in Channel Revamp manual playbook
- [ ] MCP HTTP requires valid token with the right scope; rejects insufficient
      scope (deferred to future Auth Foundation phase — MCP HTTP currently uses
      `McpAccessToken` from a separate phase, no scopes)
- [ ] Both Web Puma and MCP Puma honor the same auth concern (deferred to future
      Auth Foundation phase)
- [x] Brakeman, bundler-audit, Dependabot — clean — verified by Channel Revamp
      security-auditor
- [ ] `pito/docs/design.md` updated for any UI changes (deferred to future Auth
      Foundation phase)

---

## Specs requirements

- Model specs for `Tenant`, `User`, `ApiToken`: validations, associations,
  password hashing, token digest generation/comparison, expiry handling.
- Scope enforcement spec: each scope grants the tools/endpoints it should and
  denies others.
- `Current` attribute spec: set/unset across requests; no leakage between tests
  (RSpec must reset `Current` between tests via a global `after(:each)`).
- Default scoping spec: querying a tenant-scoped model without `Current.tenant`
  either raises or returns empty (pick one and document — recommend **raise** so
  missing `Current` is loud).
- Cross-tenant leak spec: create two tenants/users via factory; assert no
  cross-access through any tenant-scoped model.
- API auth spec: missing → 401, invalid → 401, revoked → 401, expired → 401,
  valid → 200 + `Current.user` set.
- Both-Pumas request spec: at least one spec per Puma that exercises the auth
  concern end-to-end (Web Puma JSON endpoint; MCP Puma tool call).

## Security requirements

- Tokens: 32 bytes of randomness (`SecureRandom.urlsafe_base64(32)`). Digested
  with bcrypt or sha256+pepper (pick one and document; bcrypt is heavier but
  more standard, sha256+pepper is faster). Plaintext shown once at creation.
  Constant-time comparison on every lookup.
- Passwords: bcrypt via `has_secure_password`, cost factor 12. Minimum length 12
  characters.
- Default scoping enforced at the model level. A controller bug must not leak
  data across tenants.
- Brakeman: no new warnings.
- bundler-audit: clean. Verify any auth-related gem additions (bcrypt is already
  present from Alpha).
- Dependabot: review.
- Audit log: record every token creation and revocation to a dedicated audit log
  file (`log/auth_audit.log`).
- `pito/docs/design.md`: token list and creation form documented if they differ
  from existing form patterns.

## Manual testing checklist

The user runs through this before commit:

1. `bin/rails db:reset` — fresh DB, migrations run, seeds populate without
   errors
2. Verify in console: `Tenant.count == 1`, `User.count == 1`,
   `ApiToken.count >= 1`
3. Web UI: visit `/`, `/channels`, `/videos`, `/saved_views`, `/settings` — all
   work as before (seeded user is implicitly current)
4. Settings → Tokens → generate a token named `read-only` with only `yt:read`
5. `curl -H "Authorization: Bearer <token>" https://app.pitomd.com/api/channels.json`
   — returns channels
6. `curl -X POST -H "Authorization: Bearer <token>" https://app.pitomd.com/api/channels.json -d '...'`
   — returns 403 (insufficient scope)
7. Generate token with `yt:read yt:write` — POST succeeds
8. Generate token with `yt:read yt:write yt:destructive` — DELETE succeeds
9. From Claude desktop or mobile, configure MCP connector pointed at
   `mcp.pitomd.com` with a token that has `yt:read yt:write` — read/write tool
   calls succeed; destructive calls rejected
10. Revoke a token via Settings UI; immediately retry — 401
11. From mobile-Claude with the Phase 1 dev-token (`dev:read dev:write`), call
    `dev:list_files` — succeeds; call any `yt:*` tool — rejected
12. `bundle exec rspec` — green, including the cross-tenant leak spec

---

## Challenges to anticipate

- **`Current` attribute leakage in tests.** RSpec must reset `Current` between
  tests, otherwise a test that sets `Current.tenant` pollutes later tests. Add a
  global `after(:each) { Current.reset }` in `rails_helper.rb`.
- **Existing seed code.** Alpha seeds may not assume a `tenant_id`. Update seed
  scripts to set `Current.tenant` first or pass `tenant:` explicitly. Same for
  any factory definitions.
- **MCP stdio transport bypass.** If an stdio MCP server still exists from
  Alpha, it bypasses HTTP auth entirely — the stdio process is implicitly
  trusted (local-only). Document this clearly. The recommendation is to keep
  stdio for local Claude Code use; HTTP transport is for remote clients.
- **Default scope behavior on missing `Current`.** Two options: raise (safer;
  bugs are loud) or return empty (more forgiving; bugs are silent). Recommend
  raise. Set `Current.tenant` in a `before_action` that runs on every controller
  (web pages use the seeded user; JSON endpoints use the auth concern's resolved
  user).
- **Existing tokens from Alpha.** Per `beta.md`, Alpha tokens are not contracts.
  Drop them. The migration creates the new `api_tokens` table fresh; the user
  generates new tokens through the Settings UI.
- **Both Pumas must reload after the migration.** After running migrations, both
  Puma processes need to restart to pick up the new schema. `bin/dev` restart
  handles this automatically; in production (Phase 16), Kamal handles it.
- **`citext` extension.** Postgres supports `citext` natively but it requires
  `enable_extension :citext` in a migration. Add this here (Phase 2 added
  pgcrypto and vector; this phase adds citext for emails and slugs).

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user is OK with the Alpha token table being dropped and replaced. (Per
   `beta.md`: Alpha tokens are not contracts.)
2. Default seed user role is `owner`. (Confirm or alter.)
3. Password hashing algorithm: bcrypt with cost factor 12. (Alternative: argon2
   — heavier, likely overkill for single-tenant. Stick with bcrypt unless user
   objects.)
4. Default scoping behavior on missing `Current.tenant`: **raise** (recommended;
   bugs are loud) vs return empty (more forgiving). Recommend raise.
5. Token digest method: bcrypt vs sha256+pepper. Recommend sha256+pepper for
   token-lookup performance (bcrypt makes every API call slow); confirm.
6. Both Puma processes will be restarted after migrations are applied.
