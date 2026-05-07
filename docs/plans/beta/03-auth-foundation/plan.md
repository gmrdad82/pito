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

- [x] Migration: create `tenants` table (`slug` citext unique, `name`,
      timestamps) — Channel Revamp delivered name-only; 5A added `slug`
      (citext, unique, NOT NULL) via
      `20260507000001_add_slug_to_tenants.rb` and the matching seed
      backfill from `:owner.tenant_slug` (fallback `"primary"`)
- [x] Migration: create `users` table with `tenant_id` FK, `email` citext
      (unique within tenant), `password_digest`, `name`, `role` (default
      `'owner'`), timestamps — delivered in Channel Revamp with
      `username + email + password_digest`. 5A formally drops `name` and
      `role` from the spec (single-user world), and locks
      `email`/`username` global uniqueness as a deliberate departure
      revisited at Theta multi-tenancy
- [x] `Tenant` model: `has_many :users`, `has_many :api_tokens`, validations on
      slug and name — Channel Revamp delivered associations + name validation;
      5A adds `slug` validation (presence, format, length, uniqueness via
      citext); 5B added `has_many :api_tokens` via the rename
- [~] `User` model: `belongs_to :tenant`, `has_secure_password`, validations,
  `has_many :api_tokens` — delivered without `has_many :api_tokens`; username
  regex `\A[A-Za-z][A-Za-z0-9]*\z` and `find_by_username_or_email` added
- [x] Migration: add `tenant_id` (and `user_id` where appropriate) to every
      existing data-holding table; backfill existing rows in the same migration
      to the seeded tenant + user (delivered in 5A — videos, playlists,
      playlist_items, video_stats, video_uploads, saved_views, bulk_operations,
      bulk_operation_items each get the three-step add-reference / backfill /
      not-null sequence. `footages.tenant_id` was tightened from nullable to
      NOT NULL in the same batch. `mcp_access_tokens` → `api_tokens` got its
      `tenant_id` (plus `user_id`, scopes, expires_at) from 5B's rename
      migration)
- [x] Add `belongs_to :tenant` to every affected model — delivered in 5A via
      the `BelongsToTenant` concern (next checkbox); the concern declares the
      association so every tenanted model gets it uniformly
- [x] Add the `belongs_to_tenant` concern (or equivalent) and apply uniformly
      (delivered in 5A — `app/models/concerns/belongs_to_tenant.rb` declares
      `belongs_to :tenant`, validates `tenant_id` presence, and a
      `default_scope` keyed on `Current.tenant_id` that raises
      `BelongsToTenant::TenantContextMissing` when Current is unset.
      Included in: Channel, Video, Playlist, PlaylistItem, VideoStat,
      VideoUpload, SavedView, BulkOperation, BulkOperationItem, Project,
      Collection, Game, Footage, Note, Timeline, ProjectReference. Tenant
      and User intentionally do NOT include it.)
- [x] Migration: drop the Alpha-era token table (whatever it was called) and
      create `api_tokens` with the full Beta schema. No data preservation needed
      — Alpha tokens are not contracts. (5B: `mcp_access_tokens` was renamed
      and extended via two migrations rather than dropped — preserves the
      working rake-task CRUD path; spec §5 locks this rename-and-extend path)
- [x] `ApiToken` model: associations, token digest, scope validation, expiry
      helper (delivered in 5B: `belongs_to :tenant, :user`; HMAC-SHA256 with
      pepper credential; `scopes_subset_of_catalog`; `revoked? / expired? /
      usable?`; `touch_used!`)
- [x] Add `Current` model with `tenant`, `user`, `token` attributes — delivered
      in Channel Revamp; `before_action :set_current_tenant_and_user` populates
      from `Tenant.first` / `User.first` singletons

### Scope catalog

- [x] Define scope catalog as a single Ruby constant or module — list of valid
      scopes with descriptions (delivered in 5B: `app/lib/scopes.rb` with
      `Scopes::ALL` (9 entries) and `Scopes::DESCRIPTIONS`; both frozen)
- [x] Add `require_scope!(scope)` helper used by both controllers and tools
      (delivered in 5B: `Api::AuthConcern#require_scope!` for controllers,
      `Mcp::ToolAuth.require_scope!` for tools — both honor `Current.token`)
- [x] Map every existing MCP tool to its required scope (`yt:read`, `yt:write`,
      or `yt:destructive`) (delivered in 5B: every tool's `call` enforces the
      catalog scope — see report mapping)
- [x] Phase 1's `dev:*` tools continue to require `dev:read`/`dev:write`; the
      formalization is just listing them in the catalog (delivered in 5B:
      `list_docs`/`read_doc` → `dev:read`, `save_note` → `dev:write`)
- [x] Declare `website:read` and `website:write` in the catalog (no tools yet —
      Phase 6 adds them) (delivered in 5B's `Scopes` module)

### JSON API auth concern

- [x] Implement `Api::AuthConcern` (or equivalent name) — bearer extraction,
      lookup by digest, scope check, `Current` population (delivered in 5B:
      `Api::TokenAuthenticator` for the Rack-level path, `Api::AuthConcern`
      controller mixin shared by both)
- [x] Apply to every JSON endpoint in Web Puma's controllers (delivered in 5B:
      `Api::FootagesController` is the only `Api::*` controller in Phase B's
      scope; concern mixed in)
- [x] Apply to every MCP HTTP transport endpoint in MCP Puma (delivered in 5B:
      `Mcp::RackApp#call` invokes `Api::TokenAuthenticator` before delegating
      to the transport)
- [x] Constant-time digest comparison (delivered in 5B: HMAC-SHA256 with the
      `:tokens.pepper` credential; `ActiveSupport::SecurityUtils.secure_compare`
      in both `ApiToken.authenticate` and `Api::TokenAuthenticator`)
- [x] Update `last_used_at` on success (delivered in 5B:
      `ApiToken#touch_used!` via `update_columns`)
- [x] Basic Rack::Attack throttle on failed lookups (5 per minute per IP) — full
      rate limiting is Phase 15 (delivered in 5B at the spec's locked rate of
      10 per 5 minutes per IP via `ApiAuthThrottle` + Rack::Attack blocklist;
      see `config/initializers/rack_attack.rb`)
- [x] Specs covering: missing token, invalid token, revoked token, expired
      token, valid token with required scope, valid token without required scope
      (delivered in 5B: `spec/lib/api/token_authenticator_spec.rb`,
      `spec/requests/api/auth_concern_spec.rb`,
      `spec/requests/mcp/rack_app_auth_spec.rb`)

### Existing MCP tool refactor

- [x] Each existing MCP tool calls `require_scope!('yt:read')` (or
      write/destructive as appropriate) at the top of its execute method
      (delivered in 5B: every tool's `call` opens with
      `Mcp::ToolAuth.require_scope!(...)`; full mapping in 5B's session log)
- [x] Each tool sets `Current.tenant` and `Current.user` from the resolved token
      (or relies on the auth concern having done so) (delivered in 5B:
      `Mcp::RackApp#call` populates `Current` from the token, then resets in
      `ensure`)
- [~] Tool specs assert scope rejection: a token without the right scope is
      rejected before any work happens (delivered in 5B at the rack-app level
      via `spec/requests/mcp/rack_app_auth_spec.rb`'s scope-enforcement
      example; per-tool scope-reject examples remain a follow-up since the
      scope check is uniform across all tools)

### Seeds

- [x] Seed one Tenant (`slug: "primary"`, `name: <user's name or handle>`) —
      Channel Revamp delivered name only; 5A added slug, sourced from
      `:owner.tenant_slug` (fallback `"primary"`)
- [x] Seed one User (the user's own account, role `owner`, password from Rails
      credentials) — delivered with `username + email + password_digest` from
      `:owner` credentials. 5A formally drops the `role` column; the seed has
      no `role` reference
- [x] Seed a default `ApiToken` for development with
      `dev:read dev:write yt:read yt:write project:read project:write` scopes
      (no `yt:destructive` by default; user opts in). Delivered in 5C — `db/seeds.rb`
      mints a `name: "dev"` token guarded by `ApiToken.exists?(name: "dev",
      tenant_id: tenant.id)`; plaintext is printed inside a banner on the run that
      actually mints. Idempotent on subsequent runs.
- [x] All existing seed records get `tenant_id` and `user_id` assigned to the
      seeded tenant + user — 5A wraps the seed body in
      `Current.tenant = tenant` and stamps `tenant: tenant` on the video and
      video_stat seeds (channels were already tenanted in Channel Revamp,
      Phase 4 fixtures were tenanted from day one). `user_id` plumbing is
      deferred to a later phase since no surviving model carries `user_id`
      yet

### Settings UI (minimal)

- [x] List tokens (name, scopes, last-used, created-at, revoke button) —
      delivered in 5C: `Settings::TokensController#index` lists active tokens
      first then revoked tokens grayed; columns: name, scopes, created_at,
      last_used_at, expires_at, last_token_preview, status. `[ revoke ]`
      bracketed link per active row routes to the action confirmation page.
- [x] Generate token form: name input + scope checkboxes grouped by namespace —
      delivered in 5C: `app/views/settings/tokens/_form.html.erb` iterates
      `Scopes::DESCRIPTIONS.group_by { |scope, _| scope.split(":").first }`
      and renders one `md-check` per scope under per-namespace `<fieldset>`s
      (`dev:`, `yt:`, `website:`, `project:`).
- [x] Token creation response shows plaintext exactly once with a clear "save
      now, won't show again" notice — delivered in 5C:
      `app/views/settings/tokens/create.html.erb` renders `@plaintext` inside
      a `<pre class="code-block">` framed by a `flash-warning` block.
      Subsequent index visits never re-display the plaintext (only the last-4
      preview).
- [x] Revoke action sets `revoked_at`; subsequent uses of the token return 401
      (deferred to future Auth Foundation phase) — delivered in 5C:
      `Settings::TokensController#destroy` calls `@token.revoke!` (which sets
      `revoked_at = Time.current` via `update!`); the row stays. Step B's
      `Api::TokenAuthenticator` already rejects revoked tokens with
      `revoked_token` 401.
- [x] Apply the existing Pito design system (bracketed buttons, monospace,
      dark/light theme) — delivered in 5C: bracketed-link styling via
      `BracketedLinkComponent`, monospace inherited from `body`, no JS confirm
      (revoke goes through the action-screen framework), red only on the
      `[ revoke ]` link and the `[revoke]` submit button.

### Documentation

- [x] Update `pito/docs/architecture.md`: auth section, multi-tenant scoping
      pattern, token lifecycle, the `belongs_to_tenant` concern — delivered
      in 5C: rewrote the "Tenant + User schema" section as
      "Tenant + User + ApiToken schema (Phase 3 — Auth Foundation)", adding
      explicit subsections for Schema, Current, BelongsToTenant, and the
      `Current.token` flow. Removed the false "auth deferred" claim from the
      "Things explicitly NOT in scope" section.
- [x] Update `pito/docs/mcp.md`: scope requirements per tool, scope catalog
      reference — delivered in 5C: added a Scope-per-tool table covering all
      19 tools with required scope + Channel-Revamp notes; updated the
      Architecture and Token Model sections to match Step B reality; replaced
      the stale `mcp:*` rake task surface with `tokens:*` (the Step B
      rename); refreshed the File Structure section to reflect
      `app/models/api_token.rb`, `app/lib/scopes.rb`, the auth concern, the
      rack-attack initializer, and the auth-audit logger.
- [x] Add `pito/docs/auth.md`: authoritative reference for the auth model —
      delivered in 5C: 11 sections per spec §6.6 (Model overview, Scope
      catalog, Tool/endpoint scope map, Request flow with ASCII diagram,
      `belongs_to_tenant` enforcement, Token lifecycle, Bootstrap ceremony,
      Audit log, Throttling, Departures from the original Phase 3 plan,
      Future phase hooks).
- [~] Update `pito/docs/design.md` with the token UI patterns if visually
      distinct from existing forms — not needed; the token UI uses existing
      design-system primitives (bracketed-link styling, action-screen
      framework for revoke confirmation, `md-check` for scope checkboxes,
      `flash-warning` for the show-once notice, `code-block` for the
      plaintext display). Nothing visually distinct to document.

### Validation

- [x] All Alpha specs continue to pass with `Current.tenant` populated in test
      setup helpers — Channel Revamp set `Current.tenant = Tenant.first` via
      `before_action`; specs green
- [x] New specs for `Tenant`, `User`, `ApiToken`, scope enforcement, `Current`
      lifecycle, default scoping — Tenant + User specs delivered in Channel
      Revamp; `ApiToken` / `Scopes` / `Api::TokenAuthenticator` /
      `Api::AuthConcern` / `rack-attack` specs delivered in 5B
      (`spec/models/api_token_spec.rb`, `spec/lib/scopes_spec.rb`,
      `spec/lib/api/token_authenticator_spec.rb`,
      `spec/requests/api/auth_concern_spec.rb`,
      `spec/requests/mcp/rack_app_auth_spec.rb`,
      `spec/initializers/rack_attack_spec.rb`)
- [x] Cross-tenant leak spec: create a second tenant + user via factory; assert
      all queries scoped to `Current.tenant` exclude the other tenant's records
      (delivered in 5A — `spec/models/cross_tenant_leak_spec.rb` builds a
      full two-tenant fixture, asserts count + symmetry under Current=tenant_a
      and Current=tenant_b across all 16 tenanted models, locks
      RecordNotFound on cross-tenant `find`, asserts
      TenantContextMissing under `Current.reset`, and locks
      `Model.unscoped` as the documented escape hatch)
- [x] Web UI works as before (the seeded user is implicitly current) — verified
      in Channel Revamp manual playbook
- [x] MCP HTTP requires valid token with the right scope; rejects insufficient
      scope (delivered in 5B: `Mcp::RackApp` rejects unauthenticated with 401;
      every tool's `call` rejects insufficient scope with the
      `insufficient_scope` envelope)
- [x] Both Web Puma and MCP Puma honor the same auth concern (delivered in
      5B: `Api::TokenAuthenticator` is the shared engine — controllers mix in
      `Api::AuthConcern`, the rack app calls the authenticator inline)
- [x] Brakeman, bundler-audit, Dependabot — clean — verified by Channel Revamp
      security-auditor; 5B re-verified Brakeman: 0 warnings (rack-attack 6.8.0
      added)
- [~] `pito/docs/design.md` updated for any UI changes — not needed (5C used
      only existing design-system primitives; see Documentation section).

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
