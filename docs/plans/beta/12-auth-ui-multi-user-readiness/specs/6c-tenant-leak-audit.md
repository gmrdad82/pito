# Phase 6 — Step C — Tenant Leak Audit + Multi-User Readiness

> Third (and closing) deliverable for Phase 6 (Auth UI + Multi-User Readiness).
> With Phase 5 having wired `BelongsToTenant` default scoping at the schema /
> model layer and Phase 6 Steps A and B having installed cookie-session and
> OAuth-issued auth (real users with real tenant ids replacing the implicit
> `Tenant.first / User.first` pin), Step C proves — exhaustively, with specs
> instead of inspection — that no controller flow, model query, background job,
> or MCP tool can leak data across tenants. Step C also retires every remaining
> hardcoded `Tenant.first` / `User.first` reference from production code paths
> and lands the supporting docs that close the phase. Date: 2026-05-05. Locked
> decisions are pinned exactly — do not reinvent.

---

## 1. Goal

Convert the multi-tenant promise from "the schema says so" into "the test suite
says so." Step C does three things, in order:

1. Stand up a **two-tenant fixture infrastructure** in the spec suite so every
   request, model, job, and MCP spec can run with two tenants populated and one
   selected as `Current.tenant`. This becomes the substrate for every leak
   spec.
2. **Author cross-tenant leak specs** for every layer — controllers (HTML and
   JSON), background jobs, MCP tools, and `BelongsToTenant`-bearing models.
   Each spec asserts the same shape: with tenant A authenticated, no row /
   record / response field belonging to tenant B is reachable; with tenant B
   authenticated, the inverse.
3. **Retire the singleton fallback.** Every production code path that still
   reads `Tenant.first` or `User.first` (the Phase-5-and-earlier shortcut) is
   removed or, if a legitimate non-request path needs a tenant (e.g., a
   one-shot rake task), is justified in a code comment and gated by an
   environment check. Every `Model.unscoped` / `Model.find` that bypasses the
   default tenant scope is similarly justified inline.

The deliverable is **green specs + clean grep + audited unscoped usage**, not
new product surface. This is a prove-it-correct exercise, the same shape Phase
3 promised and Phase 12's plan checklist enumerates under "Multi-tenant
audit."

## 2. Depends on

- Phase 5 Step A — `Tenant`, `User`, `BelongsToTenant`, `Current.tenant_id`
  default scoping. Step C relies on the default scope being on by default at
  every model.
- Phase 5 Step B — `Api::TokenAuthenticator`, `Api::AuthConcern`, `Scopes`
  catalog. Step C exercises the bearer surface against two tenants.
- Phase 5 Step C — `docs/auth.md` exists with §1 Tenancy and §11 Audit
  sections. Step C extends them.
- Phase 6 Step A — `SessionsController`, `Sessions::AuthConcern`,
  `Current.session`, the `sign_in_as(user)` request-spec helper. Step C drives
  HTML controllers via this helper.
- Phase 6 Step B — Doorkeeper-issued tokens flow through the SAME
  `Api::AuthConcern`. Step C verifies the dispatch is tenant-correct for both
  manual `ApiToken` and OAuth-issued tokens.
- The MCP server registration (`bin/mcp` / `bin/mcp-web`) and the existing
  tools enumerated under `app/mcp/`. Step C audits each tool for tenant
  resolution from the bearer token.

## 3. Unblocks

- **Phase 7** — Google OAuth + YouTube API Foundation. Tokens written by Phase
  7 will be tenant-scoped from day one; Step C's audit guarantees the read
  path is correct so Phase 7 doesn't have to re-prove tenancy for the YouTube
  surface.
- **Phase 11+ observability** — Step C documents the per-tenant filtering
  contract that observability dashboards will consume.
- **Theta multi-tenancy** — flipping the user-facing single-user assumption
  off (signups, multi-user, billing) becomes a UI / policy change rather than
  a "do we even know the runtime is tenant-clean" question.
- **Closes Phase 6.** Step C is the last sub-step of Phase 6; once it lands,
  the phase log notes the close-out and Phase 7 can begin.

## 4. Why now

Three converging reasons:

1. **Real auth exists for the first time.** Steps A and B replaced the
   implicit `Tenant.first / User.first` pin with cookie-session and
   OAuth-issued bearer tokens that carry a real `Current.user` /
   `Current.tenant`. Until those existed, a leak audit was meaningless: every
   request was implicitly tenant A, period. Now there's an authenticated path
   for tenant B, and the audit can actually fail.
2. **Phase 5 promised the schema is ready; Phase 6 promises the runtime
   is.** The plan checklist (§ "Multi-tenant audit") is a Phase 12
   deliverable, not a "someday" item. Splitting it off into Step C keeps
   Steps A and B shippable on their own merits while making the audit a
   first-class artifact with its own spec file, its own acceptance criteria,
   and its own row in the phase log.
3. **Hardcoded singletons rot quietly.** Every controller, job, and MCP tool
   that still reaches for `Tenant.first` or `User.first` works in single-user
   Beta and silently breaks the moment a second tenant exists. The longer
   those calls live, the harder they are to find (autocomplete suggests them,
   copy-paste propagates them). Step C is the right time to grep them out
   while the audit infrastructure is fresh.

This step is the smallest move that closes the gap between "we believe the
schema enforces tenancy" and "the test suite proves the runtime enforces
tenancy on every layer."

---

## 5. Locked decisions

- **Two-tenant fixture, not three or N.** The leak meta-test creates exactly
  two tenants ("acme" and "beta"). Two is sufficient to detect any equality vs
  containment bug; adding a third inflates spec runtime without catching a
  qualitatively new class of bug. If a future leak class requires three, the
  fixture extends — captured as a follow-up, not Step C scope.
- **Fixture lives in `spec/support/two_tenants.rb`.** A single shared support
  file, not per-spec inline. Exposes constants (`TWO_TENANTS_USER_A`,
  `TWO_TENANTS_USER_B`, etc.) and helper methods (`as_tenant_a { ... }`,
  `as_tenant_b { ... }`) so every leak spec reads the same way.
- **Leak specs grouped under `spec/leaks/`.** New top-level spec directory.
  Reasoning: easy to enumerate, easy to run in isolation
  (`bundle exec rspec spec/leaks`), easy to mark `:slow` if needed, easy for
  CI to surface separately.
- **Leak specs are NOT marked `:slow` by default.** The full leak suite must
  fit in the normal RSpec run. If runtime exceeds 60s the implementer
  consolidates fixtures (one shared two-tenant `before(:all)` per file) before
  resorting to a `:slow` exclusion. Reasoning: a leak suite that nobody runs
  is worse than no leak suite at all.
- **Every `Model.unscoped` and every direct `Model.find(id)` in production
  code is audited and either justified inline or removed.** Justification is
  a one-line comment immediately above the call:
  `# unscoped: <reason>` (e.g.,
  `# unscoped: token-based lookup pre-Current.tenant population`). Step C's
  acceptance includes a grep that asserts every such call has the comment.
- **Hardcoded `Tenant.first` / `User.first` is BANNED in production code.**
  Permitted ONLY in `db/seeds.rb`, in `lib/tasks/` rake tasks gated by
  `Rails.env`, and in tests. The grep enforces this — see §6.6.
- **HTML controller leak specs use `sign_in_as(user)`.** The Step A helper.
  Each HTML leak spec signs in as user A, hits a controller action that takes
  an id belonging to tenant B, and asserts a 404 (`ActiveRecord::RecordNotFound`
  surfaces as 404 via Rails' default `rescue_from`). 404 — not 403 — is the
  decision. Reasoning: 403 leaks the existence of the record; 404 implies "no
  such resource for you," matching the default-scope contract.
- **JSON / MCP leak specs use bearer tokens minted in `before` blocks.** A
  helper `bearer_for(user, scopes:)` mints a manual `ApiToken` with the
  requested scopes for the given user, returns the plaintext, and registers
  cleanup. Doorkeeper-issued tokens are exercised in a separate (smaller)
  leak spec to confirm the dispatch path in `Api::AuthConcern` produces the
  same `Current.tenant` as a manual token.
- **Background job leak specs use Sidekiq's inline mode.**
  `Sidekiq::Testing.inline!` for the leak suite. Each job spec enqueues with
  `tenant_id: tenant_a.id`, asserts the job's database touches stay inside
  tenant A. Then enqueues with `tenant_id: tenant_b.id`, asserts the inverse.
- **Job tenancy contract: `tenant_id` is a positional argument on every
  job's `perform`.** Step C reaffirms (and audits) that every job follows the
  Phase 5 pattern: `def perform(tenant_id, ...)` with `Current.tenant_id =
  tenant_id` as the first line and `ensure Current.reset` as the last. Jobs
  that don't follow this pattern are flagged in the audit and either
  refactored in Step C or captured as a follow-up if the refactor is
  non-trivial. **Step C ships the audit; refactors of compliant jobs are
  in-scope, refactors of jobs that need re-architecture (e.g., a job that
  currently runs across tenants by design) are out-of-scope and captured as
  follow-ups.**
- **MCP tool leak specs go through the Rack app, not the tool class
  directly.** `spec/leaks/mcp/<tool>_spec.rb` builds a Rack request with a
  bearer token for user A, dispatches through `Mcp::RackApp`, asserts the
  response payload contains no tenant B ids. Reasoning: tool-class unit specs
  bypass `Api::AuthConcern`; Rack-level specs exercise the full auth chain.
- **Documentation lives in two places.** A new top-level
  `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md` enumerates
  the audit results (which models / controllers / jobs / MCP tools were
  audited, what was found, what was fixed). The existing `docs/auth.md`
  gains a §12 "Tenant isolation guarantees" section summarizing the runtime
  contract for downstream readers.
- **No new gem.** Step C does not add `flipper-rails` or any feature-flag
  library. Phase 12's "Multi-user UI (flag-gated)" plan section is
  out-of-scope here and captured as a follow-up. Step C closes Phase 6 on
  the audit deliverable; the multi-user UI is sequenced separately so it
  doesn't bloat Step C's surface area.

---

## 6. In scope

### 6.1 Two-tenant fixture infrastructure

`spec/support/two_tenants.rb` — new. Shape:

```ruby
module TwoTenants
  def two_tenants
    @two_tenants ||= begin
      a = Tenant.find_or_create_by!(slug: "acme")  { |t| t.name = "Acme" }
      b = Tenant.find_or_create_by!(slug: "beta")  { |t| t.name = "Beta" }
      ua = User.find_or_create_by!(email: "owner@acme.test") do |u|
        u.tenant   = a
        u.password = "test-password-1"
      end
      ub = User.find_or_create_by!(email: "owner@beta.test") do |u|
        u.tenant   = b
        u.password = "test-password-2"
      end
      OpenStruct.new(a: a, b: b, user_a: ua, user_b: ub)
    end
  end

  def as_tenant_a(&block)
    Current.set(tenant: two_tenants.a, user: two_tenants.user_a, &block)
  end

  def as_tenant_b(&block)
    Current.set(tenant: two_tenants.b, user: two_tenants.user_b, &block)
  end

  def bearer_for(user, scopes: Scopes::ALL)
    Current.set(tenant: user.tenant, user: user) do
      record, plaintext = ApiToken.generate!(name: "leak-spec", scopes: scopes)
      @tokens_to_cleanup ||= []
      @tokens_to_cleanup << record
      plaintext
    end
  end
end

RSpec.configure do |c|
  c.include TwoTenants, type: :request
  c.include TwoTenants, type: :system
  c.include TwoTenants, type: :model
  c.include TwoTenants, type: :job
  c.include TwoTenants, file_path: %r{spec/leaks/}
  c.after { @tokens_to_cleanup&.each(&:destroy) }
end
```

(Pseudo-shape; implementer adapts to whatever `Tenant` / `User` factory
columns Phase 5 settled on. The point is: one helper, one set of constants,
one place to update if the schema shifts.)

### 6.2 Per-layer leak specs

For each layer, one spec file per significant unit. Each file follows the
same template:

```ruby
RSpec.describe <Unit>, type: <type> do
  it "does not leak across tenants" do
    record_a = as_tenant_a { create_record_for(...) }
    record_b = as_tenant_b { create_record_for(...) }

    as_tenant_a do
      # Operate on the unit; assert only record_a is reachable.
    end

    as_tenant_b do
      # Operate on the unit; assert only record_b is reachable.
    end
  end
end
```

#### 6.2.1 Model leak specs — `spec/leaks/models/`

One file per `BelongsToTenant`-bearing model. Enumerated dynamically:

```ruby
ApplicationRecord.descendants
  .select { |m| m.include?(BelongsToTenant) }
  .each do |model|
    # Generate a leak spec for the model.
  end
```

Each spec asserts:

- `Model.all` returns only `Current.tenant`'s records.
- `Model.find(record_a.id)` (run as tenant B) raises
  `ActiveRecord::RecordNotFound`.
- `Model.where(...)` queries respect tenant.
- `Model.unscoped.all` returns all records (sanity check that `unscoped`
  works as expected; this is the one place `unscoped` is used in tests).

The list of models is captured statically at the time of spec writing;
implementer enumerates them by running the descendants check once and
hardcoding the list to keep the spec deterministic. **Do not** rely on
`ApplicationRecord.descendants` at spec-runtime (eager-loading in test env
is fragile). The list lives at the top of `spec/leaks/models/_index.rb` (or
similar) and the implementer updates it when adding a new tenanted model.

Anticipated models (subject to revision at implementation time, based on
what's actually present in `app/models/`): `Channel`, `Video`, `Project`,
`Footage`, `ProjectReference`, `Note`, `Timeline`, `Game`, `SavedView`,
`AppSetting`, `ApiToken`, `Session`, `OauthApplication`, `OauthAccessToken`,
`OauthAccessGrant`. The implementer reconciles against the actual model
inventory.

#### 6.2.2 Controller leak specs — `spec/leaks/requests/`

One file per HTML controller resource. Each file walks the controller's
RESTful actions and asserts that authenticated-as-user-A access to a
record owned by tenant B returns 404:

- `GET /<resource>` — index returns only tenant A's records (no tenant B
  ids in the rendered HTML or JSON body).
- `GET /<resource>/<id_b>` — 404.
- `PATCH /<resource>/<id_b>` — 404.
- `DELETE /<resource>/<id_b>` (or the bulk `/deletions/<type>/<id_b>` per
  the project's hard rule) — 404.
- Any nested resource — same pattern with the nested id.

Anticipated HTML controllers (subject to inventory verification):
`ChannelsController`, `VideosController`, `ProjectsController`,
`FootagesController`, `NotesController`, `TimelinesController`,
`GamesController`, `SavedViewsController`, `Settings::*Controller`,
`DeletionsController`, `SyncsController`. The implementer reconciles
against the actual controller inventory.

JSON-API controllers — same pattern using `bearer_for(user_a)` and
`bearer_for(user_b)`. Asserts 404 (or 403 with an explicit
`tenant_mismatch` reason — implementer picks based on the existing JSON
error envelope; spec accepts either as long as the chosen shape is
consistent across all JSON leak specs).

`/deletions/:type/:ids` — when `:ids` includes records from BOTH tenants,
the action returns 404 (treats the whole batch as missing) and writes
NOTHING to either tenant. Reasoning: partial success on cross-tenant
batches is a footgun; fail-closed is safer.

#### 6.2.3 Background job leak specs — `spec/leaks/jobs/`

One file per Sidekiq job. Pattern:

```ruby
RSpec.describe SomeJob, type: :job do
  it "respects tenant_id and does not touch other tenants' rows" do
    record_a = as_tenant_a { Footage.create!(...) }
    record_b = as_tenant_b { Footage.create!(...) }

    SomeJob.new.perform(two_tenants.a.id, record_a.id)
    expect(record_a.reload).to be_processed
    expect(record_b.reload).not_to be_processed
  end
end
```

Jobs to audit (subject to inventory verification): `ChannelSync`,
`VoyageEmbeddingJob`, `MeilisearchIndexingJob`, every job under
`app/jobs/`. The implementer reconciles against the actual job inventory.

The audit also asserts each job's `perform` signature begins with
`tenant_id`. Jobs that don't conform are documented in `security.md` with
a follow-up to refactor.

#### 6.2.4 MCP tool leak specs — `spec/leaks/mcp/`

One file per MCP tool. Pattern:

```ruby
RSpec.describe "MCP tool: list_channels", type: :request do
  it "returns only Current.tenant's records" do
    as_tenant_a { Channel.create!(channel_url: "https://yt/a") }
    as_tenant_b { Channel.create!(channel_url: "https://yt/b") }

    token = bearer_for(two_tenants.user_a, scopes: %w[yt:read])
    response = post_mcp_tool("list_channels", {}, token: token)

    expect(response[:channels].map { |c| c[:url] }).to eq(["https://yt/a"])
  end
end
```

`post_mcp_tool(name, args, token:)` — new helper in
`spec/support/mcp_helpers.rb` that builds a Rack request to `Mcp::RackApp`,
sets the `Authorization: Bearer <token>` header, parses the JSON-RPC
response, returns the result.

Tools to audit (subject to inventory verification, anticipated from
`docs/mcp.md` and `app/mcp/`): `list_docs`, `read_doc`, `save_note`,
`list_channels`, `list_videos`, `dashboard`, `list_saved_views`,
`delete_records`, `sync_records`. The implementer reconciles against the
actual tool inventory.

#### 6.2.5 Auth dispatch leak spec — `spec/leaks/auth_dispatch_spec.rb`

One spec file that proves both auth lanes (manual `ApiToken` and
Doorkeeper-issued OAuth token) populate `Current.tenant` consistently:

- Mint a manual `ApiToken` for user A. Hit any JSON endpoint. Assert
  `Current.tenant == tenant_a` during the request.
- Issue a Doorkeeper access token for user A (via the Step B test helper
  that performs the full Auth Code + PKCE flow). Hit the same JSON
  endpoint. Assert `Current.tenant == tenant_a`.
- Issue a Doorkeeper access token for user A bound to a `pito-cli`
  application that itself is tenant B (corner case: the application's
  `tenant_id` differs from the resource owner's `tenant_id`). Assert the
  resolution prefers `token.resource_owner.tenant` (the user's tenant) and
  emits an `auth.tenant_mismatch` audit log line. Reasoning: applications
  shouldn't issue tokens that escape the user's tenant; if Doorkeeper does
  it anyway (via misconfiguration), the runtime catches it loud.

### 6.3 `Tenant.first` / `User.first` retirement

Implementer runs:

```bash
git grep -nE 'Tenant\.first|User\.first' \
  -- 'app/' 'lib/' 'config/' \
  ':!config/initializers/two_tenants.rb' \
  ':!app/models/concerns/belongs_to_tenant.rb'
```

Every match in `app/`, `lib/`, `config/` (excluding tests and seeds) is
either:

1. Removed and replaced with `Current.tenant` / `Current.user`.
2. Replaced with a tenant-aware lookup (`Tenant.find_by(slug: ...)`).
3. Justified inline with a comment like
   `# Tenant.first: rake-only, gated by Rails.env.development?`.

`db/seeds.rb` retains `Tenant.first` / `User.first` as needed — that's the
seeding lane. `lib/tasks/*.rake` files retain them only behind a
`Rails.env.development? || Rails.env.test?` gate.

### 6.4 `unscoped` audit

Implementer runs:

```bash
git grep -nE 'unscoped' -- 'app/' 'lib/' ':!app/models/concerns/belongs_to_tenant.rb'
```

Every match must have a justifying comment on the line immediately above
it. Examples of legitimate use:

- `Sessions::Authenticator#call` — looks up `Session.unscoped` because the
  request hasn't populated `Current.tenant` yet (the row defines the
  tenant). Comment: `# unscoped: pre-Current.tenant token lookup`.
- `Api::TokenAuthenticator#call` — same shape for `ApiToken.unscoped`.
- `Doorkeeper`-bridge code in `Api::AuthConcern` — same shape.

A spec at `spec/leaks/unscoped_audit_spec.rb` runs the grep at spec-time
and fails if a match lacks a justifying comment. Pseudo-shape:

```ruby
it "every unscoped call in production code has a justifying comment" do
  matches = `git grep -nE 'unscoped' -- 'app/' 'lib/'`.lines
  unjustified = matches.reject do |line|
    file, lineno, = line.split(":", 3)
    prev = File.readlines(file)[lineno.to_i - 2]
    prev.to_s.match?(/#\s*unscoped:/)
  end
  expect(unjustified).to be_empty,
    "Unscoped calls without justifying comment:\n#{unjustified.join}"
end
```

### 6.5 `Model.find` (vs default-scoped lookup) audit

Same pattern as §6.4 but for `Model.find(...)` calls in non-test code that
might bypass the default scope. The grep is wider; the implementer
manually classifies each match:

- `Model.find(params[:id])` inside a controller — fine, default scope is
  on, tenant B id raises `RecordNotFound` → 404.
- `Model.find(some_id)` inside a job — fine if `Current.tenant_id` is set
  before the call (per §6.2.3 / Phase 5 contract); if not, document as a
  follow-up.
- `Model.find_by(some_field: val)` in a Rack-level authenticator — needs
  `unscoped` for token lookups (Phase 5 / Phase 6A pattern); the §6.4
  audit covers this.

The classification result lands in `security.md` as a table.

### 6.6 Grep enforcement spec

`spec/leaks/forbidden_patterns_spec.rb` — new. Runs the grep checks above
at spec time so regressions surface in CI. Verifies:

- No `Tenant.first` or `User.first` in `app/`, `lib/`, `config/` (except
  whitelisted lines documented in the spec itself).
- No `data-turbo-confirm` (existing project hard rule, reaffirmed here so
  the leak suite catches accidental introductions).
- No `unscoped` in production code without a justifying comment.

This spec doubles as living documentation of the project's forbidden
patterns. New patterns added later land in this same file.

### 6.7 `security.md` — audit results document

`docs/plans/beta/12-auth-ui-multi-user-readiness/security.md` — new.
Sections:

- **Audit scope** — which layers were audited (models, controllers, jobs,
  MCP tools).
- **Inventory** — table of every audited unit (model name, controller
  name, job class, MCP tool name) with a column for "leak spec file"
  pointing to the spec under `spec/leaks/`.
- **Findings** — what was found during the audit. Expected to be mostly
  "no leak detected" but any finding (even cosmetic) is documented.
- **Fixes applied** — list of code changes Step C makes (Tenant.first
  retirements, unscoped justifications added, job signatures fixed).
- **Follow-ups** — anything found that was too large to fix in Step C is
  captured as a follow-up entry that the master agent will append to
  `docs/orchestration/follow-ups.md` after Step C closes.

The doc is written by the implementer **after** the leak suite is green;
it's a record of the audit, not a plan for the audit.

### 6.8 `docs/auth.md` — §12 Tenant isolation guarantees

Add a new section §12 to `docs/auth.md` (the file Phase 5 Step C / Phase 6
Step C own jointly). Contents:

- The two-tenant test fixture pattern.
- The default-scope contract (every `BelongsToTenant`-bearing model
  filters by `Current.tenant_id`).
- The job tenancy contract (`perform(tenant_id, ...)` with
  `Current.set` / `Current.reset` lifecycle).
- The MCP / API auth dispatch contract (every authenticated request has a
  resolvable tenant or fails closed).
- The `unscoped` justification convention.
- A reference to `spec/leaks/` as the executable form of the contract.

Cross-link from `docs/architecture.md` (the §Auth section gets a one-line
pointer to §12 of `docs/auth.md`).

### 6.9 Audit log events

Step C does not add new audit log event types. It DOES verify that the
existing events from Phase 5 / Phase 6 A / B all carry `tenant_id` in
their JSON payload (cross-checked via `spec/leaks/audit_log_spec.rb`). Any
event missing `tenant_id` is fixed in Step C.

### 6.10 Follow-up: multi-user UI (NOT in Step C)

The phase plan's "Multi-user UI (flag-gated)" section is **explicitly
deferred** to a future step (Phase 6.5 or Phase 12 polish) so Step C ships
with a tight focus on the audit. Captured as Open Question.

---

## 7. Out of scope

- **Multi-user invitation flow / Settings → Users page / `flipper-rails`
  gem** — deferred to a separate step; Phase 6 closes on the audit, not on
  multi-user UI.
- **Public signup** — Theta.
- **2FA / TOTP / WebAuthn** — Theta.
- **Account deletion / data export** — Theta (GDPR concerns require real
  multi-tenant production data first).
- **SMTP wiring / password reset / email change** — owned by Step 6A.5,
  not Step C.
- **CLI migration to Doorkeeper-issued tokens** — owned by a follow-up
  (`cli-impl` agent), not Step C.
- **Performance / load testing of the leak suite at scale** — Phase 11
  observability concern. Step C ensures the suite runs in <60s on a
  developer laptop; further tuning is later.
- **Rate limit sweep beyond login + `/oauth/token`** — Phase 15.
- **Refactoring jobs that legitimately span tenants by design** — Step C
  flags them; refactor is a follow-up.

---

## 8. Acceptance criteria

- [ ] `spec/support/two_tenants.rb` exists; defines `two_tenants`,
      `as_tenant_a`, `as_tenant_b`, `bearer_for` helpers; is included in
      every spec under `spec/leaks/` and in request / system / model / job
      specs that opt in.
- [ ] `spec/leaks/` directory exists with subdirectories `models/`,
      `requests/`, `jobs/`, `mcp/` plus the auth dispatch / unscoped /
      forbidden-patterns / audit-log top-level specs.
- [ ] Every `BelongsToTenant`-bearing model has a leak spec under
      `spec/leaks/models/`. The spec asserts `.all` returns only
      `Current.tenant`'s records and that `Model.find(other_tenant_id)`
      raises `ActiveRecord::RecordNotFound`.
- [ ] Every HTML controller with a tenanted resource has a leak spec under
      `spec/leaks/requests/`. The spec asserts cross-tenant id access
      returns 404 across index / show / update / destroy.
- [ ] Every JSON-API controller has a leak spec — both manual `ApiToken`
      and Doorkeeper-issued bearer cases.
- [ ] Every Sidekiq job under `app/jobs/` has a leak spec. The spec asserts
      `perform(tenant_id, ...)` only touches that tenant's records.
- [ ] Every MCP tool registered in `Mcp::RackApp` has a leak spec under
      `spec/leaks/mcp/` going through the full Rack dispatch.
- [ ] `spec/leaks/auth_dispatch_spec.rb` proves both auth lanes (manual
      and OAuth) produce the same `Current.tenant` for the same user.
- [ ] No `Tenant.first` or `User.first` references remain in `app/`,
      `lib/`, or `config/` outside `db/seeds.rb` and gated rake tasks.
      `spec/leaks/forbidden_patterns_spec.rb` enforces.
- [ ] Every `unscoped` call in `app/` and `lib/` has a justifying
      `# unscoped: <reason>` comment on the line immediately above. Spec
      enforces.
- [ ] Every Sidekiq job's `perform` accepts `tenant_id` as its first
      positional argument (or is documented in `security.md` as a
      legitimate cross-tenant exception).
- [ ] Every audit log event in `log/auth_audit.log` carries `tenant_id`
      in its payload. Spec enforces.
- [ ] `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md`
      exists and lists every audited unit, findings, fixes, and any
      follow-ups.
- [ ] `docs/auth.md` §12 "Tenant isolation guarantees" exists and is
      cross-linked from `docs/architecture.md`.
- [ ] All previously-green specs remain green.
- [ ] Full `bundle exec rspec` (including `spec/leaks`) completes in <90s
      on the developer's laptop. (Soft target; if exceeded, implementer
      consolidates fixtures before tagging `:slow`.)
- [ ] `bundle exec rspec spec/leaks` runs cleanly in isolation (CI lane
      can target it specifically).
- [ ] Brakeman, bundler-audit, Dependabot — clean.

---

## 9. Manual playbook

1. `bin/setup` succeeds; `bin/dev` boots both Pumas.
2. Open `bin/rails console` —
   `Tenant.create!(slug: "manual-leak", name: "Manual Leak Test")`.
   `User.create!(tenant: Tenant.last, email: "leak@test", password: "x"*12)`.
3. Log in as the original seeded owner via `/login`. Land on `/`.
4. Manually craft a URL pointing to a record owned by the new tenant — e.g.,
   `Channel.create!(...)` as the new tenant in the console, capture its id,
   visit `/channels/<id>` in the browser. Expect 404 (not 403, not a
   render).
5. Same for `/projects/<id>`, `/footages/<id>`, `/videos/<id>` — every
   tenanted resource. Each returns 404.
6. Mint an `ApiToken` for the seeded owner via `/settings/tokens`. `curl`
   the JSON API for a record id owned by the new tenant — expect 404 (or
   the chosen JSON error envelope).
7. From the same `bin/rails console`, run a job manually with the wrong
   tenant id:
   `ChannelSync.new.perform(Tenant.last.id, Channel.first.id)`. Inspect
   `Channel.first.reload.last_synced_at` — expect unchanged (the job
   should no-op or raise on cross-tenant id). The exact behavior is
   implementer's choice (raise vs no-op); the spec captures whichever
   shape is implemented.
8. `bundle exec rspec spec/leaks` — green. Time it; expect under 60s.
9. `bundle exec rspec` (full suite) — green. Time it; expect under 90s.
10. `git grep -nE 'Tenant\.first|User\.first' -- 'app/' 'lib/' 'config/'` —
    empty (or matches only justified by inline comments).
11. `git grep -nE 'unscoped' -- 'app/' 'lib/'` — every match has a
    `# unscoped:` comment immediately above.
12. Open `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md` —
    every audited unit listed with a row pointing at its leak spec.
13. Open `docs/auth.md` — §12 exists and cross-references `spec/leaks/`.

---

## 10. File-scope inventory

Implementer (Lane 1 rails-impl) touches:

- `spec/support/two_tenants.rb` — new.
- `spec/support/mcp_helpers.rb` — new (`post_mcp_tool` helper). If a
  similar helper already exists from Phase 4 / 5, extend rather than
  recreate.
- `spec/leaks/` — new directory. Sub-files under `models/`, `requests/`,
  `jobs/`, `mcp/` plus top-level files: `auth_dispatch_spec.rb`,
  `unscoped_audit_spec.rb`, `forbidden_patterns_spec.rb`,
  `audit_log_spec.rb`.
- `app/` — surgical edits only, justified by audit findings:
  - Replace any `Tenant.first` / `User.first` in production code paths
    with `Current.tenant` / `Current.user` or a tenant-aware lookup.
  - Add `# unscoped: <reason>` comments above every `unscoped` call in
    production code.
  - Adjust any job whose `perform` signature lacks `tenant_id` as the
    first arg, where the refactor is trivial. Non-trivial refactors land
    as follow-ups.
  - Backfill `tenant_id` into any audit log event payload that lacks it.
- `lib/` — same scope as `app/`.
- `config/` — same scope as `app/`. Initializers that read
  `Tenant.first` / `User.first` at boot are flagged and refactored.
- `db/seeds.rb` — untouched (seeds may use `Tenant.first` / `User.first`
  legitimately).
- `lib/tasks/*.rake` — touched only to add `Rails.env` gates around
  `Tenant.first` / `User.first` calls if they're not already present.
- `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md` — new.
- `docs/auth.md` — append §12.
- `docs/architecture.md` — one-line pointer added to the §Auth section.

Out of bounds for this step:

- `app/views/**` — Step C does not touch the user-facing UI. Multi-user UI
  is a follow-up.
- `app/controllers/sessions_controller.rb`,
  `app/controllers/concerns/sessions/auth_concern.rb` — owned by Step A.
- `config/initializers/doorkeeper.rb`, `app/models/oauth_*.rb` — owned by
  Step B.
- `extras/cli/**`, `extras/website/**` — Step C is server-side; CLI /
  website surfaces are out of scope. CLI tenant-correctness depends on
  the bearer token it sends; that's covered by the JSON-API leak specs
  on the server side.
- `app/lib/scopes.rb`, `Pito::TokenDigest`, `ApiToken`, `Session` model
  internals — owned by earlier phases / steps.

## 11. Open questions

- **Multi-user UI sequencing.** The phase plan's "Multi-user UI
  (flag-gated)" section is deferred. Confirm whether to land it as a
  Phase 6.5 sub-step (delays Phase 6 close) or punt to a Phase 12 polish
  window after Phase 7 (Phase 6 closes faster, multi-user UI lands when
  there's a clearer driver). **Default if not answered: punt to Phase
  6.5 polish, file follow-up entry.**
- **JSON error envelope for cross-tenant id leaks.** Spec accepts either
  404 or 403-with-`tenant_mismatch` reason; implementer picks one shape
  and uses it consistently across every JSON leak spec. Confirm: is
  there a preference? **Default: 404 (matches HTML behavior, matches
  default-scope contract — pretend the record doesn't exist).**
- **Cross-tenant `delete_records` MCP tool batches.** The MCP
  `delete_records` tool takes a list of ids. Spec assumes a batch
  containing at least one id from a different tenant fails closed
  (entire batch rejected, no partial writes). Confirm shape.
- **Fixture cleanup strategy.** Spec assumes RSpec's transactional
  fixtures wrap each example so the two-tenant data is rolled back
  between specs. Confirm: is there a `:truncation` strategy already in
  use for any spec type that conflicts? **Default: rely on transactional
  fixtures; if a spec requires truncation, opt in explicitly per file.**
- **Job audit findings — refactor vs follow-up boundary.** Spec defines
  "trivial = changing the perform signature; non-trivial = changing the
  job's tenant model." Confirm the boundary. If a job's redesign is in
  scope, Step C scope inflates; if not, it stays a follow-up.
- **`security.md` location.** Spec places it under
  `docs/plans/beta/12-auth-ui-multi-user-readiness/security.md`.
  Alternative: a top-level `docs/security.md` that future phases extend.
  Confirm: phase-scoped (matches plan §"Multi-tenant audit") or
  cross-cutting top-level doc. **Default: phase-scoped per the plan
  text.**
- **Audit log `tenant_id` backfill scope.** Spec assumes adding
  `tenant_id` to event payloads that lack it is in scope (small
  surgical change). If any event source is in a third-party gem (e.g.,
  Doorkeeper notifications), confirm the implementer is allowed to wrap
  the subscriber to enrich the payload. **Default: yes, enrich at the
  subscriber.**
