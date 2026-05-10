# Phase 10 — Collapse MCP Scope Catalog to `dev` + `app`

> **Status:** dispatched 2026-05-10. Second concrete realignment dispatch
> following Phase 8 (Tenant Drop). Implementation lane: **rails** (single lane —
> no Rust, no Astro this round).
>
> **Cross-references:**
>
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — primary ADR; the
>   catalog collapse, the old → new mapping, and the strip-on-release commitment
>   all live there.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — Phase 8
>   prerequisite (this spec assumes the tenant drop has landed).
> - `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — Doorkeeper
>   survives; Phase 10 reconfigures its scope set, not its existence.
> - `docs/realignment-2026-05-09.md` — work unit 2.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   §"Open questions" #3 — Phase 8 left the seed dev token at the 6-scope shape;
>   Phase 10 collapses it.
> - `CLAUDE.md` — top-level project rules (yes/no booleans, secrets in
>   credentials, no JS confirms, etc.).

## Goal

Translate ADR 0004's commitment into code. Collapse `Scopes::ALL` from the
current nine entries to **two**: `dev` and `app`. Update every callsite — MCP
tool `require_scope!` calls, the `ApiToken` model, the seed dev token, the
Doorkeeper `default_scopes` / `optional_scopes` declaration, the soft- clip
monkey-patch's expectations, and every spec that asserts against the old
catalog. Add a build-time strip-on-release mechanism so production builds
suppress the `dev` scope (and the `dev`-scoped tools) without shipping any
per-environment tool registry forks.

The collapse is intentionally narrow: tool descriptions, the bulk-as- foundation
pattern, the two-step confirm flow, the request envelope shapes, and the rest of
the MCP surface stay unchanged. Only the scope strings travelling through the
system change.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                           |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Q1  | **Final catalog:** two scopes, `dev` and `app`. No read/write split. No further granularity. `Scopes::ALL` becomes exactly `[DEV, APP]`. `Scopes::DESCRIPTIONS` shrinks to two entries.                                                                                                                                                                                                                            |
| Q2  | **Old → new mapping:** `dev:read` + `dev:write` + `website:read` + `website:write` → `dev`. `yt:read` + `yt:write` + `yt:destructive` + `project:read` + `project:write` → `app`. (Mirrors ADR 0004's table.)                                                                                                                                                                                                      |
| Q3  | **Token rotation:** **rotate-on-deploy.** Existing `ApiToken` rows are revoked at migration time (or dropped — see "Token migration" below). Existing Doorkeeper `OauthAccessToken` / `OauthAccessGrant` rows are revoked at the same time. The user re-pairs Claude Mobile + Web MCP once after deploy. Single user, trivially safe. (Per master agent's 2026-05-10 decision.)                                    |
| Q4  | **Strip-on-release mechanism:** **env-config flag** at `Rails.application.config.x.mcp.expose_dev_scope`. Default `true` for development/test, default `false` for production. The flag gates: (a) `dev` membership in `Scopes::ALL` (and therefore in Doorkeeper's `optional_scopes`), and (b) registration of the `dev`-scoped tools (`list_docs`, `read_doc`, `save_note`) into the MCP server's tool registry. |
| Q5  | **Soft-clip monkey-patch:** `config/initializers/doorkeeper_scope_clip.rb` survives. It already operates on whatever `Scopes::ALL` returns — its math (`requested ∩ app.scopes ∩ server.scopes`) is catalog-agnostic. No code changes required, but the spec's behavior under the new 2-scope catalog gets explicit test coverage (see "Test sweep").                                                              |
| Q6  | **Seed dev `ApiToken`:** collapse from `[DEV_READ, DEV_WRITE, YT_READ, YT_WRITE, PROJECT_READ, PROJECT_WRITE]` to `[Scopes::DEV, Scopes::APP]`. The dev-token banner output (the "save this now" header) is otherwise unchanged.                                                                                                                                                                                   |
| Q7  | **Tool ↔ scope mapping is exhaustive in this spec.** Every `app/mcp/tools/*.rb` is listed in the table below with its old scope and its new scope. The implementation agent does not have to re-derive the mapping — it has to apply it.                                                                                                                                                                           |
| Q8  | **Backward-compat lookup:** **none.** A request that authenticates with a token whose `scopes` jsonb literally contains `"dev:read"` is rejected as `insufficient_scope`. The `ApiToken` validation (see below) refuses to save such a row. The migration drops every legacy token (Q3).                                                                                                                           |
| Q9  | **Settings UI scope picker:** out of scope here — `/settings/tokens` may be touched by a separate post-spec follow-up if its checkbox tree does not collapse trivially. The implementation agent reports the touchpoint in the log; if a one-line tweak suffices it ships with this dispatch, otherwise the agent flags it.                                                                                        |

## Migration posture (LOCKED)

**Destructive-and-reseed**, mirroring ADR 0003's posture and Phase 8's posture:

- No production data exists. Pito has not shipped to anyone outside the
  developer's machine.
- The migration drops every existing `ApiToken` row, every existing
  `OauthAccessToken`, every existing `OauthAccessGrant`. (Doorkeeper
  `OauthApplication` rows stay — those carry only the per-app scope whitelist,
  which is rewritten in-place.)
- The seed re-mints exactly one dev `ApiToken` with the new 2-scope set.
- ADR 0003 + ADR 0004 + git history are the only artifacts of the prior 9-scope
  shape. No data preservation. No backfill.
- **Rollback is explicitly NOT supported.** The migration's `down` may exist for
  Rails bookkeeping but does not have to restore anything. Document in the
  migration body.

## Files touched

### Scope catalog

- **Edit:** `app/lib/scopes.rb` — full rewrite. Final shape:

  ```ruby
  module Scopes
    DEV = "dev"
    APP = "app"

    DESCRIPTIONS = {
      DEV => "Dev tooling — knowledge base read + capture (docs/).",
      APP => "Application data — channels, videos, projects, calendar, ...",
    }.freeze

    # Guarded by a config flag so production builds drop `dev`.
    def self.all
      base = [APP]
      base.unshift(DEV) if Rails.application.config.x.mcp.expose_dev_scope
      base.freeze
    end

    # Frozen array kept as a constant for the static call sites that
    # cannot read the config (initializers running at boot before the
    # flag is set). Doorkeeper's initializer is one such caller — it
    # reads `Scopes::ALL` directly. The constant is computed at boot
    # using the same flag, so the boot-time value matches what `all`
    # returns at runtime in the same process.
    ALL = all
  end
  ```

  The two-tier shape (`Scopes.all` method + frozen `ALL` constant) is required
  because Doorkeeper's initializer (`config/initializers/doorkeeper.rb`) reads
  `Scopes::ALL` at boot; the runtime `Mcp::ToolAuth.require_scope!` callers
  reference the constants directly. Both paths see the same per-environment
  value because the constant is computed once during boot, after
  `Rails.application.config.x.mcp.expose_dev_scope` has been set in the
  environment file. Implementation agent owns the final ergonomics; the
  requirement is: under `expose_dev_scope=true`,
  `Scopes::ALL == [Scopes::DEV, Scopes::APP]`; under `=false`,
  `Scopes::ALL == [Scopes::APP]`.

### Strip-on-release flag

- **Edit:** `config/application.rb` (or a new
  `config/initializers/mcp_expose_dev_scope.rb`) — declare the configuration
  namespace:
  ```ruby
  config.x.mcp = ActiveSupport::OrderedOptions.new
  config.x.mcp.expose_dev_scope = true # development default
  ```
  Implementation agent picks the host file (recommendation: a dedicated
  initializer keeps the config surface discoverable).
- **Edit:** `config/environments/production.rb` — set
  `config.x.mcp.expose_dev_scope = false`. Add a one-line explanatory comment.
- **Edit:** `config/environments/development.rb` — set
  `config.x.mcp.expose_dev_scope = true` (explicit, even though it matches the
  application-level default).
- **Edit:** `config/environments/test.rb` — set
  `config.x.mcp.expose_dev_scope = true`. The test suite covers both modes by
  stubbing the flag in specific examples (see "Test sweep").

### Doorkeeper config

- **Edit:** `config/initializers/doorkeeper.rb`:
  - Replace the existing scopes block:
    ```ruby
    default_scopes Scopes::DEV_READ
    optional_scopes(*(Scopes::ALL - [ Scopes::DEV_READ ]))
    ```
    with:
    ```ruby
    # `Scopes::ALL` already reflects the strip-on-release flag.
    default_scopes(*Scopes::ALL)
    optional_scopes
    ```
    Both scopes are defaults: a client requesting no `scope` parameter gets
    every scope it is allowed to request (still clipped to the application's own
    `scopes` whitelist by the soft-clip monkey-patch). The architect's choice of
    "both as defaults" reflects the new catalog's intent — there is no
    fine-grained read/write opt-in to represent.
  - Drop the comment line:
    ```
    # `Scopes::ALL` is the single source of truth (Phase 5 catalog).
    ```
    Replace with:
    ```
    # `Scopes::ALL` is the single source of truth. Catalog: `dev` + `app`.
    # `dev` is stripped from the catalog when
    # `Rails.application.config.x.mcp.expose_dev_scope == false`
    # (production). Per ADR 0004.
    ```
  - The `enforce_configured_scopes`, `force_pkce`, `grant_flows`,
    `skip_authorization`, and `force_ssl_in_redirect_uri` blocks all stay as-is.

### Soft-clip monkey-patch

- **Verify:** `config/initializers/doorkeeper_scope_clip.rb` — no code changes
  required. The patch's math operates on whatever `Doorkeeper::Server.scopes`
  (sourced from `default_scopes` ∪ `optional_scopes`) and the per-application
  `scopes` whitelist contain at runtime. Under the new 2-scope catalog it
  correctly clips:
  - `dev:read app:write` (legacy-style request from a Claude.ai auto-walked
    client) → server has no `dev:read` / `app:write`, so `validate_scopes`
    rejects (rules: every requested scope must be in the server catalog). This
    is **intentional** — legacy scope strings are no longer recognized; clients
    must request `dev` / `app`.
  - `dev app` (correct request) → intersected against the application's
    whitelist; succeeds when both are whitelisted.
  - Empty scope request → falls through to defaults (`Scopes::ALL`), per the
    existing fallback.

  The behaviour is what we want; the test sweep adds explicit examples asserting
  it under the new catalog so the next person reading the code does not have to
  re-derive the math.

### MCP tool scope declarations

The implementation agent walks every file in `app/mcp/tools/*.rb` and applies
the mapping in the table below. Each tool's `Scopes::*` constant reference is
updated to one of the two new constants. The `Scopes::DEV` / `Scopes::APP`
constants land in `app/lib/scopes.rb` per the catalog rewrite above; every tool
references one of them.

| Tool file                            | `tool_name`         | Old `Scopes::*` constant                                            | New constant                                   |
| ------------------------------------ | ------------------- | ------------------------------------------------------------------- | ---------------------------------------------- |
| `app/mcp/tools/list_channels.rb`     | `list_channels`     | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/get_channel.rb`       | `get_channel`       | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/create_channel.rb`    | `create_channel`    | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/update_channel.rb`    | `update_channel`    | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/list_videos.rb`       | `list_videos`       | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/get_video.rb`         | `get_video`         | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/create_video.rb`      | `create_video`      | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/update_video.rb`      | `update_video`      | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/get_dashboard.rb`     | `get_dashboard`     | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/search_content.rb`    | `search`            | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/delete_records.rb`    | `delete_records`    | `Scopes::YT_DESTRUCTIVE`                                            | `Scopes::APP`                                  |
| `app/mcp/tools/sync_records.rb`      | `sync_records`      | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/manage_settings.rb`   | `manage_settings`   | `Scopes::YT_READ` (read branch) / `Scopes::YT_WRITE` (write branch) | `Scopes::APP` (single branch — see note below) |
| `app/mcp/tools/list_saved_views.rb`  | `list_saved_views`  | `Scopes::YT_READ`                                                   | `Scopes::APP`                                  |
| `app/mcp/tools/create_saved_view.rb` | `create_saved_view` | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/delete_saved_view.rb` | `delete_saved_view` | `Scopes::YT_WRITE`                                                  | `Scopes::APP`                                  |
| `app/mcp/tools/list_docs.rb`         | `list_docs`         | `Scopes::DEV_READ`                                                  | `Scopes::DEV`                                  |
| `app/mcp/tools/read_doc.rb`          | `read_doc`          | `Scopes::DEV_READ`                                                  | `Scopes::DEV`                                  |
| `app/mcp/tools/save_note.rb`         | `save_note`         | `Scopes::DEV_WRITE`                                                 | `Scopes::DEV`                                  |

**Note on `manage_settings`:** today the tool branches the required scope
between `Scopes::YT_READ` (no `updates` arg — view-only) and `Scopes::YT_WRITE`
(with `updates` — mutating). With the read/write split gone, both branches
collapse to `Scopes::APP`. Drop the conditional; emit a single
`require_scope!(Scopes::APP)` at the top of `call`. The implementation agent
must verify the existing test that covers the read-vs-write scope branching
(`spec/mcp/tools/manage_settings_spec.rb` or similar) is updated accordingly.

**Note on tools added since this spec was written:** if any tool not in the
table above has landed before the implementation agent picks up this dispatch,
the agent applies the same rule:

- Tools under `dev:*` (or with `Scopes::DEV_READ` / `Scopes::DEV_WRITE` in their
  `require_scope!` call) → `Scopes::DEV`.
- Every other tool → `Scopes::APP`.

The agent surfaces any new tools it sweeps in `log.md`.

### Tool registry — strip-on-release

- **Edit:** `app/mcp/pito_server.rb` (or wherever the MCP server is built and
  tools are registered) — gate the `register` calls for the three `dev`-scoped
  tools (`Mcp::Tools::ListDocs`, `Mcp::Tools::ReadDoc`, `Mcp::Tools::SaveNote`)
  on `Rails.application.config.x.mcp.expose_dev_scope`. Concretely:
  ```ruby
  if Rails.application.config.x.mcp.expose_dev_scope
    server.tool Mcp::Tools::ListDocs
    server.tool Mcp::Tools::ReadDoc
    server.tool Mcp::Tools::SaveNote
  end
  ```
  Implementation agent picks the exact API the `mcp` gem exposes (`tool` /
  `register_tool` / `tools <<`); the requirement is that under
  `expose_dev_scope=false`, calling `tools/list` over the JSON-RPC surface
  returns a list that does NOT include `list_docs`, `read_doc`, or `save_note`.
- **No change** to `app/mcp/tool_auth.rb` — the helper's API is generic
  (`require_scope!(scope)` accepts any scope string). The `Current.token.scopes`
  array carries `"dev"` / `"app"` after this dispatch lands; the helper's
  `Array(token.scopes).include?(scope.to_s)` check works without modification.
- **No change** to `app/mcp/rack_app.rb` — the rack app's token-resolution path
  is scope-agnostic. (Phase 8 already removed the tenant pinning; no further
  surgery is needed here.)

### `ApiToken` model

- **Edit:** `app/models/api_token.rb`:
  - The `scopes_subset_of_catalog` validation continues to work via
    `Array(scopes) - Scopes::ALL`. Under the new catalog this rejects any legacy
    scope string (`dev:read`, `yt:write`, etc.). No code change required — the
    change in `Scopes::ALL` flows through.
  - **Add a guard:** under
    `Rails.application.config.x.mcp.expose_dev_scope == false`, a request to
    mint a token with `scopes: ["dev"]` (or any scope set that includes `"dev"`)
    must be rejected. The architect's preferred shape:
    ```ruby
    validate :dev_scope_only_when_exposed
    # ...
    def dev_scope_only_when_exposed
      return if Rails.application.config.x.mcp.expose_dev_scope
      return unless Array(scopes).include?(Scopes::DEV)
      errors.add(:scopes, "cannot include 'dev' in this build")
    end
    ```
    The implementation agent owns the final wording.
  - The `generate!` signature stays as Phase 8 left it
    (`generate!(user:, name:, scopes:, expires_at: nil)`). No `tenant:` keyword
    (already gone after Phase 8).

### Database migration — token revocation

- **New:** `db/migrate/<NN>_revoke_tokens_for_scope_simplification.rb`. Single
  migration. Scope:
  - `ApiToken.update_all(revoked_at: Time.current)` for every row whose
    `revoked_at` is currently `NULL`. (Soft-revoke; rows stay for audit parity
    with the rest of the auth model.)
  - `Doorkeeper::AccessToken.update_all(revoked_at: Time.current)` for every row
    whose `revoked_at` is currently `NULL`.
  - `Doorkeeper::AccessGrant.update_all(revoked_at: Time.current)` for every row
    whose `revoked_at` is currently `NULL`.
  - `OauthApplication` rows: leave the rows themselves alone, but rewrite their
    `scopes` column. Each application's `scopes` string (Doorkeeper stores it as
    a space-separated string) is mapped via the same Q2 table:
    - `dev:read`, `dev:write`, `website:read`, `website:write` → `dev`
    - `yt:read`, `yt:write`, `yt:destructive`, `project:read`, `project:write` →
      `app`
    - Duplicates collapsed; final string is `"dev"`, `"app"`, or `"dev app"`
      (joined by a single space). An application with no surviving scope is
      rewritten to `"app"` (defensive default — no legitimate application should
      have only legacy scopes that all mapped to nothing, but a
      future-website-only app would have `[website:read, website:write]` →
      `[dev]` which is fine).
    - Implementation agent owns the in-Ruby mapping; the migration body iterates
      `OauthApplication.find_each` and writes the rewritten `scopes` string with
      `update_columns(scopes: new_scopes)` to skip validation (which would,
      post-migration, only accept the new catalog values).
  - The migration's body documents in a comment block: "Per ADR 0004, the scope
    catalog collapses from 9 to 2 entries. Existing tokens are revoked; users
    re-pair Claude Mobile + Web MCP after deploy. OauthApplication scope
    whitelists are rewritten in-place. Rollback is not supported — the prior
    9-scope catalog is gone from the code."
- **`db/schema.rb`:** no expected change. (No column adds / drops.)

### Seed update

- **Edit:** `db/seeds.rb` (assumes Phase 8 has landed; the `tenant_name` /
  `tenant_slug` lines are already gone):
  - Locate the dev `ApiToken` mint block (today around the
    `ApiToken.exists?(name: "dev")` guard).
  - Replace the scope list:
    ```ruby
    scopes: [
      Scopes::DEV_READ, Scopes::DEV_WRITE,
      Scopes::YT_READ, Scopes::YT_WRITE,
      Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
    ]
    ```
    with:
    ```ruby
    scopes: Scopes::ALL.dup
    ```
    (or, equivalently, `[Scopes::DEV, Scopes::APP]` — implementation agent's
    preference; `Scopes::ALL.dup` is preferred because it automatically tracks
    the strip-on-release flag — under production-style seeding the dev token
    would mint with `[Scopes::APP]` only, which is the correct behavior.)
  - The seed's banner output (the "Dev token minted (save this now …)" block)
    stays unchanged.
  - The "WARNING: credentials :owner block missing" warning copy stays
    unchanged.

### Documentation impact (post-implementation; dispatched separately to docs-keeper)

The Rails implementation does NOT touch these files. After the rails-impl
dispatch lands and the user validates, the master agent dispatches
`pito-docs-keeper` against this list:

- `docs/auth.md` §2 (scope catalog) — full rewrite. New table:

  | Scope | Description                                                            |
  | ----- | ---------------------------------------------------------------------- |
  | `dev` | Dev knowledge base read + capture (docs/, notes). Stripped on release. |
  | `app` | Application data — channels, videos, projects, calendar, etc.          |

- `docs/auth.md` §3 (tool / endpoint scope map) — collapse the per-tool table
  from the 5-column shape to 2 (tool / scope).
- `docs/auth.md` §7 (bootstrap ceremony) — update the dev token's scope set
  description to `[dev, app]`.
- `docs/mcp.md` §"Scope-per-tool table" — full rewrite using the new mapping
  (matches the table in this spec's "MCP tool scope declarations" section).
- `docs/mcp.md` §"Token Model" — drop the line "see `app/lib/scopes.rb`; see
  `docs/auth.md` §2" reference if it lists the old catalog.
- `CLAUDE.md` — verify the project-wide rules section does not list the scope
  catalog inline. (Spot check at dispatch time.)
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — flip the status
  header from "Accepted" to "Implemented" with the date the implementation lands
  and the commit SHA.

These edits are listed here for traceability; they are NOT part of the
rails-impl dispatch's file scope.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Catalog

- [ ] `Scopes::ALL` (development env) returns exactly `["dev", "app"]` in array
      order.
- [ ] `Scopes::ALL` (production env, with `expose_dev_scope = false`) returns
      exactly `["app"]`.
- [ ] `Scopes::DEV == "dev"` and `Scopes::APP == "app"` (string values match the
      on-disk constants).
- [ ] `Scopes::DESCRIPTIONS` has exactly two entries.
- [ ] `git grep 'Scopes::DEV_READ\|Scopes::DEV_WRITE\|Scopes::YT_READ\|Scopes::YT_WRITE\|Scopes::YT_DESTRUCTIVE\|Scopes::WEBSITE_READ\|Scopes::WEBSITE_WRITE\|Scopes::PROJECT_READ\|Scopes::PROJECT_WRITE' app/ lib/ spec/`
      returns zero matches.
- [ ] `git grep '"dev:read"\|"dev:write"\|"yt:read"\|"yt:write"\|"yt:destructive"\|"website:read"\|"website:write"\|"project:read"\|"project:write"' app/ lib/ spec/ db/ config/`
      returns zero matches outside the migration body and historical comment
      context (which the implementation agent flags in advance).

### Strip-on-release

- [ ] `Rails.application.config.x.mcp.expose_dev_scope` is defined (test loads
      cleanly with no `NoMethodError`).
- [ ] In `RAILS_ENV=development`, the value is `true`.
- [ ] In `RAILS_ENV=test`, the value is `true`.
- [ ] In `RAILS_ENV=production`, the value is `false`.
- [ ] Stubbing `expose_dev_scope = false` in a test makes `Scopes::ALL` return
      `["app"]` and the MCP server's `tools/list` response (over the rack app)
      drops `list_docs`, `read_doc`, `save_note`.

### Doorkeeper

- [ ] `config/initializers/doorkeeper.rb` declares
      `default_scopes(*Scopes::ALL)` and an empty `optional_scopes`.
- [ ] An OAuth `/oauth/authorize` request that requests `scope=dev app` against
      an application whitelisted for both succeeds.
- [ ] An OAuth `/oauth/authorize` request that requests `scope=dev:read`
      (legacy) is rejected (`invalid_scope` redirect or 4xx).
- [ ] An OAuth `/oauth/authorize` request that requests `scope=dev` against an
      application whitelisted only for `app` redirects with
      `error=invalid_scope` (no overlap).
- [ ] An OAuth `/oauth/authorize` request that requests `scope=dev app` against
      an application whitelisted for `dev app` (Claude.ai shape) renders the
      consent screen.
- [ ] In production env (with `expose_dev_scope = false`), an OAuth request for
      `scope=dev` is rejected by the soft-clip monkey-patch (the scope is not in
      `Scopes::ALL == ["app"]`).

### MCP tool dispatch

- [ ] A token with `scopes: ["dev"]` only, calling `list_docs` → succeeds (200 /
      valid response).
- [ ] A token with `scopes: ["dev"]` only, calling `save_note` → succeeds.
- [ ] A token with `scopes: ["dev"]` only, calling `list_channels` →
      `insufficient_scope` error (403-equivalent envelope).
- [ ] A token with `scopes: ["app"]` only, calling `list_channels` → succeeds.
- [ ] A token with `scopes: ["app"]` only, calling `list_docs` →
      `insufficient_scope`.
- [ ] A token with `scopes: ["dev", "app"]`, calling any tool in the table →
      succeeds (subject to other tool-specific validations).
- [ ] A token with a legacy scope string like `["dev:read"]` cannot be saved
      (validation rejects); existing rows with such strings have been revoked by
      the migration.
- [ ] In production env (with `expose_dev_scope = false`), the MCP `tools/list`
      JSON-RPC response does NOT contain `list_docs`, `read_doc`, or
      `save_note`.
- [ ] In production env, even a token whose `scopes` array contains `"dev"`
      (somehow surviving the migration — e.g., user-minted between deploy +
      production restart) is unable to call `list_docs`: either the tool isn't
      registered (preferred), or the tool's `require_scope!` rejects when
      `Scopes::ALL` doesn't contain `"dev"`. The implementation agent confirms
      which enforcement layer fires; the test asserts the observable behavior
      either way.

### Database / migration

- [ ] After the migration runs, every previously-active `ApiToken` row has
      `revoked_at` set.
- [ ] After the migration runs, every previously-active
      `Doorkeeper::AccessToken` row has `revoked_at` set.
- [ ] After the migration runs, every previously-active
      `Doorkeeper::AccessGrant` row has `revoked_at` set.
- [ ] After the migration runs, every `OauthApplication.scopes` string contains
      only `"dev"`, `"app"`, or a space-separated combination of the two — never
      any legacy scope.
- [ ] `bin/rails db:migrate` runs cleanly on a freshly-seeded Phase-8 database.

### Seed

- [ ] After `bin/rails db:seed` (development env), the dev `ApiToken` has
      `scopes == ["dev", "app"]`.
- [ ] After `bin/rails db:seed` (production env, with the strip-on- release flag
      flipped), the dev `ApiToken` either is not minted (preferred — production
      seeds skip the dev token) or has `scopes == ["app"]`. Implementation agent
      picks the cleaner path; spec asserts whichever behavior is implemented.
- [ ] `bin/rails db:seed` is still idempotent — running twice in a row leaves
      the database in the same state.

### Tests

- [ ] `bundle exec rspec` passes after the sweep. Spec count delta is reported
      in `log.md` (some IDOR-era specs are gone post-Phase-8; Phase 10 should
      remove or update specs that asserted against the 9-scope catalog).
- [ ] Every new test enumerated in "Test sweep" below passes.
- [ ] No spec references a legacy scope constant (`Scopes::DEV_READ` etc.) or
      string (`"dev:read"` etc.). Verified via `git grep`.

## Test sweep

The implementation agent owns the full sweep. The enumeration below is
exhaustive; any spec the agent touches must end in one of the three buckets
(delete / update / add).

### Specs to update

| Path                                                                       | Edit                                                                                                                                                                                                                                                                                        |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/lib/scopes_spec.rb` (or `spec/models/scopes_spec.rb`)                | Full rewrite for the 2-scope catalog. New test list below under "New tests".                                                                                                                                                                                                                |
| `spec/models/api_token_spec.rb`                                            | Drop the legacy 9-scope membership tests; replace with the new 2-scope tests below. Add the strip-on-release validation test (legacy `dev` rejection in prod).                                                                                                                              |
| `spec/requests/oauth_scope_clip_spec.rb`                                   | Update every reference from `Scopes::DEV_READ` / `Scopes::PROJECT_READ` / etc. to `Scopes::DEV` / `Scopes::APP`. Verify the soft-clip behavior under the new catalog. The structural assertions (consent screen renders, error redirect on no-overlap) stay; only the scope strings change. |
| Every `spec/mcp/tools/*_spec.rb`                                           | Update each tool's scope assertion to `Scopes::APP` (or `Scopes::DEV` for the three Dev-KB tools). Drop the read/write distinction tests on `manage_settings_spec.rb`.                                                                                                                      |
| `spec/mcp/tool_auth_spec.rb`                                               | Update the example token scope arrays to the new strings. Add the "legacy scope string is rejected" example.                                                                                                                                                                                |
| `spec/requests/api/auth_spec.rb` (and any sibling auth specs)              | Update the example scope arrays.                                                                                                                                                                                                                                                            |
| `spec/factories/api_tokens.rb`                                             | Update the default `scopes` array to `[Scopes::DEV, Scopes::APP]`. Update any traits that name specific scopes.                                                                                                                                                                             |
| `spec/factories/oauth_applications.rb`                                     | Update the default `scopes` string to `"dev app"` (or the explicit constants joined). Update any traits.                                                                                                                                                                                    |
| `spec/db/seeds_spec.rb` (introduced in Phase 8)                            | Update the dev-token assertion: scopes are now `["dev", "app"]`, not the 6-element legacy list.                                                                                                                                                                                             |
| `lib/tasks/tokens.rake` (and `spec/lib/tasks/tokens_spec.rb` if it exists) | Update any embedded help text / examples that reference legacy scope names. The rake task accepts a `+`-separated list — under the new catalog the realistic invocation is `bin/rails 'tokens:create[my-mobile,dev+app]'`.                                                                  |

### New tests to add (exhaustive coverage mandate)

The implementation agent writes these. Each is named explicitly so the reviewer
can check existence + behavior without guesswork.

#### `spec/lib/scopes_spec.rb` (full rewrite)

- **Catalog shape:**
  - `it "exposes Scopes::DEV as 'dev'"`.
  - `it "exposes Scopes::APP as 'app'"`.
  - `it "has no read/write split constants"` — assert
    `defined?(Scopes::DEV_READ)` is `nil`, same for every other legacy constant.
    (Boundary test that the rewrite was complete.)
- **`Scopes::ALL`:**
  - `it "in test/development env, returns ['dev', 'app']"`.
  - `it "in production env (with expose_dev_scope=false), returns ['app']"` —
    stub `Rails.application.config.x.mcp.expose_dev_scope = false`, re-evaluate,
    assert.
  - `it "is frozen"`.
- **`Scopes::DESCRIPTIONS`:**
  - `it "has a non-empty description for DEV"`.
  - `it "has a non-empty description for APP"`.
  - `it "has exactly two entries"`.

#### `spec/models/api_token_spec.rb` (additions)

- **Validation under the new catalog:**
  - `it "accepts scopes: ['dev']"`.
  - `it "accepts scopes: ['app']"`.
  - `it "accepts scopes: ['dev', 'app']"`.
  - `it "rejects scopes: ['foo']"` (unknown).
  - `it "rejects scopes: ['dev:read']"` (legacy string — explicit boundary).
  - `it "rejects scopes: ['yt:read']"` (legacy string — explicit boundary).
  - `it "rejects scopes: []"` (empty — preserved from existing coverage).
  - `it "rejects scopes: ['dev', 'dev']"` (duplicates) — implementation agent's
    call whether to accept or reject; spec encodes the choice. Recommendation:
    **accept and dedupe on save** to match the Doorkeeper application scopes
    behavior.
- **Strip-on-release validation:**
  - `it "rejects scopes: ['dev'] when expose_dev_scope is false"` — stub the
    flag to false; build a token with `[Scopes::DEV]`; assert `not_to be_valid`
    and the error mentions `"dev"`.
  - `it "rejects scopes: ['dev', 'app'] when expose_dev_scope is false"` — same
    setup; the presence of `dev` is what triggers the rejection.
  - `it "accepts scopes: ['app'] when expose_dev_scope is false"` — happy path
    under the production-style flag.

#### `spec/mcp/tool_auth_spec.rb` (additions)

- `it "rejects a request when the token's scopes only contain a legacy string"`
  — stub `Current.token.scopes = ["dev:read"]`; call
  `Mcp::ToolAuth.require_scope!(Scopes::DEV)`; assert an `insufficient_scope`
  Response is returned. (Defense-in-depth — the validation should already
  prevent such a row from being saved, but the guard at runtime ensures a
  hand-crafted SQL update can't smuggle legacy access.)

#### `spec/requests/oauth_scope_clip_spec.rb` (additions)

- `it "issues 'dev' alone when requested matches"` — application whitelisted for
  `"dev app"`, request `scope=dev`; final issued scope is `"dev"`.
- `it "issues 'app' alone when requested matches"` — same shape, request
  `scope=app`; issued scope is `"app"`.
- `it "issues 'dev app' when requested matches"`.
- `it "clips legacy scope strings out (legacy 'dev:read' is rejected)"` —
  application whitelisted for `"dev app"`, request `scope=dev:read`; redirect
  with `error=invalid_scope` (the requested scope is not in `Scopes::ALL`).
- `it "handles Claude.ai's auto-walked scope set: requests 'dev app' against an app declaring 'dev app' and accepts"`
  — happy path; the consent screen renders.
- `it "rejects an authorize request for 'dev' under expose_dev_scope=false"` —
  stub the production flag; even an application whitelisted for `"dev app"`
  cannot get a `dev` scope issued because the server catalog drops it; redirect
  with `error=invalid_scope`.

#### `spec/requests/mcp/tool_registry_spec.rb` (new — strip-on-release)

This file does not exist today; the implementation agent creates it.

- **`tools/list` under the development flag (expose_dev_scope=true):**
  - `it "lists list_docs"`.
  - `it "lists read_doc"`.
  - `it "lists save_note"`.
  - `it "lists list_channels"` (sanity check that app tools are present).
- **`tools/list` under the production flag (expose_dev_scope=false):**
  - `it "does not list list_docs"`.
  - `it "does not list read_doc"`.
  - `it "does not list save_note"`.
  - `it "still lists list_channels"` (sanity check).
- **Tool dispatch under the production flag:**
  - `it "rejects a tools/call for list_docs with the not-found / not-registered error envelope from the gem"`
    — invocation against the disabled tool fails predictably; the exact error
    shape is whatever the `mcp` gem returns when an unknown tool is called.
    Implementation agent encodes the gem's behavior.
  - `it "rejects a tools/call for save_note even when the bearer token's scopes literally contain 'dev'"`
    — construct a token with `["dev"]` (bypassing the validation by
    `update_columns` if necessary, simulating a stale token); assert the call
    still fails (either at the tool-not-registered layer or at the
    `require_scope!` layer with `insufficient_scope`).

#### `spec/mcp/tools/list_docs_spec.rb` (and `read_doc_spec.rb`, `save_note_spec.rb`) updates

Each Dev KB tool spec needs:

- An updated happy-path example: bearer token has `scopes: ["dev"]` (not
  `[Scopes::DEV_READ]`); call succeeds.
- An updated sad-path example: bearer token has `scopes: ["app"]` only; call
  returns `insufficient_scope`.

#### `spec/mcp/tools/<every-app-tool>_spec.rb` updates

Each app tool spec needs:

- An updated happy-path example: bearer token has `scopes: ["app"]`; call
  succeeds.
- An updated sad-path example: bearer token has `scopes: ["dev"]` only; call
  returns `insufficient_scope`.

The implementation agent enumerates the full file set via
`git grep -l 'YT_READ\|YT_WRITE\|YT_DESTRUCTIVE\|PROJECT_READ\|PROJECT_WRITE' spec/mcp/`.

#### `spec/db/seeds_spec.rb` (Phase 8 introduced this — update)

- `it "mints the dev ApiToken with scopes ['dev', 'app']"` — replaces the
  previous 6-element scope assertion.
- `it "is idempotent across two seed runs"` — preserved from Phase 8.

#### `spec/db/migrate/<timestamp>_revoke_tokens_for_scope_simplification_spec.rb` (new — migration integration)

Optional but recommended. The implementation agent decides whether the test
lives at the migration layer or at the integration / fixture layer. The required
behaviour:

- **Setup:** load the schema; insert a fixture `ApiToken` with
  `scopes: [...legacy...]` and `revoked_at: nil`; insert a
  `Doorkeeper::AccessToken` with `revoked_at: nil`; insert an `OauthApplication`
  with `scopes: "dev:read project:write yt:read"`.
- **Run** the migration's `up`.
- **Assert:**
  - The `ApiToken` row's `revoked_at` is now non-nil.
  - The `Doorkeeper::AccessToken` row's `revoked_at` is now non-nil.
  - The `OauthApplication.scopes` is rewritten to `"dev app"` (order-
    insensitive — the implementation agent picks the canonical order; the test
    asserts the set, not the string).

## Manual playbook (post-implementation)

The user runs after the dispatch lands, before the commit.

1. **Confirm Phase 8 is on `main`.** The tenant drop is the prerequisite; the
   seed in this phase assumes the post-Phase-8 shape. If anything in the working
   tree references `tenant_id` on a token, stop and re-route.
2. **Drop and recreate the database.**
   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```
   Confirm the seed prints the dev-token banner exactly once.
3. **Verify the seeded scope set.**
   ```bash
   bin/rails runner 'puts ApiToken.where(name: "dev").pluck(:scopes).inspect'
   ```
   Expected output: `[["dev", "app"]]`.
4. **Re-pair Claude Mobile (MCP).** Open the Claude Mobile MCP connector
   configuration; revoke the existing connection; re-add `mcp.pitomd.com` (or
   `https://app.pitomd.com/mcp` per the local / tunnel choice). Walk the
   Doorkeeper consent flow. The consent screen should display two scopes: `dev`
   and `app` (and the prose descriptions per the copy questions).
5. **Re-pair Claude.ai Web MCP.** Open Claude.ai's MCP connector settings;
   revoke; re-add. Same consent screen check. Claude.ai auto-walks all
   advertised scopes, so the soft-clip monkey-patch should hand it `[dev, app]`
   from the configured application whitelist.
6. **Smoke a `dev` tool.** From Claude Mobile, call `list_docs`. It should
   return the list of markdown files.
7. **Smoke an `app` tool.** From Claude Mobile, call `list_channels`. It should
   return the seeded channels.
8. **Smoke a strip-on-release dry-run.** Locally, with the working tree, run:
   ```bash
   RAILS_ENV=production \
     RAILS_MASTER_KEY=<your-key> \
     bin/rails runner 'puts Scopes::ALL.inspect'
   ```
   Expected output: `["app"]`.
9. **Run the full RSpec suite.**
   ```bash
   bundle exec rspec
   ```
   Confirm green. Note the spec count delta in `log.md`.
10. **Run rubocop / brakeman.**
    ```bash
    bundle exec rubocop
    bundle exec brakeman -q
    ```
    Both green (or no new findings).
11. **Verify the soft-clip monkey-patch behavior.** From the running `bin/dev`,
    exercise an OAuth `/oauth/authorize` request with the scope param manually
    set to `dev:read app:write` (legacy strings). Confirm the redirect carries
    `error=invalid_scope`. Then exercise the same flow with `scope=dev app`;
    confirm the consent screen renders.
12. **Reviewer fills in:** any further smoke steps surfaced during the review
    pass.

## Cross-stack scope

| Surface           | Status                                                                                                                                                                                                                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                                                                                                                                                                                        |
| MCP rack app      | **In scope.** Tool registry gating + per-tool scope updates. Same lane.                                                                                                                                                                                                                            |
| Doorkeeper        | **In scope.** Default/optional scope reconfiguration; soft-clip monkey-patch verified. Same lane.                                                                                                                                                                                                  |
| `pito` CLI (Rust) | **Skipped.** The CLI does not currently make scope-aware API calls (it consumes the JSON API surface, not Doorkeeper); no scope strings are encoded on the client side. If a CLI-side reference surfaces during the implementation sweep, the agent flags it but does not fix it in this dispatch. |
| Astro / website   | **Skipped.** N/A.                                                                                                                                                                                                                                                                                  |
| Settings UI       | **Best-effort in scope.** `/settings/tokens` create form's scope picker may need a small tweak (collapse from a 9-checkbox tree to two flat checkboxes labelled per the new descriptions). If the change is one-line, ship it; otherwise the agent flags as a follow-up.                           |

## Copy questions to escalate (master agent asks user before dispatch)

The architect surfaces these; the user picks the wording. Do NOT pick copy in
the spec.

1. **Consent screen scope description for `dev`.** Doorkeeper's consent screen
   renders the scope description from `Scopes::DESCRIPTIONS`. Suggested options:
   - `"Dev tooling — knowledge base read + capture (docs/, notes)."`
   - `"Developer knowledge base. Read documents, save notes."`
   - `"Read and capture developer docs."`
2. **Consent screen scope description for `app`.** Suggested options:
   - `"Application data — channels, videos, projects, calendar, notifications."`
   - `"Application access. Manage channels, videos, projects, and the calendar."`
   - `"Manage your pito install."`
3. **Insufficient-scope error envelope text.** Today's payload is
   `{"error": "insufficient_scope", "required": "<scope>"}`. With the `<scope>`
   value collapsing to `"dev"` or `"app"`, the message reads correctly without
   modification. Confirm no copy change.
4. **Settings UI scope picker labels.** Today's labels (per Phase 5) are derived
   from `Scopes::DESCRIPTIONS`. Same prose as Q1 + Q2 will surface here unless
   the user wants a different framing on the create-token page.
5. **Production-build language.** When `expose_dev_scope = false`, a user (or a
   Claude.ai connector) requesting `dev` gets `error=invalid_scope` from
   Doorkeeper's standard error machinery. Confirm whether the current default
   error message is acceptable or whether we want a custom one. Recommendation:
   leave as-is; the OAuth error code is the right wire shape.
6. **Migration body comment.** The architect proposed: "Per ADR 0004, the scope
   catalog collapses from 9 to 2 entries. Existing tokens are revoked; users
   re-pair Claude Mobile + Web MCP after deploy." Confirm or rewrite.
7. **`docs/auth.md` §2 prose framing.** Once the catalog table is two rows, the
   surrounding prose ("Three namespaces are live in Phase 3 …") needs a rewrite.
   The architect captures the touchpoint; the docs-keeper drafts; user reviews.
8. **`docs/mcp.md` "Channel-Revamp note" column** in the per-tool table — the
   column exists today carrying historical Path-A2 notes; under the new
   collapsed table this column becomes mostly empty. Confirm whether to drop the
   column outright or keep it as a freeform notes column.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Strip-on-release: tool-registry gate vs. `require_scope!` gate.** The
   architect's preferred shape is **both** (defense-in-depth): the tool isn't
   registered at all in production, AND the scope isn't in `Scopes::ALL`. A user
   with a legacy `["dev"]` token in production hits the not-registered layer
   first; if somehow the tool is registered (a future build flag mistake), the
   scope check still denies. Recommendation: ship both gates. Master agent
   confirms.
2. **Production seed behavior.** `db/seeds.rb` currently always mints a dev
   `ApiToken`. In production (with `expose_dev_scope = false`), the dev token's
   `dev` scope would be invalid (and the validation would reject). Two options:
   - (a) skip the dev-token mint entirely under `Rails.env.production?` (matches
     the spirit of "production users don't get dev tooling").
   - (b) mint the dev token with `[Scopes::APP]` only. Recommendation: **(a) —
     skip in production.** A production install does not want a "dev" token
     sitting in the database; the operator mints their own via
     `/settings/tokens`. Master agent confirms.
3. **Scope picker UI in `/settings/tokens` create form.** The Phase 5
   implementation rendered checkboxes from `Scopes::DESCRIPTIONS`. With only two
   entries, the visual surface is trivial; the architect expects the existing
   implementation to "just work" via the same loop. The implementation agent
   verifies and reports.
4. **Doorkeeper application scope-whitelist defaults.** The `OauthApplication`
   create form (under `/settings/oauth_applications/new`) likely has a
   scope-checkbox tree mirroring `Scopes::ALL`. Same simplification: from 9
   to 2. The implementation agent verifies and reports.
5. **Should the migration outright DROP `ApiToken` rows instead of
   soft-revoking?** Recommendation: **soft-revoke.** Soft-revoke matches the
   existing audit posture (revoked rows stay for forensic review). The same
   applies to Doorkeeper tokens (which use `revoked_at` natively).
6. **Strip-on-release flag name.** The architect proposed
   `Rails.application.config.x.mcp.expose_dev_scope`. Alternatives:
   - `config.x.mcp.dev_tooling_enabled`
   - `config.x.dev_kb.enabled`
   - `config.x.mcp.scopes.expose_dev` Pick whichever reads cleanly to the user;
     the architect's pick is `mcp.expose_dev_scope` because it names exactly the
     on/off property — the dev scope's exposure to the catalog and the tool
     registry.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing in
the prior sections. Implementation agent treats these as the contract.

### Copy decisions (lock these into the spec)

1. **Consent screen `dev` scope description** →
   `"read and capture developer docs."` (lowercase per project tone).
2. **Consent screen `app` scope description** →
   `"application access. manage channels, videos, projects, and the calendar."`
   (lowercase per project tone).
3. **Insufficient-scope error envelope text** → No change. The current
   `{"error": "insufficient_scope", "required": "<scope>"}` shape already reads
   correctly with the new 2-scope catalog.
4. **Settings UI scope picker labels** → Derive from the same
   `Scopes::DESCRIPTIONS` map (so they match the consent-screen copy verbatim).
5. **Production-build error language for missing `dev` scope** → Keep
   Doorkeeper's standard `error=invalid_scope`. The OAuth error code is the
   right wire shape; no custom message.
6. **Migration body comment** → Accept the architect's proposed text verbatim:
   `"Per ADR 0004, the scope catalog collapses from 9 to 2 entries. Existing tokens are revoked; users re-pair Claude Mobile + Web MCP after deploy."`
7. **`docs/auth.md` §2 prose framing** → docs-keeper handles after user
   validates the manual playbook. Implementation agent does not touch `docs/`.
8. **`docs/mcp.md` Channel-Revamp note column** → Drop the column outright. Path
   A2 is retired (per ADR 0003 update), and a 2-row table doesn't need a
   vestigial notes column. docs-keeper drops the column when it rewrites the
   table for the 2-scope catalog.

### Open-question decisions (lock these into the spec)

1. **Strip-on-release gating layer count** → Both gates. Tool-registry gate AND
   `require_scope!` gate. Defense-in-depth.
2. **Production seed behavior** → Skip dev-token mint entirely under
   `Rails.env.production?`. Production operators mint their own tokens via
   `/settings/tokens` if needed.
3. **Settings tokens scope picker** → Implementation agent verifies the existing
   checkbox-loop "just works" with 2 entries; no UI change anticipated. If the
   implementation finds non-trivial UI churn, surface for follow-up.
4. **OAuth application scope-whitelist UI** → Same posture as #3. Implementation
   verifies; no UI change anticipated.
5. **Migration: revoke vs drop existing `ApiToken` / Doorkeeper tokens** →
   Soft-revoke. Sets `revoked_at` (Doorkeeper native) / equivalent for
   `ApiToken`. Preserves audit-trail; matches existing posture.
6. **Strip-on-release flag name** →
   `Rails.application.config.x.mcp.expose_dev_scope`. Architect's pick stands.

## Non-goals (explicit)

- **`GoogleIdentity` rename.** Phase 9 spec.
- **Channel / Video schema expansion.** Realignment work unit 4.
- **New MCP tool surfaces.** Calendar, notifications, IGDB, etc. all use
  `Scopes::APP` per the realignment, but their introduction is per- domain (work
  units 6 / 7 / 8 / 9), not in this dispatch.
- **`pito` CLI changes.** No client-side scope encoding to update.
- **Settings UI redesign.** Only the trivial one-line tweaks mentioned above; no
  broader rework.
- **Migration rollback testing.** Destructive-and-reseed posture; the `down`
  method (if any) is for Rails bookkeeping only.
- **Single-binary distribution / install wizard.** Realignment work unit 12;
  deferred ~6 months. The strip-on-release flag is wired up here so that work
  unit can rely on it without a follow-up scope rewrite.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`, depending on the agent
re-prefix follow-up status at dispatch time). Touches:

- `db/migrate/`, `db/seeds.rb`
- `app/lib/scopes.rb`, `app/models/api_token.rb`
- `app/mcp/tools/*.rb`, `app/mcp/pito_server.rb`
- `config/initializers/doorkeeper.rb`
- `config/initializers/mcp_expose_dev_scope.rb` (new — or
  `config/application.rb`)
- `config/environments/{development,test,production}.rb`
- `spec/**`
- (best-effort) `app/views/settings/**` if the picker collapse is one-line;
  otherwise flagged.

No `extras/cli/`, no `extras/website/`, no `docs/` (that is docs-keeper's
separate dispatch after validation).

## Reviewer checkpoints (post-implementation)

The reviewer agent runs:

1. `git grep 'DEV_READ\|DEV_WRITE\|YT_READ\|YT_WRITE\|YT_DESTRUCTIVE\|WEBSITE_READ\|WEBSITE_WRITE\|PROJECT_READ\|PROJECT_WRITE' app/ lib/ spec/ config/ db/`
   → expect zero matches except in:
   - migration body (the rewrite migration's mapping table itself, if the
     implementation agent expressed it as constants for clarity)
   - any historical-context comment the implementation agent flags in advance
     (typically none — the catalog collapse is a clean break).
2. `git grep '"dev:read"\|"dev:write"\|"yt:read"\|"yt:write"\|"yt:destructive"\|"website:read"\|"website:write"\|"project:read"\|"project:write"' app/ lib/ spec/ config/ db/`
   → same: zero matches outside the migration mapping body.
3. `bundle exec rspec` — green.
4. `bundle exec rubocop` — green (or no new violations).
5. `bundle exec brakeman -q` — green (or no new findings).
6. Manual playbook §1-§11 above.
7. Spec file count delta logged in
   `docs/plans/beta/10-mcp-scope-simplification/log.md`.
8. Confirm the soft-clip monkey-patch is unchanged on disk
   (`git diff config/initializers/doorkeeper_scope_clip.rb` returns nothing).
9. Confirm the strip-on-release boundary in production:
   `RAILS_ENV=production bin/rails runner 'puts Scopes::ALL.inspect'` prints
   `["app"]`.
