# Auth

The single source of truth for Pito's authentication and authorization model.
This phase is the **Auth Foundation**: schema-level multi-tenancy plus
bearer-token auth + scopes for the JSON API and MCP HTTP transport. There is no
login UI yet; HTML routes still operate under the implicit single-user session
(`Current.user = User.first`). Phase 6 lands the login surface on top of this
foundation.

The pieces are split across three steps:

- **Step A** — schema (Tenant, User, `BelongsToTenant`).
- **Step B** — `ApiToken`, scope catalog, `Api::AuthConcern`, audit log,
  rack-attack throttle.
- **Step C** — Settings UI for token CRUD, dev token seed, this document.

If you came here looking for something specific:

- "How do I generate a dev token?" → §7.
- "Which scope does my MCP tool require?" → §3.
- "How does a request flow through auth?" → §4.
- "What's the `belongs_to_tenant` raise about?" → §5.
- "Why does the schema look different from the original Phase 3 plan?" → §10.

## 1. Model overview

Four moving parts:

```
Tenant ──< User ──< ApiToken
                       │
                       └── scopes: ["dev:read", "yt:write", ...]

Current   (ActiveSupport::CurrentAttributes)
  ├── tenant
  ├── user
  └── token         ← set by Api::TokenAuthenticator on every API request
```

- `Tenant` — isolation unit. One row in this phase. Has a `slug` (citext,
  unique) and a `name`. No `belongs_to_tenant` itself (a tenant has no parent
  tenant).
- `User` — owner of tokens. One row in this phase, seeded from the `:owner`
  credentials block. Uses `has_secure_password`. `username` and `email` are
  globally unique (deliberate departure — see §10).
- `ApiToken` — bearer credential. Stored as an HMAC-SHA256 digest with a
  server-side `:tokens.pepper` credential; plaintext is shown once at
  creation and never persisted. Has a `name`, a `scopes` jsonb array, optional
  `expires_at`, and a soft-revoke `revoked_at`.
- `Current` — `ActiveSupport::CurrentAttributes`. Carries `tenant`, `user`,
  `token` for the duration of a request (or job, or rake task). Reset on every
  response and between every spec example.

## 2. Scope catalog

Authoritative source: `app/lib/scopes.rb`. Listed below as a reference; if the
two diverge, the file wins.

| Scope            | Description                                              |
| ---------------- | -------------------------------------------------------- |
| `dev:read`       | Read dev knowledge base (docs/).                         |
| `dev:write`      | Write notes to docs/notes/.                              |
| `yt:read`        | Read channels, videos, stats, dashboards.                |
| `yt:write`       | Create / update channels, videos, saved views.           |
| `yt:destructive` | Delete channels, videos, bulk-delete operations.         |
| `website:read`   | Read landing-page content (Phase 6+, no tools yet).      |
| `website:write`  | Edit landing-page content (Phase 6+, no tools yet).      |
| `project:read`   | Read projects, collections, games, footage, notes.       |
| `project:write`  | Create / update / delete project workspace records.      |

Naming pattern: `<namespace>:<permission>`. Adding a new scope means editing
`Scopes::ALL` and `Scopes::DESCRIPTIONS` and ticking the corresponding tools'
`require_scope!` calls.

## 3. Tool / endpoint scope map

Every MCP tool's `call` method opens with
`Mcp::ToolAuth.require_scope!(...)`. Every JSON controller action declares
its required scope via `require_scope!` from `Api::AuthConcern`.

### MCP tools

| Tool                | Required scope          |
| ------------------- | ----------------------- |
| `list_channels`     | `yt:read`               |
| `get_channel`       | `yt:read`               |
| `list_videos`       | `yt:read`               |
| `get_video`         | `yt:read`               |
| `get_dashboard`     | `yt:read`               |
| `search`            | `yt:read`               |
| `list_saved_views`  | `yt:read`               |
| `manage_settings`   | `yt:read` (no updates)  |
|                     | `yt:write` (with updates) |
| `create_channel`    | `yt:write`              |
| `update_channel`    | `yt:write`              |
| `create_video`      | `yt:write`              |
| `update_video`      | `yt:write`              |
| `create_saved_view` | `yt:write`              |
| `delete_saved_view` | `yt:write`              |
| `sync_records`      | `yt:write`              |
| `delete_records`    | `yt:destructive`        |
| `list_docs`         | `dev:read`              |
| `read_doc`          | `dev:read`              |
| `save_note`         | `dev:write`             |

### JSON HTTP endpoints

| Endpoint                                    | Required scope    |
| ------------------------------------------- | ----------------- |
| `GET /api/projects/:project_id/footages`    | `project:read`    |
| `POST /api/projects/:project_id/footages`   | `project:write`   |

The HTML routes (`/channels`, `/videos`, `/projects`, `/settings`, etc.) do
not require bearer tokens in this phase — they operate under the implicit
single-user session via `ApplicationController#set_current_tenant_and_user`.
Phase 6 adds the login UI and gates these routes behind a real session.

## 4. Request flow

Both Pumas (Web on 3027, MCP on 3028) share the same auth engine
(`Api::TokenAuthenticator`).

```
Bearer header arrives
   │
   ▼
Api::TokenAuthenticator.authenticate(env)
   │
   ├── extract `Authorization: Bearer <plaintext>` header
   ├── digest = HMAC_SHA256(:tokens.pepper, plaintext)
   ├── ApiToken.where(token_digest: digest).take
   ├── verify usable? (not revoked, not expired)
   ├── secure_compare on the digest
   │
   ├── on FAILURE:
   │     env["pito.auth_failed"] = true
   │     ApiAuthThrottle.record_failure(env)
   │     AUTH_AUDIT_LOGGER.info(<reason>)
   │     return Result.failure(<reason>)
   │
   ▼ on SUCCESS
   token.touch_used!                    # update_columns(last_used_at: now)
   Current.token  = token
   Current.user   = token.user
   Current.tenant = token.tenant
   AUTH_AUDIT_LOGGER.info(auth.success)
   return Result.success(token)
   │
   ▼
controller action / MCP tool
   │
   require_scope!(Scopes::YT_WRITE)     # raises Api::Forbidden if missing
   │
   ▼
work happens
   │
   ▼
response sent → Current.reset (controller after_action / Rack ensure block)
```

### Web Puma (`Api::AuthConcern`)

`Api::AuthConcern` is mixed into every controller under the `Api::` namespace
(today: `Api::FootagesController`). The concern adds:

- `before_action :authenticate_api_token!` — runs the authenticator, raises
  `Api::Unauthorized` on failure.
- `require_scope!(scope)` helper — raises `Api::Forbidden` when the resolved
  token's scopes don't include the required one.

Errors are translated to JSON envelopes by `ApplicationController`:

- `401 {"error": "missing_token" | "invalid_token" | "revoked_token" |
  "expired_token" | "auth_misconfigured"}`
- `403 {"error": "insufficient_scope", "required": "<scope>"}`

### MCP Puma (`Mcp::RackApp`)

The rack app calls the authenticator inline in `#call`, populates `Current`,
delegates to the streamable HTTP transport, and resets in an `ensure` block.
Per-tool scope enforcement happens inside each tool's `call` method via
`Mcp::ToolAuth.require_scope!`.

## 5. `belongs_to_tenant` enforcement

`app/models/concerns/belongs_to_tenant.rb` is included by every tenanted
model. It declares:

- `belongs_to :tenant`
- `validates :tenant_id, presence: true`
- `default_scope { where(tenant_id: Current.tenant_id) }` — the scope is
  applied **always**, and **raises** `BelongsToTenant::TenantContextMissing`
  when `Current.tenant_id` is nil. Bugs are loud; missing tenant context is
  never silent.

The escape hatch is `Model.unscoped`. Use it in the rare cases where the
caller intentionally needs to see across tenants — seed scripts, the
authenticator's pre-Current digest lookup, the cross-tenant leak spec. In
application code there are no legitimate callers.

`Tenant` and `User` deliberately do NOT include the concern. Tenant has no
parent; User is queried by future login flows that don't yet have a tenant
pin.

## 6. Token lifecycle

```
Settings::TokensController#create   |   bin/rails 'tokens:create[name,...]'
                              │
                              ▼
            ApiToken.generate!(tenant:, user:, name:, scopes:, expires_at: nil)
              ─ generates SecureRandom.urlsafe_base64(32) plaintext
              ─ stores HMAC-SHA256 digest + last 4 chars
              ─ returns [record, plaintext]
              ─ plaintext is shown once, never re-displayed
                              │
                              ▼
                      ┌──── used ────┐
                      │              │
              Api::TokenAuthenticator.authenticate
                  ─ on success: touch_used! (last_used_at)
                              │
                              ▼
              Settings::TokensController#destroy   |   bin/rails 'tokens:revoke[id]'
                              │
                              ▼
                      record.revoke!  →  revoked_at = Time.current
                      (the row stays in the database forever for audit)
```

There is no automatic expiry sweep yet. `expires_at` is honored on every
`authenticate` call (rejected as `expired_token`), but no background job
deletes or marks expired rows. Phase 12 / 15 add automated expiry handling.

## 7. Bootstrap ceremony

First install on a fresh machine:

1. Set the pepper credential. The pepper is the secret HMAC key the auth
   engine uses to digest plaintext tokens. Without it, no token can be
   minted or authenticated.

   ```bash
   bin/rails credentials:edit
   ```

   Add:

   ```yaml
   tokens:
     pepper: <64-char hex>
   ```

   Generate the value with `openssl rand -hex 32`.

2. Run `bin/setup`. The script pre-flights the pepper credential and exits 1
   with a walkthrough if it's absent. With it set, `db:prepare` runs
   migrations and triggers `db:seed`.

3. The seed mints a default `dev` token (idempotent — second runs are no-ops)
   with the scope set:

   ```
   dev:read, dev:write, yt:read, yt:write, project:read, project:write
   ```

   Plaintext is printed to STDOUT inside a banner. **Save it now** — it cannot
   be retrieved later. If you lose it, revoke it via `/settings/tokens` and
   mint a new one.

4. Configure clients with the captured plaintext:

   - `pito` CLI: `export PITO_API_TOKEN=<plaintext>` (the binary reads it).
   - MCP HTTP transport: include `Authorization: Bearer <plaintext>` on
     every POST to `/mcp`.
   - Claude Mobile: configure the MCP connector to point at
     `mcp.pitomd.com` with the bearer token.

5. Mint additional scoped tokens via `/settings/tokens` (one per client, one
   per scope set). Revoke unused tokens periodically.

## 8. Audit log

`config/initializers/auth_audit_logger.rb` configures `AUTH_AUDIT_LOGGER`
against `log/auth_audit.log`. Format: one JSON line per event.

Event types:

- `auth.success` — successful authenticate.
- `auth.missing_token` — no Authorization header (or no Bearer prefix).
- `auth.invalid_token` — digest didn't match any row.
- `auth.revoked_token` — row found, but `revoked_at` is set.
- `auth.expired_token` — row found, but `expires_at <= Time.current`.
- `auth.misconfigured` — `:tokens.pepper` credential absent.
- `token.created` — Settings UI minted a new token.
- `token.revoked` — Settings UI revoked a token.

Rotation is host-side (logrotate); out of scope for this phase.

Both Pumas write to the same file. The MCP rack app writes from outside the
Rails request cycle; the controllers write from inside.

## 9. Throttling

`config/initializers/rack_attack.rb` blocklists IPs that fail authentication
more than 10 times in 5 minutes. The bucket is keyed on the request IP and
incremented from inside `Api::TokenAuthenticator` whenever it returns a
failure.

A blocklisted request returns `429 {"error": "too_many_requests"}`. The
blocklist is per-IP and not per-token (you can't burn through a token's
budget by spamming). HTML routes are exempt — only `/api/*` and `/mcp` are
gated.

Comprehensive rate limiting is Phase 15.

## 10. Departures from the original Phase 3 plan

Four schema decisions diverge from the locked Phase 3 (Auth Foundation) plan
that pre-dates the Channel Revamp pivot. Each is a deliberate choice; future
phases can revisit.

### `users.email` and `users.username` are globally unique

The original plan specified per-tenant uniqueness (a UNIQUE index on
`(tenant_id, email)`). Channel Revamp shipped a global UNIQUE index on
`email` and on `username` instead. With one tenant in the system, the
practical behavior is identical; the global indexes are simpler to reason
about and support the future "log in by username/email anywhere on the app"
shape without reaching into the URL for a tenant slug.

The trade-off: when multi-tenancy lands at Theta, two tenants can't share a
username or email. Theta's spec will revisit; until then, single-tenant
makes the question moot.

### `users.role` and `users.name` are dropped

The plan had `role` (string, default `"owner"`) and `name`. Single-user world
makes the role column dead weight (every row is `"owner"`); username + email
cover every display need without `name`. Both columns are absent from the
shipped schema. When auth grows roles (admin / member / etc. in a future
phase), the column comes back via a migration.

### `tenants.slug` was added late

The original plan didn't specify a `slug`. Channel Revamp shipped tenants
with `name` only; Step A added `slug` (citext, unique, NOT NULL) so URLs
like `/<tenant_slug>/...` are achievable when multi-tenancy lands. The seed
backfills slug from `:owner.tenant_slug` (fallback `"primary"`).

### `mcp_access_tokens` was renamed, not dropped

The plan said the Alpha-era token table would be dropped and replaced with a
fresh `api_tokens` table. Step B chose to rename (`rename_table`) and extend
(`add_column tenant_id, user_id, scopes, expires_at`) instead. Rationale:
preserves the working `bin/rails tokens:*` rake task path; rolling back the
rename is cheaper than rolling back a drop+create+migrate cycle. Existing
rows backfilled to `Tenant.first` / `User.first` and the dev:* scope set.

## 11. Future phase hooks

| Phase    | What it adds                                                |
| -------- | ----------------------------------------------------------- |
| Phase 6  | Activates `website:*` tools (landing-page editor).          |
| Phase 7  | Google OAuth tokens tied to Users (different model: `GoogleIdentity`); doesn't change the bearer-token surface. |
| Phase 12 | Login form + session UI on top of this foundation. Doorkeeper for OAuth client flows. Token expiry automation. |
| Phase 15 | Hardens rate limits beyond the basic rack-attack rule.      |
| Theta    | Multi-tenant admin tooling, per-tenant uniqueness revisit.  |

When a phase touches the auth surface, the `Scopes` module is the place to
add new entries; `Api::AuthConcern` and `Mcp::ToolAuth.require_scope!` are
the gates.
