# Phase 3 — Step B — Token Model and Auth Concern

> The unifying middleware. Promotes `McpAccessToken` to `ApiToken`, defines the
> Beta scope catalog, and adds a single `Api::AuthConcern` that both Web Puma
> JSON endpoints and `Mcp::RackApp` consume. Date: 2026-05-05. Locked decisions
> are pinned exactly — do not reinvent.

---

## 1. Goal

Replace the placeholder "auth open" line at the top of `Mcp::RackApp` with
real bearer-token authentication, and apply the same concern to every JSON
endpoint on Web Puma. Tokens carry scopes; every MCP tool and JSON action
calls `require_scope!(<scope>)` before doing work. Failed lookups are
throttled. Successful and failed auth attempts are written to a dedicated
audit log.

The token model is a rename-and-extend of the existing `McpAccessToken`
table from the Channel-Revamp-era MCP HTTP transport phase — not a fresh
table. Existing rake-task token CRUD continues to work after the rename.

## 2. Depends on

- Step A (`5a-schema-and-current.md`) — `mcp_access_tokens` has `tenant_id`,
  every model is tenanted, `Current.tenant_id` reliably scopes queries.
- Channel Revamp's `McpAccessToken` model: HMAC-SHA256 digest, secure
  compare, `last_used_at` update, rake-task CRUD.
- Channel Revamp's `Current` model with `attribute :tenant, :user, :token`.

## 3. Unblocks

- Step C (`5c-settings-ui-and-docs.md`) — Settings UI builds CRUD on the
  renamed model; docs reference `Scopes::ALL`.
- Phase 4's `pito footage` CLI — once tokens are required for JSON
  endpoints, the CLI's bearer-header support has a real backend to talk to.
- Phase 6 onward — `website:*` and future namespaces plug into the catalog
  declared here.

## 4. Why now

Step A makes the schema uniform. Step B is the moment to lock the auth
contract: every request in/out of either Puma carries a bearer token, the
token resolves to a Tenant + User + scope set, and `Current` is populated
consistently. Step C's UI is just CRUD on top of this; without Step B, the
UI has nothing meaningful to mint.

The decision to extend `McpAccessToken` rather than drop and replace it is
locked: that table already has the digest, secure-compare, and
`last_used_at` plumbing. The plan called for a fresh `api_tokens` table, but
the analogue post-dates the plan and is now the de-facto Beta token model.
A clean rename + column add is shorter than a drop-and-recreate, and
preserves the working rake-task CRUD path.

---

## 5. Locked decisions

- **Token digest:** HMAC-SHA256 with a server-side pepper from
  `Rails.application.credentials.dig(:tokens, :pepper)`. Constant-time
  compare via `ActiveSupport::SecurityUtils.secure_compare`. Choice over
  bcrypt is the plan's "fast token-lookup performance" path — bcrypt would
  add ~100ms to every API call.
- **Token shape:** `SecureRandom.urlsafe_base64(32)` (32 bytes of
  randomness, ~43 chars urlsafe). Plaintext shown once at creation. Stored
  as digest only.
- **Pepper rotation:** out of scope. The pepper is generated once at
  `bin/setup` time (Step C documents the ceremony) and never rotated in
  Phase 3. A future phase handles rotation if needed.
- **Token rename:** `mcp_access_tokens` → `api_tokens`. Model class
  `McpAccessToken` → `ApiToken`. The single migration uses `rename_table` +
  any necessary `rename_index`. No data loss; existing rows survive.
- **Audit log:** dedicated file `log/auth_audit.log`. Format JSON per line:
  `{ts, event, token_name, token_id, ip, route, scope_required, result}`.
  Written from the auth concern. Both Pumas append to the same file.
- **Throttle:** `rack-attack` gem, throttle by IP on the
  `Authorization`-bearing request path: 10 failed lookups per 5 minutes →
  429. Successful lookups do not count against the throttle.
- **Cookie auth untouched.** Web HTML routes (`/`, `/channels`, `/videos`,
  `/settings`) continue without bearer tokens — the existing `before_action`
  (Step A's predecessor patch) populates `Current.tenant` /
  `Current.user` from the seeded singletons. Only `Api::*` JSON endpoints
  and `Mcp::RackApp` require tokens.

---

## 6. In scope

### 6.1 Token model rename and extend

Migration sequence (reversible):

1. `rename_table :mcp_access_tokens, :api_tokens` and rename any indexes
   that include the old table name.
2. `add_reference :api_tokens, :user, foreign_key: true, null: true`.
   Backfill existing rows to `User.first.id`.
   `change_column_null :api_tokens, :user_id, false`.
3. `add_column :api_tokens, :scopes, :jsonb, null: false, default: []`.
   Backfill existing rows to `["dev:read", "dev:write"]` (the Phase 1
   `dev:*` set already de facto in use).
4. `add_column :api_tokens, :expires_at, :datetime, null: true`.

Rename the model file `app/models/mcp_access_token.rb` →
`app/models/api_token.rb` and class `McpAccessToken` → `ApiToken`. Update
every caller: rake tasks under `lib/tasks/`, MCP rack app, model specs,
factory.

`ApiToken` validations / methods:

- `belongs_to :tenant`, `belongs_to :user`. Include `BelongsToTenant`.
- `validates :name, presence: true`.
- `validates :scopes, presence: true` — empty array rejected.
- `validate :scopes_subset_of_catalog` — every entry must be in
  `Scopes::ALL`.
- `validates :token_digest, presence: true, uniqueness: true`.
- Class method `ApiToken.generate!(tenant:, user:, name:, scopes:,
  expires_at: nil)` returns `[record, plaintext]` and stores digest +
  `last_token_preview` (last 4 chars of plaintext).
- `revoked?` → `revoked_at.present?`.
- `expired?` → `expires_at.present? && expires_at <= Time.current`.
- `usable?` → not `revoked?` and not `expired?`.
- `touch_used!` updates `last_used_at` via `update_columns` (skip
  validations / callbacks; safe under default scope).

### 6.2 Scope catalog

New file `app/lib/scopes.rb`:

```ruby
module Scopes
  DEV_READ        = "dev:read"
  DEV_WRITE       = "dev:write"
  YT_READ         = "yt:read"
  YT_WRITE        = "yt:write"
  YT_DESTRUCTIVE  = "yt:destructive"
  WEBSITE_READ    = "website:read"
  WEBSITE_WRITE   = "website:write"
  PROJECT_READ    = "project:read"
  PROJECT_WRITE   = "project:write"

  ALL = [
    DEV_READ, DEV_WRITE,
    YT_READ, YT_WRITE, YT_DESTRUCTIVE,
    WEBSITE_READ, WEBSITE_WRITE,
    PROJECT_READ, PROJECT_WRITE
  ].freeze

  DESCRIPTIONS = {
    DEV_READ       => "Read dev knowledge base (docs/).",
    DEV_WRITE      => "Write notes to docs/notes/.",
    YT_READ        => "Read channels, videos, stats, dashboards.",
    YT_WRITE       => "Create / update channels, videos, saved views.",
    YT_DESTRUCTIVE => "Delete channels, videos, bulk-delete operations.",
    WEBSITE_READ   => "Read landing-page content (Phase 6+).",
    WEBSITE_WRITE  => "Edit landing-page content (Phase 6+).",
    PROJECT_READ   => "Read projects, collections, games, footage, notes.",
    PROJECT_WRITE  => "Create / update / delete project workspace records."
  }.freeze
end
```

`Scopes::ALL` is the single source of truth. The Settings UI form
(Step C) renders checkboxes from `DESCRIPTIONS`. `Api::AuthConcern`
references `Scopes::*` constants by name in `require_scope!` calls.

### 6.3 `Api::AuthConcern`

New concern at `app/controllers/concerns/api/auth_concern.rb`:

Behavior:

1. Extracts `Authorization: Bearer <token>` header. Missing header → 401
   with `{error: "missing_token"}`.
2. Computes HMAC-SHA256 of the plaintext using
   `Rails.application.credentials.dig(:tokens, :pepper)` as the key.
3. Looks up `ApiToken.unscoped.find_by(token_digest: digest)` — `unscoped`
   because the request has no `Current.tenant` yet; the token row defines
   the tenant. Constant-time compare not needed at the DB layer (the
   digest is the lookup key) but the concern uses
   `ActiveSupport::SecurityUtils.secure_compare` for any plaintext-to-
   plaintext fallback path (none in v1, but the helper is wired for the
   future).
4. Reject (401) if: row missing, `revoked?`, `expired?`. Each rejection
   writes one line to `log/auth_audit.log` with the reason.
5. On success: `Current.token = api_token`, `Current.tenant =
   api_token.tenant`, `Current.user = api_token.user`,
   `api_token.touch_used!`. Append a success line to the audit log.
6. Provide `require_scope!(scope)` instance method that raises
   `Api::Forbidden` (returns 403 with `{error: "insufficient_scope",
   required: scope}`) if `Current.token.scopes` does not include the
   given scope.

Rescue points in `ApplicationController` (or the `Api::Base` parent if
that class exists; otherwise add it):

- `rescue_from Api::Unauthorized` → 401 JSON.
- `rescue_from Api::Forbidden` → 403 JSON.

### 6.4 Application points

**Web Puma JSON endpoints.** Mix `Api::AuthConcern` into every controller
under `app/controllers/api/**`. Currently that's `Api::FootagesController`
(Phase 4). Each action in those controllers calls `require_scope!(...)`
with the appropriate scope:

- Read actions (`index`, `show`) → `Scopes::PROJECT_READ` (footage is
  project workspace data; read-only listing).
- Write actions (`create`, `update`, `destroy`, footage import endpoints)
  → `Scopes::PROJECT_WRITE`.

**`Mcp::RackApp`.** Replace the comment at line 8 ("Auth: open for now")
with a call into the auth concern. Because `Mcp::RackApp` is a Rack app,
not a Rails controller, the concern is reorganized so the bearer-extract
+ digest-lookup + Current-population logic lives in a plain Ruby class
(`Api::TokenAuthenticator`) that both the controller concern and the Rack
app call into. The controller concern is a thin shim; the Rack app calls
the same authenticator.

Pseudo-shape of the rack app change:

```ruby
def call(env)
  result = Api::TokenAuthenticator.call(env)
  return result.to_rack_response if result.failure?

  Current.token  = result.token
  Current.tenant = result.token.tenant
  Current.user   = result.token.user

  @mcp_server.call(env)
ensure
  Current.reset
end
```

### 6.5 MCP tool scope wiring

Every MCP tool's `call` method gains a `require_scope!(<scope>)` at the
top. The mapping (the authoritative version of which lives in `docs/mcp.md`,
written by Step C):

- `dev:list_docs`, `dev:read_doc` → `Scopes::DEV_READ`.
- `dev:save_note` → `Scopes::DEV_WRITE`.
- All channel / video / dashboard / saved-views read tools (`yt:list_*`,
  `yt:get_*`, `yt:search_*`, etc.) → `Scopes::YT_READ`.
- All channel / video / saved-views mutating tools → `Scopes::YT_WRITE`.
- All channel / video destructive tools (`yt:delete_*`, bulk-delete) →
  `Scopes::YT_DESTRUCTIVE`.

The mapping is implementation-time work — the spec lists the categories;
the exact `case` per tool happens during dispatch.

### 6.6 Throttling

Add `rack-attack` to `Gemfile`. New initializer
`config/initializers/rack_attack.rb` with one rule:

```ruby
Rack::Attack.throttle("auth/failed", limit: 10, period: 5.minutes) do |req|
  req.ip if req.env["pito.auth_failed"] == true
end
```

`Api::TokenAuthenticator` sets `env["pito.auth_failed"] = true` on every
failure path so the throttle counts only failures. 429 response body:
`{error: "rate_limited", retry_after: <seconds>}`.

Configure `Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore
.new(...)` to use the existing Redis instance. Throttle data is per-process
lossy if Redis is down — acceptable; this is a soft defense, not a security
boundary.

### 6.7 Audit log

New logger configured in
`config/initializers/auth_audit_logger.rb`:

```ruby
AUTH_AUDIT_LOGGER = Logger.new(Rails.root.join("log/auth_audit.log"))
AUTH_AUDIT_LOGGER.formatter = ->(severity, time, _, msg) {
  "#{msg}\n"  # JSON line — already formatted at the call site
}
```

Each call site writes one JSON line:

```json
{
  "ts": "2026-05-05T12:34:56.789Z",
  "event": "auth.success",
  "token_id": 7,
  "token_name": "dev",
  "ip": "127.0.0.1",
  "route": "/mcp",
  "scope_required": null,
  "result": "ok"
}
```

Events: `auth.success`, `auth.missing_token`, `auth.invalid_token`,
`auth.revoked_token`, `auth.expired_token`, `auth.insufficient_scope`,
`auth.throttled`. Logrotate is host-side concern, not in this spec.

### 6.8 Credentials addition

Add a `:tokens` block to `Rails.application.credentials`:

```yaml
tokens:
  pepper: <64-char hex; SecureRandom.hex(32) at Step C bootstrap time>
```

Step C is responsible for the actual credential ceremony (`bin/rails
credentials:edit` walkthrough in `docs/setup.md`). Step B just expects the
credential to be readable at request time; if it's missing, the app boots
but the first auth attempt raises a clear `Api::AuthConfigurationMissing`
that 500s with `{error: "auth_misconfigured"}`. (Better than silently
hashing with `nil`.)

### 6.9 Specs

New / updated specs:

- `spec/models/api_token_spec.rb` — replaces
  `spec/models/mcp_access_token_spec.rb`. Coverage: digest generation,
  scope subset validation, `revoked?`, `expired?`, `usable?`,
  `touch_used!` updates `last_used_at`, `generate!` returns plaintext
  exactly once.
- `spec/lib/scopes_spec.rb` — `ALL` matches the constant list, every
  constant has a `DESCRIPTIONS` entry.
- `spec/requests/api/auth_concern_spec.rb` — exercises every reject path
  (missing, invalid, revoked, expired, wrong scope) plus the success path
  through a representative `Api::FootagesController` action. Asserts
  `Current.tenant`, `Current.user`, `Current.token` populated on success.
- `spec/requests/mcp/rack_app_auth_spec.rb` — same matrix against
  `/mcp` (or whatever the Rack mount point is). Asserts unauthenticated
  request returns 401 (was `200` previously).
- `spec/mcp/tools/<each tool>_spec.rb` — extend each existing tool spec
  with a "rejects when token lacks <scope>" example.
- `spec/initializers/rack_attack_spec.rb` — using
  `Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new` in
  test setup, hammer 11 failed requests from one IP, assert the 11th
  returns 429.
- `spec/lib/api/token_authenticator_spec.rb` — unit-test the Rack-level
  authenticator class.

Audit log assertions: capture writes via a `StringIO`-backed logger
fixture; assert the JSON payload shape.

---

## 7. Out of scope

- Token CRUD UI under Settings — Step C.
- `docs/auth.md`, `docs/mcp.md`, `docs/architecture.md` updates — Step C.
- Pepper rotation tooling.
- Doorkeeper / OAuth client flows — Phase 12.
- Per-token rate limits beyond the failed-lookup throttle — Phase 15.
- Argon2 / bcrypt token hashing alternatives.
- Web cookie session work — Phase 12.
- Hooking `Api::AuthConcern` into the Phase 4 `pito footage` CLI client —
  the CLI sends the bearer header already; this step just makes the
  server enforce it.

---

## 8. Acceptance criteria

- [ ] `mcp_access_tokens` table renamed to `api_tokens`, with new columns
      `user_id` (NOT NULL), `scopes` (jsonb, NOT NULL, default `[]`),
      `expires_at` (nullable). `tenant_id` already present from Step A.
- [ ] Migration is reversible.
- [ ] `McpAccessToken` class renamed to `ApiToken`; every caller updated
      (rake tasks, model specs, factory, MCP rack app).
- [ ] `Scopes` module exists at `app/lib/scopes.rb` with the nine
      constants and `ALL` / `DESCRIPTIONS` collections.
- [ ] `Api::TokenAuthenticator` (Rack-level) and `Api::AuthConcern`
      (controller-level) both populate `Current.token` /
      `Current.tenant` / `Current.user` from a valid bearer token.
- [ ] `Mcp::RackApp` rejects unauthenticated requests with 401. Every
      MCP tool rejects requests whose token lacks the required scope
      with 403.
- [ ] Every `Api::*` controller action requires a scope via
      `require_scope!(...)`; missing → 403.
- [ ] `rack-attack` is in the `Gemfile`; failed-token throttle returns
      429 after 10 failures within 5 minutes.
- [ ] `log/auth_audit.log` receives one JSON line per auth event
      (success or failure).
- [ ] `:tokens.pepper` credential block is required at boot (or fails
      loud on first auth attempt with a clear error).
- [ ] All previously-green specs remain green; new specs cover every
      path listed in §6.9.
- [ ] No regression on Web HTML routes — they remain cookie-only and do
      not require a bearer token.
- [ ] Rake-task token CRUD continues to work after the model rename
      (sanity-checked in the manual playbook).
- [ ] Brakeman, bundler-audit, Dependabot — clean (the rack-attack
      addition gets its own audit pass).

---

## 9. Manual playbook

Run after the implementer reports green:

1. `bin/rails credentials:edit` — confirm the `:tokens.pepper` block
   exists (Step C handles the bootstrap script; this step verifies the
   credential is readable).
2. `bin/rails db:migrate` — table renamed, columns added; no errors.
3. `bin/rails console` —
   - `ApiToken` class exists; `McpAccessToken` is undefined.
   - `Scopes::ALL.size == 9`.
4. Mint a test token via the rake task (the existing CRUD path):
   `bin/rails "tokens:create[manual-test,yt:read]"` (or whatever the
   exact task signature is post-rename). Capture plaintext.
5. `curl -i https://app.pitomd.com/api/footages` (no header) → 401 with
   `{"error":"missing_token"}`.
6. `curl -i -H "Authorization: Bearer <token>" https://app.pitomd.com/api/footages` →
   either 403 (footage uses `project:read`, our token has `yt:read`) or
   200 if you minted with `project:read`. The point is: scope check
   fires.
7. Mint a token with `dev:read` only. `curl -i -H "Authorization:
   Bearer <token>" https://mcp.pitomd.com` POST a `dev:list_docs`
   request → 200. POST a `yt:list_channels` request → 403 with
   `{"error":"insufficient_scope","required":"yt:read"}`.
8. Revoke the token via rake (`bin/rails "tokens:revoke[<id>]"`).
   Re-run step 7 → 401 with `{"error":"revoked_token"}`.
9. Hammer 11 bad requests:
   `for i in $(seq 1 11); do curl -i -H "Authorization: Bearer bad" https://mcp.pitomd.com; done` →
   the 11th returns 429.
10. `tail log/auth_audit.log` — JSON lines per event, one per request.
11. Visit `/`, `/channels`, `/videos` in the browser — still load
    without any token (cookie-only path is untouched).
12. `bundle exec rspec` — green.

---

## 10. File-scope inventory

Implementer (Lane 1 rails-impl) touches:

- `db/migrate/<ts>_rename_mcp_access_tokens_to_api_tokens.rb`.
- `db/migrate/<ts>_add_user_scopes_expires_to_api_tokens.rb`.
- `app/models/api_token.rb` (renamed from `mcp_access_token.rb`).
- `app/lib/scopes.rb` — new.
- `app/lib/api/token_authenticator.rb` — new.
- `app/controllers/concerns/api/auth_concern.rb` — new.
- `app/controllers/application_controller.rb` — `rescue_from` Api errors.
- `app/controllers/api/footages_controller.rb` (and any other `Api::*`)
  — include the concern, add `require_scope!` per action.
- `app/mcp/rack_app.rb` — replace "auth open" with concern call.
- `app/mcp/tools/**/*.rb` — `require_scope!(...)` at top of each `call`.
- `config/initializers/rack_attack.rb` — new.
- `config/initializers/auth_audit_logger.rb` — new.
- `Gemfile`, `Gemfile.lock` — add `rack-attack`.
- `lib/tasks/tokens.rake` (or whatever the existing CRUD task is named)
  — update class references.
- `spec/models/api_token_spec.rb` (renamed).
- `spec/lib/scopes_spec.rb` — new.
- `spec/lib/api/token_authenticator_spec.rb` — new.
- `spec/requests/api/auth_concern_spec.rb` — new.
- `spec/requests/mcp/rack_app_auth_spec.rb` — new (or extend existing).
- `spec/mcp/tools/**` — extend each tool spec with a scope-reject case.
- `spec/initializers/rack_attack_spec.rb` — new.
- `spec/factories/api_tokens.rb` (renamed).

Out of bounds for this step:

- `app/views/**` — Step C owns the Settings UI.
- `db/seeds.rb` — Step C adds the dev token seed.
- `docs/**` — Step C owns all doc updates.
- `extras/cli/**` — CLI client work is later phases.
- `app/controllers/settings/**` — Step C.

## 11. Open questions

- Confirm `Mcp::RackApp` exposes the request env in a shape
  `Api::TokenAuthenticator` can consume. If the rack app uses a
  hand-rolled JSON-RPC dispatch that doesn't surface request headers
  cleanly, the implementer pauses and reports — the authenticator's
  contract assumes standard Rack `env`.
- Confirm the existing rake-task name pattern. The spec assumes
  `tokens:create` / `tokens:revoke`; if the existing tasks are
  `mcp_tokens:*`, decide rename now (consistency with `ApiToken`) or
  defer.
- Confirm the `Api::FootagesController` actions. If any action shouldn't
  require auth (e.g., a public health-check endpoint), it gets `skip_*`
  explicitly — implementer flags any candidate.
