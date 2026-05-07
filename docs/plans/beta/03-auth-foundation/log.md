# Phase 3 — Auth Foundation — Session Log

## 2026-05-07 — Step A (5a-schema-and-current.md)

**Spec:** `docs/plans/beta/03-auth-foundation/specs/5a-schema-and-current.md`

**Goal of the session.** Lock the multi-tenant schema shape, formalize the four
schema departures from the original Phase 3 plan, ship the `BelongsToTenant`
concern with `Current.tenant_id` default scoping, and prove cross-tenant
isolation with a paired-tenant leak spec. Step A and Step B were worked in
parallel; this entry covers Step A only.

### What landed

**Migrations (26 total).** Three-step pattern (add nullable reference, backfill
via lineage, set NOT NULL) applied per table so rollback is cheap. Tables:
`videos`, `playlists`, `playlist_items`, `video_stats`, `video_uploads`,
`saved_views`, `bulk_operations`, `bulk_operation_items`. `saved_views` and
`bulk_operations` have no obvious lineage column; both backfill to
`Tenant.first`. Plus `tenants.slug` (citext, unique, NOT NULL, backfilled from
`:owner.tenant_slug` credentials with fallback `"primary"`) and
`footages.tenant_id` tightened from nullable to NOT NULL. `mcp_access_tokens`
was deliberately skipped — Step B owns the rename to `api_tokens` and adds
`tenant_id` as part of that rename.

**`BelongsToTenant` concern.** New at
`app/models/concerns/belongs_to_tenant.rb`. Declares `belongs_to :tenant`,
`validates :tenant_id, presence: true`, and a `default_scope` that raises
`BelongsToTenant::TenantContextMissing` when `Current.tenant_id` is nil. Locked
decision per spec §5.4 — bugs should be loud, not silent. `Model.unscoped` is
the documented escape hatch.

Included in: `Channel`, `Video`, `Playlist`, `PlaylistItem`, `VideoStat`,
`VideoUpload`, `SavedView`, `BulkOperation`, `BulkOperationItem`, `Project`,
`Collection`, `Game`, `Footage`, `Note`, `Timeline`, `ProjectReference`.
`Tenant` and `User` intentionally do NOT include the concern (Tenant has no
`tenant_id`; User is queried by login flows that do not have `Current` set).

**`Current.tenant_id` reader.** Added a small convenience method on `Current` so
`BelongsToTenant`'s default scope can branch on `Current.tenant_id` without a
`respond_to?` dance.

**Footage / ProjectReference denormalization.** The
`before_validation :denormalize_tenant_from_project` callback on both models was
tightened. Two changes from the original `||=` shape:

1. When `project` is present, `tenant_id == Current.tenant_id` is now treated as
   the default-scope's stamp on a freshly built row (Rails copies scope `where`
   conditions onto attribute defaults for `new` records). The project's tenant
   wins in that case, which keeps `proj.games << game` and
   `Footage.create!(project: ..., ...)` consistent with their parent.
2. For Footage specifically: when both `project` and `tenant_id` are absent,
   raise `Footage::MissingProjectError` immediately rather than silently let the
   row reach validation in a half-set state. With `tenant_id` now NOT NULL on
   the column itself, raising here is the right loud-failure shape.

**Tenant slug validations.** `Tenant#slug` validates presence, length (≤ 60
chars), `\A[a-z0-9][a-z0-9_-]*\z` format, and case-insensitive uniqueness via
citext.

**Seeds.** Wrap the seed body in `Current.tenant = tenant` so default-scoped
reads inside the seed file work. Stamp `tenant: tenant` explicitly on the video
and video_stat seeds (channels were already tenanted in Channel Revamp; Phase 4
fixtures were tenanted from day one). Tenant seed reads `:owner.tenant_slug`
from credentials with fallback `"primary"`.

**Factories.** Every newly-tenanted factory uses
`tenant { Current.tenant || association(:tenant) }` so it reuses the active
tenant when one is set. The `bulk_operation_item` factory was reworked to build
its internal video against the parent bulk_operation's tenant so cross-tenant
fixtures don't accidentally spawn extra channels.

**Test support — `spec/support/tenant_context.rb`.** Global `before(:each)` that
pins `Current.tenant` to a default tenant (creates one if no tenant exists yet).
Without this, every existing spec that hits a tenanted model factory would
raise. Specs that need to assert behavior with no tenant context (the
cross-tenant leak spec for the §5.5 step 6 "raises without Current" assertion)
call `Current.reset` inside the example. Specs that explicitly create a second
tenant pivot via `before { Current.tenant = tenant }`.

**Job tenant context.** `NoteSyncJob#perform` and `Notes::EmbedJob#perform` both
pin `Current.tenant` for the duration of the job (and restore previous state in
the `ensure` block). Without this, Sidekiq workers would raise
`TenantContextMissing` on every tenanted-model query. `Notes::EmbedJob` uses
`Note.unscoped.find_by(id:)` for the initial lookup since the worker starts with
no tenant context.

**Specs.**

- `spec/models/concerns/belongs_to_tenant_spec.rb` — locks the default-scope
  raise behavior, the presence validator, and the inclusion roster.
- `spec/models/cross_tenant_leak_spec.rb` — full two-tenant fixture, count +
  find symmetry across all 16 tenanted models, RecordNotFound on cross-tenant
  find, TenantContextMissing under `Current.reset`, and `Model.unscoped`
  escape-hatch coverage.
- `spec/models/tenant_spec.rb` — slug presence / format / length / uniqueness.
- `spec/models/footage_spec.rb` — `MissingProjectError` raise on bare
  `Footage.new` with no project and no tenant_id; tolerated when `tenant_id` is
  set explicitly.
- `spec/requests/application_controller_current_spec.rb` — updated. The
  pre-Phase-5 `tolerates nil Tenant.first` assertion is gone (with
  BelongsToTenant the contract is "tenant context is required"); the Current
  lifecycle test now asserts the support hook seeds Current at the top of every
  example.
- A handful of existing specs (`spec/models/project_spec.rb`,
  `spec/models/note_spec.rb`, `spec/models/project_reference_spec.rb`,
  `spec/jobs/note_sync_job_spec.rb`, `spec/mcp/tools/create_channel_spec.rb`,
  `spec/requests/notes_spec.rb`) got `before { Current.tenant = tenant }` pivots
  so their explicitly-created tenants line up with default-scoped queries.

### Decisions captured before execution

- `tenant_slug` fallback when `:owner.tenant_slug` is absent in credentials =
  `"primary"`.
- `users.role` formally dropped — single-user world; column has no readers.
- `users.name` formally dropped — username + email cover every display need.
- `users.email` / `users.username` global uniqueness — locked as a deliberate
  departure (single-tenant tractable; revisited at Theta multi-tenancy).
- `mcp_access_tokens.tenant_id` deferred to Step B's rename rather than added in
  Step A. Avoids a column-on-the-old-name + rename + extend chain.
- Default-scope-stamp gotcha in Footage / ProjectReference denormalization
  resolved by treating `tenant_id == Current.tenant_id` as "default stamp" and
  letting `project.tenant_id` win. Explicit user assignment that disagrees with
  both Current AND project still flows through to the validator for rejection.
- Test support: a global `before(:each)` pre-pinning `Current.tenant` for every
  spec type. The alternative — making each existing spec explicitly set
  `Current.tenant` after every factory create — was rejected as too invasive on
  a 1361-spec suite. Specs that need to assert no-context behavior (the
  cross-tenant leak spec) call `Current.reset` inside the example.

### Validation

- `bundle exec rspec` — 1529 examples, 0 failures (1117 carried forward from
  before 5A, 5B's specs included). Spec count grew because of new Step A specs
  (cross-tenant leak, BelongsToTenant concern, tenant slug, footage raise) plus
  5B's auth specs.
- `bin/brakeman -q -w2` — 0 warnings.
- Migrations roll back cleanly via `bin/rails db:rollback STEP=26` and reapply
  via `bin/rails db:migrate`.
- Seeds run end-to-end via `bin/rails db:seed` (idempotent — second run is a
  no-op).
- Manual playbook deferred to the architect — not committed yet.

### Files touched (high level)

- 26 new migrations under `db/migrate/20260507000001..20260507000090`.
- `app/models/concerns/belongs_to_tenant.rb` (new).
- `app/models/current.rb` (added `tenant_id` reader).
- `app/models/{channel,video,playlist,playlist_item,video_stat,video_upload,saved_view,bulk_operation,bulk_operation_item,project,collection,game,footage,note,timeline,project_reference,tenant}.rb`
  (include the concern; tenant adds slug validation; footage / project_reference
  tighten the denormalization callback).
- `app/jobs/note_sync_job.rb`, `app/jobs/notes/embed_job.rb` (pin Current.tenant
  for the duration of perform).
- `db/seeds.rb` (Current wrap, tenant slug, video / video_stat tenant stamps).
- `spec/support/tenant_context.rb` (new).
- `spec/factories/{tenants,channels,users,videos,playlists,playlist_items,video_stats,video_uploads,saved_views,bulk_operations,bulk_operation_items,collections,projects,games}.rb`
  (tenant association via Current-aware default).
- `spec/models/concerns/belongs_to_tenant_spec.rb` (new).
- `spec/models/cross_tenant_leak_spec.rb` (new).
- `spec/models/{tenant,footage,project,note,project_reference}_spec.rb` (slug +
  raise specs added; default-scope-aware test pivots).
- `spec/jobs/note_sync_job_spec.rb` (Current pivot).
- `spec/mcp/tools/create_channel_spec.rb` (let-tenant aligned with auto pin).
- `spec/requests/{notes,application_controller_current}_spec.rb` (let-tenant
  alignment + Current lifecycle contract update).

### Open issues / follow-ups

- `User#role` and `User#name` were already absent from the schema before 5A ran
  — the destructive drops the spec called for were no-ops. Recorded the formal
  decision in the plan.md without a destructive migration.
- `users.email` / `users.username` global uniqueness is locked as a deliberate
  departure for now; the rationale is recorded in this log and referenced in the
  spec. Step C's docs pass should land it in `docs/architecture.md` and
  `docs/auth.md`.
- Phase 4 already-tenanted factories (`projects`, `collections`, `games`,
  `notes`, `timelines`, `footages`) were left as-is; they already use
  `Current.tenant || association(:tenant)` shape (or pass tenant from a parent
  association), so no changes needed.

---

## 2026-05-07 — Step B (5b-token-and-auth-concern.md)

**Spec:**
`docs/plans/beta/03-auth-foundation/specs/5b-token-and-auth-concern.md`

**Goal of the session.** Promote `McpAccessToken` to `ApiToken` (rename +
extend), declare the Beta scope catalog, and wire bearer-token authentication +
scope enforcement into both Pumas (Web's `Api::*` controllers and
`Mcp::RackApp`).

### What landed

**Token model.** `mcp_access_tokens` → `api_tokens` via two migrations:

- `20260507100001_rename_mcp_access_tokens_to_api_tokens` — `rename_table`
  - index rename.
- `20260507100002_add_user_scopes_expires_to_api_tokens` — adds `tenant_id` (FK
  NOT NULL), `user_id` (FK NOT NULL), `scopes` (jsonb NOT NULL default `[]`),
  `expires_at` (datetime nullable), plus indexes. Backfills existing rows to
  `Tenant.first` / `User.first` and the dev:\* scope set.

`ApiToken` model carries: `belongs_to :tenant, :user`; HMAC-SHA256 digest with
`:tokens.pepper` credential; `scopes_subset_of_catalog` validator against
`Scopes::ALL`; `revoked? / expired? / usable?` predicates; `touch_used!` via
`update_columns`. The legacy `authenticate(plaintext)` class method is preserved
for the rake CRUD path; production HTTP authentication routes through
`Api::TokenAuthenticator`.

**Scope catalog.** `app/lib/scopes.rb` declares the nine catalog entries in two
frozen collections (`ALL`, `DESCRIPTIONS`):

- `dev:read`, `dev:write`
- `yt:read`, `yt:write`, `yt:destructive`
- `website:read`, `website:write` (declared, no tools yet — Phase 6)
- `project:read`, `project:write`

**Authentication engine.** `Api::TokenAuthenticator` (under `app/lib/api/`) is
the shared engine: extracts the bearer header, digests + looks up the row,
returns a `Result` struct with either the token or a `failure_reason`
(`missing_token`, `invalid_token`, `revoked_token`, `expired_token`,
`auth_misconfigured`). On every failure it sets
`env["pito.auth_failed"] = true`, bumps the rack-attack failed-auth bucket, and
writes one JSON line to `log/auth_audit.log`.

`Api::AuthConcern` (under `app/controllers/concerns/api/`) is a thin shim: a
`before_action :authenticate_api_token!` runs the authenticator and translates
failures into rescued errors, plus a `require_scope!(scope)` helper. Mixed into
`Api::FootagesController` (the only `Api::*` controller in Phase B). Each action
declares its required scope (`Scopes::PROJECT_READ` for `index`,
`Scopes::PROJECT_WRITE` for `create`).

`Mcp::RackApp#call` invokes the authenticator inline before delegating to the
StreamableHTTPTransport, populating `Current.token / tenant / user` and
resetting in `ensure`.

**Tool-level scope enforcement.** `Mcp::ToolAuth.require_scope!(scope)` is a
tool-friendly check — returns nil to proceed, or an MCP::Tool error response
with `{error: "insufficient_scope", required: <scope>}` when the token's scopes
lack the requirement. Every tool's `call` opens with this guard. The mapping:

- `dev:read` — `list_docs`, `read_doc`
- `dev:write` — `save_note`
- `yt:read` — `list_channels`, `get_channel`, `list_videos`, `get_video`,
  `get_dashboard`, `list_saved_views`, `search`, `manage_settings` (read-only
  path)
- `yt:write` — `create_channel`, `update_channel`, `create_video`,
  `update_video`, `create_saved_view`, `delete_saved_view`, `sync_records`,
  `manage_settings` (mutating path)
- `yt:destructive` — `delete_records`

**Throttle.** `rack-attack 6.8.0` added to the Gemfile;
`config/initializers/rack_attack.rb` wires a blocklist that 429s when the per-IP
failed-auth bucket reaches 10 within a 5-minute window. The `ApiAuthThrottle`
helper module shares the bucket key shape between the authenticator's failure
path (which records) and the blocklist (which reads). `Rack::Attack.cache.store`
is the Rails cache in dev/prod and an isolated `MemoryStore` in test (cleared
per-example via `spec/support/rack_attack_isolation.rb`).

**Audit log.** `config/initializers/auth_audit_logger.rb` configures
`AUTH_AUDIT_LOGGER` against `log/auth_audit.log`. Format: one JSON line per
event (`auth.success`, `auth.missing_token`, `auth.invalid_token`,
`auth.revoked_token`, `auth.expired_token`, `auth.misconfigured`). Both Pumas
write to the same file; logrotate is host-side (out of scope for this step).

**Rake task rename.** `lib/tasks/mcp.rake` → `lib/tasks/tokens.rake`, tasks
renamed `mcp:generate_token` / `mcp:list_tokens` / `mcp:revoke_token` →
`tokens:create` / `tokens:list` / `tokens:revoke`. `tokens:create` accepts a
`+`-separated scope list (commas inside Thor task args need escaping; `+` keeps
the CLI ergonomic). The task validates the scope list against `Scopes::ALL`
before minting.

**Pepper credential.** `Rails.application.credentials.tokens.pepper` generated
as 64-char hex via `SecureRandom.hex(32)` and written to
`config/credentials.yml.enc`. `ApiToken.digest(plaintext)` raises
`Api::AuthConfigurationMissing` when the credential is absent — the
authenticator translates that into a clean `{error: "auth_misconfigured"}` 500.
Step C will document the credential ceremony in `docs/setup.md`.

### Files changed (high level)

- `Gemfile`, `Gemfile.lock` — add rack-attack.
- `config/credentials.yml.enc` — `:tokens.pepper` block added.
- `config/initializers/rack_attack.rb` — new.
- `config/initializers/auth_audit_logger.rb` — new.
- `db/migrate/20260507100001_rename_mcp_access_tokens_to_api_tokens.rb` — new.
- `db/migrate/20260507100002_add_user_scopes_expires_to_api_tokens.rb` — new.
- `db/schema.rb` — regenerated from the migrations.
- `app/lib/scopes.rb` — new (scope catalog).
- `app/lib/api/unauthorized.rb`, `forbidden.rb`, `auth_configuration_missing.rb`
  — new error classes.
- `app/lib/api/token_authenticator.rb` — new (shared engine).
- `app/controllers/concerns/api/auth_concern.rb` — new controller mixin.
- `app/controllers/application_controller.rb` —
  `rescue_from Api::Unauthorized / Api::Forbidden`, JSON renderers.
- `app/controllers/api/footages_controller.rb` — include `Api::AuthConcern`,
  skip the cookie-only Current populator, call `require_scope!` per action.
- `app/models/api_token.rb` — renamed from `mcp_access_token.rb`; rewritten per
  spec §6.1.
- `app/mcp/rack_app.rb` — bearer enforcement; populates Current; resets in
  `ensure`.
- `app/mcp/tool_auth.rb` — new; required by `app/mcp/pito_server.rb`.
- `app/mcp/pito_server.rb` — `require_relative "tool_auth"`.
- `app/mcp/tools/*.rb` — every tool's `call` opens with
  `Mcp::ToolAuth.require_scope!(...)` per the mapping above.
- `lib/tasks/tokens.rake` — renamed from `mcp.rake`, rewritten for the new model
  and the catalog-aware scope flag.
- `spec/factories/api_tokens.rb` — renamed from `mcp_access_tokens.rb`; builds
  an internally consistent row from a freshly digested plaintext.
- `spec/models/api_token_spec.rb` — replaces `mcp_access_token_spec.rb`; covers
  digest / scope / lifecycle / `touch_used!` / pepper credential.
- `spec/lib/scopes_spec.rb` — new.
- `spec/lib/api/token_authenticator_spec.rb` — new (15 examples covering every
  reject path, success path, env flag, audit log, Result→Rack).
- `spec/requests/api/auth_concern_spec.rb` — new (9 examples driving the full
  reject/accept matrix through `Api::FootagesController`).
- `spec/requests/api/footages_spec.rb` — updated to mint a token and send the
  Bearer header on every request.
- `spec/requests/mcp/rack_app_auth_spec.rb` — new (6 examples covering 401
  paths, success path, and a per-tool scope-reject example).
- `spec/requests/mcp_http_spec.rb` — updated to mint a token and send the Bearer
  header on every request.
- `spec/initializers/rack_attack_spec.rb` — new (3 examples: 429 after the 11th
  bad request, HTML routes exempt, success doesn't burn the bucket).
- `spec/support/api_token_context.rb` — new; pins `Current.token` for
  `spec/mcp/**` tool specs so direct `Mcp::Tools::*.call(...)` invocations see a
  usable token.
- `spec/support/rack_attack_isolation.rb` — new; clears
  `Rack::Attack.cache.store` before every example.
- `docs/plans/beta/03-auth-foundation/plan.md` — ticked the relevant checkboxes
  (token model, scope catalog, JSON API auth concern, existing-tool refactor,
  Rack::Attack throttle, MCP HTTP auth, dual-Puma auth sharing, Brakeman
  re-verification).

### Test results

- `bin/rspec spec/` — **1417 examples, 0 failures**.
- `bundle exec brakeman -q -w2` — **0 security warnings**.

### Decisions captured this session

1. **Migrations split rather than monolithic.** The rename and the column-add
   were split into two migrations to keep each step reversible without
   DB-statement gymnastics. Rolling back the second migration leaves the renamed
   table intact; rolling back further restores the original name.
2. **`Api::TokenAuthenticator` returns a `Result` struct rather than raising.**
   The Rails controller path can rescue from raised errors cleanly, but the Rack
   app path cannot. Returning a `Result` keeps one code path that both contexts
   use; the controller concern raises `Api::Unauthorized` / `Api::Forbidden`
   itself when needed for the rescue_from pattern.
3. **`ApiAuthThrottle` records failures from inside the authenticator** rather
   than relying on a Rack::Attack `throttle` block that observes the current
   request. The block-style approach would only see flags from PRIOR requests;
   counting in-line at the failure path keeps the bucket monotonically
   increasing as failures happen.
4. **The error classes split into one-file-per-class** to satisfy Zeitwerk's
   autoload contract under `app/lib/api/`.
5. **`tokens:create`'s scope-list separator is `+`, not `,`** because Thor task
   args use `,` as the argument boundary already; using `+` keeps the CLI
   ergonomic without escaping.
6. **The MCP `manage_settings` tool gets dual-mode scope enforcement** —
   `yt:read` when called with no `updates`, `yt:write` when called with
   `updates`. Both apply to the same tool name; the gate is the payload shape.

### Out of scope (handed off to Step C)

- Settings UI for token CRUD (list / create / revoke).
- `docs/auth.md`, `docs/architecture.md`, `docs/mcp.md`, `docs/setup.md`
  updates.
- Pepper credential ceremony documentation (the credential is set; the
  walkthrough lands in Step C).
- Cross-tenant leak spec (single tenant only in 5A/5B).
- Per-tool scope-reject examples (one rack-app-level scope reject example
  exercises the gate; per-tool examples are repetitive given the uniform
  `Mcp::ToolAuth.require_scope!` shape).

---

## 2026-05-07 — Step C (5c-settings-ui-and-docs.md)

**Spec:** `docs/plans/beta/03-auth-foundation/specs/5c-settings-ui-and-docs.md`

**Goal of the session.** Make the auth model usable end-to-end without dropping
to a rake console. Web UI for token CRUD, dev token seed at install time, and
the four documentation deliverables (`docs/auth.md`, `docs/architecture.md`,
`docs/mcp.md`, `docs/setup.md`).

### What landed

**Settings UI for tokens.** Dedicated `/settings/tokens` page (recommended shape
per the dispatch's locked decisions):

- `Settings::TokensController`
  (`app/controllers/settings/tokens_controller.rb`). Five actions: `index`,
  `new`, `create`, `revoke` (action-confirmation GET), `destroy`. Tenant-scoped
  via `ApiToken.where(tenant_id: Current.tenant_id)` (`ApiToken` doesn't include
  `BelongsToTenant`; manual scoping was the cleanest fit).
- Routes via
  `namespace :settings { resources :tokens, only: %i[index new create destroy] do member { get :revoke } end }`.
- Views — `index.html.erb` (active tokens first, revoked grayed at the bottom),
  `new.html.erb` (form), `_form.html.erb` (scope checkboxes grouped by namespace
  via `Scopes::DESCRIPTIONS.group_by`), `create.html.erb` (the
  show-plaintext-once page with the `[ I have saved it ]` bracketed return
  link), `revoke.html.erb` (action confirmation screen using the existing
  `shared/_action_screen.html.erb` partial). All bracketed-link styling, no JS
  confirms.

**Settings page 6th pane.** Settings is now a `.pane-row` of six 452px panes
(was 5). Order: appearance, workspaces, YouTube, Voyage AI, search, tokens. The
6th pane (B per zebra) is a stub showing `active: <count>` plus a
`[ manage tokens ]` bracketed link to `/settings/tokens`. Token CRUD lives on
the dedicated page because the surface has multiple states (index, new,
post-create plaintext-once, revoke confirmation) that don't fit a single
fieldset.

**Default dev token seed.** `db/seeds.rb` mints a `name: "dev"` token guarded by
`ApiToken.exists?(name: "dev", tenant_id: tenant.id)` so re-runs are no-ops.
Default scope set:
`dev:read, dev:write, yt:read, yt:write, project:read, project:write` — excludes
`yt:destructive` and `website:*` per the dispatch's locked scope list. Plaintext
printed inside a 64-char `=` banner so the install ceremony captures it once.
The seed aborts with a clear message if `:tokens.pepper` is absent at seed time
(defensive — `bin/setup` should have caught it already).

**`bin/setup` pepper pre-flight.** Added a
`Rails.application.credentials.dig(:tokens, :pepper).present?` check via
`bin/rails runner` between `db:prepare` and `log:clear tmp:clear`. On absence,
prints a walkthrough (`bin/rails credentials:edit` + the YAML shape +
`openssl rand -hex 32`) and exits 1. On second run after the user sets it, the
script proceeds normally. Halt happens post-`db:prepare` because the runner
check needs Rails to boot.

**Documentation.**

- `docs/auth.md` — new. Eleven sections per spec §6.6: Model overview, Scope
  catalog (full table), Tool/endpoint scope map, Request flow (ASCII flowchart
  for both Pumas), `belongs_to_tenant` enforcement, Token lifecycle, Bootstrap
  ceremony, Audit log, Throttling, Departures from the original Phase 3 plan,
  Future phase hooks. The single source of truth that future phases link to.
- `docs/architecture.md` — auth section rewritten. Removed the false "Auth
  Foundation deferred to a later phase" claim. Added explicit subsections for
  Schema, Current, BelongsToTenant, and the `Current.token` flow. The "Things
  explicitly NOT in scope" list now reflects what's truly absent (login UI,
  Google OAuth, expiry sweep) rather than what's shipped.
- `docs/mcp.md` — Scope-per-tool table covering all 19 tools. Architecture /
  Token Model sections refreshed to point at `docs/auth.md`. Stale `mcp:*` rake
  tasks renamed to `tokens:*` (the Step B rename). File Structure refreshed to
  include `app/models/api_token.rb`, `app/lib/scopes.rb`, the auth concern, the
  rack-attack initializer, and the auth-audit logger.
- `docs/setup.md` — Added the `:tokens.pepper` credential ceremony to §3 with
  `openssl rand -hex 32` recipe. Added the dev-token-capture step to §5 with the
  banner shape and the lose-it/revoke-it advice.

**Specs.**

- `spec/requests/settings/tokens_spec.rb` — new. 23 examples covering index
  (active + revoked + tenant scoping + nav), new (form shape + per-namespace
  scope groups), create (success + plaintext-once + invalid scope + blank name +
  empty scope + expires_at parse), revoke confirmation (action-screen + no JS
  confirm + destructive button), destroy (revoked_at set, row preserved,
  idempotent on already-revoked).
- `spec/system/settings/tokens_spec.rb` — new. 2 feature-spec examples using
  `driven_by(:rack_test)` (no JS driver in the project's Gemfile; the rack_test
  driver is sufficient for the bracketed-link / form-submit flow). Mirror manual
  playbook steps 4–7 + 11.
- `spec/seeds_spec.rb` — new. 2 examples covering the dev-token mint (locked
  default scope set, idempotency).
- `spec/requests/settings_spec.rb` — updated. The 5-pane assertion is now 6
  panes; the section ordering assertion includes `tokens` after `search`; new
  assertion for the tokens-pane link to `/settings/tokens`.

### Decisions captured this session

1. **Tokens pane is a stub linking to a dedicated page**, not an inline surface.
   The token CRUD has 4 states (index / new / show-plaintext-once / revoke
   confirmation); cramming them into a single fieldset would strain the layout.
   The 6th pane shows the active count + a `[ manage tokens ]` link.
2. **Pepper check runs post-`db:prepare`** rather than pre-`bundle install`. The
   runner check needs Rails booted; running before `db:prepare` would require a
   separate validation path. With `db:prepare` running migrations on a fresh DB
   but NOT triggering `db:seed` (db:seed is a separate task, only called when
   needed), the seed step that actually mints the dev token doesn't run during
   `bin/setup` itself. The check is still important: without it, the FIRST run
   of `bin/rails db:seed` would fail noisily.
3. **System spec uses `driven_by(:rack_test)`** rather than introducing
   selenium-webdriver as a new dependency. The flow we test (clicks on bracketed
   links, form fills, button clicks) doesn't need JS. Future phases that need
   JS-driven specs can add a driver gem then.
4. **Plaintext lives in an instance variable, not a flash**. Spec §11 confirmed
   this requirement; `@plaintext` is set on the controller's `create` action and
   rendered by `create.html.erb`. Subsequent index visits never re-display it.
5. **`status: :unprocessable_content`** instead of the deprecated
   `:unprocessable_entity`. Rack 3 deprecates the latter; the rest of the
   codebase uses the new symbol via Rails 8 patches.
6. **Nav location: 6th pane on the existing settings page**, NOT a top-of- page
   nav. The dispatch's "decided defaults" override the spec's "settings nav
   update" section (§6.3). The pane shape matches the other 5; zebra continues;
   no separate nav row added.
7. **Default-stamp safety in seeds**. The seed body wraps the dev-token mint in
   `Current.user = owner` so any default-scope-aware lookups inside
   `ApiToken.generate!` don't raise. The auth concern + the `BelongsToTenant`
   raise both depend on `Current.tenant_id` being set, which Step A's seed
   wrapper already does.

### Test results

- `bundle exec rspec` — **1557 examples, 0 failures** (1417 from Step B + 140
  from 5C). New: 23 request specs + 2 system specs + 2 seeds specs + 1
  numeric-formatting fix; updated: settings_spec pane count + ordering
  - new tokens-pane link assertion.
- `bin/brakeman -q -w2` — **0 security warnings**.
- `bin/bundler-audit` — **No vulnerabilities found**.

### Files touched (high level)

- `app/controllers/settings/tokens_controller.rb` — new.
- `app/views/settings/tokens/{index,new,_form,create,revoke}.html.erb` — new (5
  files).
- `app/views/settings/index.html.erb` — added 6th pane (tokens).
- `app/controllers/settings_controller.rb` — added `@active_tokens_count` for
  the new pane.
- `config/routes.rb` — `namespace :settings` block with `resources :tokens` +
  `member { get :revoke }`.
- `db/seeds.rb` — dev-token mint (idempotent, banner output).
- `bin/setup` — pepper credential pre-flight check post-`db:prepare`.
- `docs/auth.md` — new.
- `docs/architecture.md` — auth section rewrite.
- `docs/mcp.md` — scope-per-tool table, references to `docs/auth.md`, rake task
  rename, file structure refresh.
- `docs/setup.md` — pepper ceremony + dev-token capture.
- `docs/plans/beta/03-auth-foundation/plan.md` — ticked Settings UI +
  Documentation + dev-token seed checkboxes.
- `spec/requests/settings/tokens_spec.rb` — new.
- `spec/system/settings/tokens_spec.rb` — new.
- `spec/seeds_spec.rb` — new.
- `spec/requests/settings_spec.rb` — pane-count + ordering update.

### Out of scope (deferred to future phases)

- Login form / signup form / session UI — Phase 6.
- Doorkeeper / OAuth client flows — Phase 12.
- Token expiry automation (background sweep) — Phase 12 / 15.
- Pepper rotation — future phase.
- Per-token audit detail page (showing last-N requests) — future enhancement.
- Editing existing tokens (rename, scope change) — out of scope by design;
  workflow is revoke + mint a new token.
- Cross-tenant leak spec for `ApiToken` — `ApiToken` does not include
  `BelongsToTenant` (it's filtered manually in the controller); the cross-tenant
  spec from 5A doesn't cover it. Tenant scoping in the new request specs
  (`other-tenant-token` example) covers the controller boundary instead.
