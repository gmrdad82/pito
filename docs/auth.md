# Auth

The single source of truth for pito's authentication and authorization model.
pito is a **single-install, multi-user** application (ADR 0003): the whole
database belongs to one install, every authenticated user has install-wide
read/write access, and there is no per-user data isolation. Authentication is
mandatory at every endpoint, every MCP tool, and every controller action.

Four surfaces gate access to the install:

- **Browser → Rails (Web Puma)** — cookie + DB-backed sessions; login is email +
  password (Phase 8).
- **MCP / `pito` CLI → Rails (MCP Puma + API routes)** — bearer `ApiToken`s
  (HMAC-digested, scoped, revocable).
- **Third-party clients → Rails** — Doorkeeper-issued OAuth 2.0 tokens
  (Authorization Code + PKCE; Phase 6B).
- **pito → Google (outbound delegation)** — OAuth-delegated `GoogleIdentity` for
  YouTube API access (Phase 7; channel-only OAuth per ADR 0006).

If you came here looking for something specific:

- "How do I log in?" → §1 (login flow).
- "How do I generate a dev token?" → §7.
- "Which scope does my MCP tool require?" → §4.
- "How does a request flow through auth?" → §5.

## Auth surfaces overview

This document is authoritative for **email + password login** (surface #1, §1
below) and **bearer ApiTokens** (surface #2, the rest of the document — the
original Phase 5 Auth Foundation). Surfaces #3 and #4 are documented elsewhere.

| #   | Surface                   | Mechanism                                            | Authoritative reference                                                                                                                                                                                                                   |
| --- | ------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Browser → Rails           | Cookie + DB-backed sessions (email + password)       | §1 below for the login flow + rate-limit + audit shape. Live code: `app/controllers/sessions_controller.rb`, `app/controllers/concerns/sessions/auth_concern.rb`. Revocation UI at `/settings/sessions`.                                  |
| 2   | MCP / `pito` CLI → Rails  | Bearer ApiTokens (HMAC-digested, scoped, revocable)  | The rest of this document (`docs/auth.md`). Live code: `app/lib/api/token_authenticator.rb`, `app/models/api_token.rb`.                                                                                                                   |
| 3   | 3rd-party clients → Rails | Doorkeeper-issued OAuth (Authorization Code + PKCE)  | Spec: `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md`. Live config: `config/initializers/doorkeeper.rb`. Tokens are 2h access / 14d refresh. Stays per ADR 0005.                                    |
| 4   | pito → Google (YouTube)   | OAuth-delegated `GoogleIdentity` (encrypted at rest) | `docs/architecture.md` "Google OAuth + YouTube API foundation (Phase 7)" section. Live code: `app/models/google_identity.rb`. Channel-only OAuth per ADR 0006 (no "Sign in with Google"); rename to `YoutubeConnection` lands in Phase 9. |

The four surfaces are independent. A request from a browser session (#1) cannot
authenticate as an ApiToken (#2); a Doorkeeper access token (#3) does not grant
Google API access (#4). Each surface has its own credential type, lifetime, and
revocation path.

## 1. Login flow (email + password)

The login form at `/login` accepts a single `email` field plus `password` and
submits to `SessionsController#create`. There is no "username" path and no "Sign
in with Google" alternative — Phase 8 dropped the `username` column from `users`
(ADR 0003 + 0006), and ADR 0006 narrowed Google OAuth to channel connection
only.

### Model

- `User` — auth-only model. Columns:
  `id, email (citext, unique, NOT NULL), password_digest, created_at, updated_at`.
  No `username`, no `tenant_id`, no `admin`. `has_secure_password`.
- `Session` — DB-backed session record (Phase 6A). Carries the cookie's session
  id, the user reference, IP / user-agent metadata, and supports per-session
  revocation via `/settings/sessions`.

### Flow

```
POST /login (email, password)
   │
   ├── User.find_by(email: <stripped, downcased>)
   ├── If found: user.authenticate(password)        → bcrypt compare
   │   If not found: bcrypt_dummy_compare(password) → constant-time, same wall-cost
   │
   ├── Both branches return the same generic
   │   "invalid email or password." flash on failure
   │   (no oracle on whether the email exists).
   │
   ▼ on success
   Session.create_for!(user:) — issues cookie
   redirect_to <intended_path> || root_path
```

The bcrypt-dummy-compare on the no-such-email branch closes the timing oracle
that previously distinguished "no such email" from "wrong password" via wall-
clock latency (Phase 8 F1 fix).

### Rate limit

`SessionThrottle` blocklists IPs that fail login more than **10 times in 5
minutes**. The bucket is keyed on the request IP. A blocklisted request returns
the form re-rendered with a throttling notice; the bucket clears as it ages out.
Rate limiting is per-IP (not per-email) so spammers cannot lock a victim out by
guessing their email; comprehensive rate-limit hardening is a later phase.

### Audit log

Every login attempt — success or failure — writes a JSON line to
`log/auth_audit.log`. The payload includes `email_attempted` (renamed from the
pre-Phase-8 `identifier_attempted`), the outcome, and request metadata. See §8
for the full event catalog.

## 2. ApiToken model overview

Three moving parts:

```
User ──< ApiToken
              │
              └── scopes: ["dev:read", "yt:write", ...]

Current   (ActiveSupport::CurrentAttributes)
  ├── user
  ├── session
  └── token         ← set by Api::TokenAuthenticator on every API request
```

- `User` — owner of tokens (see §1). Seeded from the `:owner` credentials block
  (`{ email, password }`).
- `ApiToken` — bearer credential. Stored as an HMAC-SHA256 digest with a
  server-side `:tokens.pepper` credential; plaintext is shown once at creation
  and never persisted. Has a `name`, a `scopes` jsonb array, optional
  `expires_at`, and a soft-revoke `revoked_at`.
- `Current` — `ActiveSupport::CurrentAttributes`. Carries `user`, `session`,
  `token` for the duration of a request (or job, or rake task). Reset on every
  response and between every spec example. There is no `Current.tenant`.

## 3. Scope catalog

Authoritative source: `app/lib/scopes.rb`. Listed below as a reference; if the
two diverge, the file wins.

| Scope            | Description                                         |
| ---------------- | --------------------------------------------------- |
| `dev:read`       | Read dev knowledge base (docs/).                    |
| `dev:write`      | Write notes to docs/notes/.                         |
| `yt:read`        | Read channels, videos, stats, dashboards.           |
| `yt:write`       | Create / update channels, videos, saved views.      |
| `yt:destructive` | Delete channels, videos, bulk-delete operations.    |
| `website:read`   | Read landing-page content (Phase 6+, no tools yet). |
| `website:write`  | Edit landing-page content (Phase 6+, no tools yet). |
| `project:read`   | Read projects, collections, games, footage, notes.  |
| `project:write`  | Create / update / delete project workspace records. |

Naming pattern: `<namespace>:<permission>`. Adding a new scope means editing
`Scopes::ALL` and `Scopes::DESCRIPTIONS` and ticking the corresponding tools'
`require_scope!` calls.

## 4. Tool / endpoint scope map

Every MCP tool's `call` method opens with `Mcp::ToolAuth.require_scope!(...)`.
Every JSON controller action declares its required scope via `require_scope!`
from `Api::AuthConcern`.

### MCP tools

| Tool                | Required scope            |
| ------------------- | ------------------------- |
| `list_channels`     | `yt:read`                 |
| `get_channel`       | `yt:read`                 |
| `list_videos`       | `yt:read`                 |
| `get_video`         | `yt:read`                 |
| `get_dashboard`     | `yt:read`                 |
| `search`            | `yt:read`                 |
| `list_saved_views`  | `yt:read`                 |
| `manage_settings`   | `yt:read` (no updates)    |
|                     | `yt:write` (with updates) |
| `create_channel`    | `yt:write`                |
| `update_channel`    | `yt:write`                |
| `create_video`      | `yt:write`                |
| `update_video`      | `yt:write`                |
| `create_saved_view` | `yt:write`                |
| `delete_saved_view` | `yt:write`                |
| `sync_records`      | `yt:write`                |
| `delete_records`    | `yt:destructive`          |
| `list_docs`         | `dev:read`                |
| `read_doc`          | `dev:read`                |
| `save_note`         | `dev:write`               |

### JSON HTTP endpoints

| Endpoint                                  | Required scope  |
| ----------------------------------------- | --------------- |
| `GET /api/projects/:project_id/footages`  | `project:read`  |
| `POST /api/projects/:project_id/footages` | `project:write` |

HTML routes (`/channels`, `/videos`, `/projects`, `/settings`, etc.) are gated
by `Sessions::AuthConcern`: an authenticated cookie session is required, and
unauthenticated requests redirect to `/login` with the intended URL stashed.
Bearer tokens are for surfaces #2 and #3 only.

## 5. Request flow (bearer tokens)

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
   Current.token = token
   Current.user  = token.user
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

- `401 {"error": "missing_token" | "invalid_token" | "revoked_token" | "expired_token" | "auth_misconfigured"}`
- `403 {"error": "insufficient_scope", "required": "<scope>"}`

### MCP Puma (`Mcp::RackApp`)

The rack app calls the authenticator inline in `#call`, populates `Current`,
delegates to the streamable HTTP transport, and resets in an `ensure` block.
Per-tool scope enforcement happens inside each tool's `call` method via
`Mcp::ToolAuth.require_scope!`.

## 6. Token lifecycle

```
Settings::TokensController#create   |   bin/rails 'tokens:create[name,...]'
                              │
                              ▼
            ApiToken.generate!(user:, name:, scopes:, expires_at: nil)
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
`authenticate` call (rejected as `expired_token`), but no background job deletes
or marks expired rows. Phase 12 / 15 add automated expiry handling.

## 7. Bootstrap ceremony

First install on a fresh machine:

1. Set the pepper credential. The pepper is the secret HMAC key the auth engine
   uses to digest plaintext tokens. Without it, no token can be minted or
   authenticated.

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
   with a walkthrough if it's absent. With it set, `db:prepare` runs migrations
   and triggers `db:seed`.

3. The seed mints a default `dev` token (idempotent — second runs are no-ops)
   with the scope set:

   ```
   dev:read, dev:write, yt:read, yt:write, project:read, project:write
   ```

   Plaintext is printed to STDOUT inside a banner. **Save it now** — it cannot
   be retrieved later. If you lose it, revoke it via `/settings/tokens` and mint
   a new one.

4. Configure clients with the captured plaintext:
   - `pito` CLI: `export PITO_API_TOKEN=<plaintext>` (the binary reads it).
   - MCP HTTP transport: include `Authorization: Bearer <plaintext>` on every
     POST to `/mcp`.
   - Claude Mobile: configure the MCP connector to point at `mcp.pitomd.com`
     with the bearer token.

5. Mint additional scoped tokens via `/settings/tokens` (one per client, one per
   scope set). Revoke unused tokens periodically.

## 8. Audit log

`config/initializers/auth_audit_logger.rb` configures `AUTH_AUDIT_LOGGER`
against `log/auth_audit.log`. Format: one JSON line per event.

Event types:

- `auth.success` — successful bearer authenticate.
- `auth.missing_token` — no Authorization header (or no Bearer prefix).
- `auth.invalid_token` — digest didn't match any row.
- `auth.revoked_token` — row found, but `revoked_at` is set.
- `auth.expired_token` — row found, but `expires_at <= Time.current`.
- `auth.misconfigured` — `:tokens.pepper` credential absent.
- `token.created` — Settings UI minted a new token.
- `token.revoked` — Settings UI revoked a token.
- `session.create.success` — successful login. Payload includes
  `email_attempted`.
- `session.create.failure` — failed login. Payload includes `email_attempted`
  and a generic failure reason. The reason does NOT distinguish "no such email"
  from "wrong password" — the bcrypt-dummy-compare path produces the same
  outcome shape on either branch (Phase 8 F1 fix).
- `session.destroy` — logout.

Rotation is host-side (logrotate); out of scope for this phase.

Both Pumas write to the same file. The MCP rack app writes from outside the
Rails request cycle; the controllers write from inside.

## 9. Throttling

Two independent throttles defend the install:

- **`SessionThrottle`** — gates the login form. Blocklists IPs that fail login
  more than 10 times in 5 minutes (see §1).
- **`config/initializers/rack_attack.rb`** — gates bearer-token surfaces.
  Blocklists IPs that fail bearer authentication more than 10 times in 5
  minutes; incremented from inside `Api::TokenAuthenticator` whenever it returns
  a failure. A blocklisted request returns `429 {"error": "too_many_requests"}`.
  Only `/api/*` and `/mcp` are gated; HTML routes go through `SessionThrottle`.

Both buckets are per-IP, not per-credential. Comprehensive rate-limit hardening
is a later phase.

## 10. Future phase hooks

| Phase    | What it adds                                                                                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 9  | Renames `GoogleIdentity` → `YoutubeConnection` (channel-only OAuth per ADR 0006). Bearer-token surface unaffected.                    |
| Phase 12 | Hardens auth UI: token expiry automation, session management improvements, multi-user readiness on top of the single-install posture. |
| Phase 15 | Hardens rate limits beyond the current `SessionThrottle` + `rack-attack` rules.                                                       |

When a phase touches the auth surface, the `Scopes` module is the place to add
new entries; `Api::AuthConcern` and `Mcp::ToolAuth.require_scope!` are the
gates.
