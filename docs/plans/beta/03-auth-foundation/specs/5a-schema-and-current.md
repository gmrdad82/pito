# Phase 3 — Step A — Schema Completion and Current Wiring

> Foundation step for Phase 3 (Auth Foundation). Locks the multi-tenant schema
> shape, formalizes a handful of departures from the original plan, adds the
> `belongs_to_tenant` concern, and proves cross-tenant isolation with paired
> fixtures. Date: 2026-05-05. Locked decisions are pinned exactly — do not
> reinvent.

---

## 1. Goal

Finish the multi-tenant schema started in Channel Revamp. Every data-holding
table that survived Alpha and Phase 4 gets a `tenant_id` (NOT NULL, FK to
tenants). A `belongs_to_tenant` concern enforces tenant isolation at the model
layer with a default scope keyed on `Current.tenant_id`. Two-tenant fixtures
prove no cross-tenant leak through any normal ActiveRecord usage.

This step also formalizes four schema departures from the original Phase 3 plan
that crystallized during Channel Revamp and Phase 4: the global uniqueness of
`users.email` / `users.username`, the absence of `users.role` and `users.name`,
and the missing `tenants.slug`. Each is decided, applied, and documented here so
Steps B and C build on a settled schema.

## 2. Depends on

- Channel Revamp's `Tenant`, `User`, `Current`, and
  `before_action :set_current_tenant_and_user` patch.
- Phase 4's project-workspace tables (`projects`, `collections`, `games`,
  `footages`, `notes`, `timelines`, `project_references`) — already tenanted
  from day one; this step does not touch their `tenant_id` columns.
- A parallel pre-Phase-3 patch wiring `Current.reset` after each spec via
  `rails_helper.rb` `after(:each)`. This step assumes that patch lands first.

## 3. Unblocks

- Step B (`5b-token-and-auth-concern.md`) — `ApiToken` needs `tenant_id` /
  `user_id` columns, which this step adds (alongside the rest of the
  data-holding tables).
- Step C (`5c-settings-ui-and-docs.md`) — Settings UI for tokens depends on a
  settled schema and the `belongs_to_tenant` enforcement spec being green.
- Phase 6 onward — every later phase assumes `Current.tenant_id` reliably scopes
  every model query.

## 4. Why now

The Phase 3 plan calls out that adding tenant columns now, while the dataset is
seeds only, costs hours; adding them after real YouTube data and embeddings
costs weeks. Channel Revamp tenanted `channels` but stopped there — leaving
videos, playlists, video_stats, video_uploads, saved_views, bulk_operations,
bulk_operation_items, and mcp_access_tokens (the de-facto Beta token table)
without a tenant column. Step B introduces token-based auth that populates
`Current.tenant` from a token; without uniform tenant scoping, that population
is decorative.

This step is also the right moment to lock the four schema departures. Step B
and Step C both reference the User and Tenant shapes; neither should re-litigate
`role`, `name`, or `slug`.

---

## 5. In scope

### 5.1 Tenant column additions

Add `tenant_id` (`bigint`, NOT NULL, FK to `tenants`, indexed) to:

- `videos` — backfill via `channel.tenant_id`.
- `playlists` — backfill via `channel.tenant_id`.
- `playlist_items` — backfill via `playlist.tenant_id` (after `playlists` is
  tenanted in the same migration sequence).
- `video_stats` — backfill via `video.tenant_id` (after `videos`).
- `video_uploads` — backfill via `video.tenant_id` (after `videos`).
- `saved_views` — backfill to the seeded tenant (`Tenant.first.id`); SavedView
  is user-data-holding but currently has no obvious lineage column.
- `bulk_operations` — backfill to the seeded tenant.
- `bulk_operation_items` — backfill via `bulk_operation.tenant_id` (after
  `bulk_operations`).
- `mcp_access_tokens` — backfill to the seeded tenant. (Step B renames the table
  to `api_tokens` and adds further columns; this step only adds the `tenant_id`
  column so the schema is uniform when Step B starts.)

**Migration shape per table.** Three-step pattern, each as its own migration so
rollback is cheap:

1. `add_reference :<table>, :tenant, foreign_key: true, null: true`.
2. Backfill via `update_columns(tenant_id: <derived>)` in a data migration —
   `update_columns` skips validations and callbacks, important because
   `belongs_to_tenant`'s default scope would otherwise filter the very rows
   we're trying to update.
3. `change_column_null :<table>, :tenant_id, false`.

Each migration is reversible (`up` / `down` explicit; no `change` blocks for the
backfill steps).

Index every `tenant_id` column. Composite indexes follow Phase 4's convention:
`(tenant_id, <natural sort key>)` where one already exists scoped by something
else — adjust on a per-table basis at implementation time.

### 5.2 Footage tenant_id normalization

`footages.tenant_id` is currently nullable while every other Phase 4 sibling is
NOT NULL. Decision: **make NOT NULL.** Steps:

1. Backfill any null rows from `project.tenant_id`.
2. `change_column_null :footages, :tenant_id, false`.
3. Keep the `before_validation` callback that denormalizes `tenant_id` from
   `project` — but tighten it: raise a clear error if `project` is also nil,
   rather than silently letting the row through.

The callback is preserved (not dropped) because it's the convenience the Project
Show flow relies on; the spec just wants it to fail loud.

### 5.3 Schema departures — formally decided

Four departures from the Phase 3 plan get a one-line resolution and a paragraph
in `docs/architecture.md` (Step C edits the doc; this spec records the
decisions).

- **`tenants.slug` (citext, unique).** Decision: **add it.** Migration creates
  the column, backfills existing seeded tenant with `slug` derived from
  `:owner.tenant_slug` credentials block (default `"primary"` if absent), then
  sets NOT NULL + unique index. Seed updated to set slug at create time.
- **`users.role`.** Decision: **formally drop.** Single-user world; the column
  has no readers. If `docs/plans/beta/03-auth-foundation/dropped.md` does not
  exist, skip the dropped-list write — Step C captures the decision in
  `docs/auth.md` instead. (The original plan's `role: "owner"` default is now
  meaningless.)
- **`users.name`.** Decision: **formally drop.** `username` plus `email` cover
  every display need. Same disposition as `role`.
- **`users.email` / `users.username` global uniqueness.** Decision: **document
  as a deliberate departure.** Single-tenant tractable; the per-tenant
  uniqueness story is revisited when multi-tenant ships in Theta. No schema
  change here — the unique indexes stay single-column. Step C documents the
  rationale in `docs/architecture.md` and `docs/auth.md`.

### 5.4 `belongs_to_tenant` concern

New concern at `app/models/concerns/belongs_to_tenant.rb`:

```ruby
module BelongsToTenant
  extend ActiveSupport::Concern

  included do
    belongs_to :tenant
    validates :tenant_id, presence: true

    default_scope do
      if Current.tenant_id
        where(tenant_id: Current.tenant_id)
      else
        raise TenantContextMissing, "Current.tenant_id required for #{name}"
      end
    end
  end

  class TenantContextMissing < StandardError; end
end
```

**Locked decision — fail loud.** A query against a tenant-scoped model with no
`Current.tenant_id` raises `BelongsToTenant::TenantContextMissing`. Bugs should
be loud, not silent. Tests that need to bypass the scope use `Model.unscoped`
explicitly — there is no `with_tenant_context_optional` escape hatch.

The concern is included in:

- Existing tenanted models from Channel Revamp: `Channel`.
- All data-holding models that gain `tenant_id` in §5.1: `Video`, `Playlist`,
  `PlaylistItem`, `VideoStat`, `VideoUpload`, `SavedView`, `BulkOperation`,
  `BulkOperationItem`, `McpAccessToken` (renamed `ApiToken` in Step B).
- Phase 4 already-tenanted models: `Project`, `Collection`, `Game`, `Footage`,
  `Note`, `Timeline`, `ProjectReference`.

`Tenant` and `User` themselves do **not** include the concern — `Tenant` has no
`tenant_id`, and `User` is the row that defines tenant membership for tokens and
is queried by login flows that don't have a `Current` set yet.

### 5.5 Cross-tenant leak spec

New shared spec under `spec/support/cross_tenant_leak_spec.rb` (or as a feature
spec under `spec/system/`). Pattern:

1. Two-tenant fixture: factory creates `tenant_a` and `tenant_b` with one user
   each and one of every data-holding model in each tenant.
2. Set `Current.tenant = tenant_a`.
3. For each tenanted model, assert `.count == 1` and the loaded row belongs to
   `tenant_a`.
4. Assert `Model.find(<tenant_b row id>)` raises `ActiveRecord::RecordNotFound`
   (because the default scope filters it out before the find).
5. Switch `Current.tenant = tenant_b`, repeat — assert symmetry.
6. Reset `Current` (via the `Current.reset` `after(:each)`); assert that any
   query against any tenanted model raises
   `BelongsToTenant::TenantContextMissing`.

Every controller spec also gets a one-line assertion: the controller's
`before_action :set_current_tenant_and_user` populates `Current.tenant` to
`Tenant.first` — verified by an `expect(Current.tenant).to eq(Tenant.first)`
inside one representative action.

### 5.6 Seeds

Update `db/seeds.rb`:

- Tenant seed reads `:owner.tenant_slug` from credentials (fallback `"primary"`)
  and sets `slug` at create time.
- User seed unchanged in shape (`username`, `email`, `password_digest`); the
  removed `role` / `name` columns mean any seed code referencing them gets
  cleaned up.
- Existing data-holding seeds (videos, playlists, saved_views, etc.) get
  `tenant: Tenant.first` set explicitly. Run with
  `Current.tenant = Tenant.first` wrapping the seed body so default-scoped reads
  inside the seed file work.

### 5.7 Factory updates

`FactoryBot` definitions for every newly-tenanted model get a `tenant`
association (default `Tenant.first` or `association :tenant`). Existing
factories that already pass `tenant: ...` (Phase 4 ones) need no change.

---

## 6. Out of scope

- `ApiToken` columns beyond `tenant_id` — Step B renames the table and adds
  `user_id`, `scopes`, `expires_at`.
- Bearer-token auth, scope catalog, `require_scope!` helper — all Step B.
- Settings UI for tokens — Step C.
- `docs/auth.md`, `docs/architecture.md`, `docs/mcp.md` updates — Step C.
- `Current.reset` `after(:each)` wiring — owned by the parallel pre-Phase-3
  patch; this step assumes it has landed.
- Per-tenant uniqueness on `users.email` / `users.username` — explicitly
  deferred to multi-tenant in Theta.
- Per-tenant `Channel.channel_url` uniqueness review — out of scope; Channel
  Revamp's index choice stands until multi-tenant lands.

---

## 7. Acceptance criteria

- [ ] `tenant_id` exists, NOT NULL, indexed, with FK to `tenants` on every table
      listed in §5.1.
- [ ] `footages.tenant_id` is NOT NULL; the `before_validation` callback raises
      if `project` is nil.
- [ ] `tenants.slug` exists, citext, unique, NOT NULL; seeded tenant has its
      slug set from `:owner.tenant_slug` (or `"primary"`).
- [ ] `users` table no longer has `role` or `name` columns.
- [ ] `BelongsToTenant` concern exists at
      `app/models/concerns/belongs_to_tenant.rb` and is included by every
      tenanted model listed in §5.4.
- [ ] Querying any tenanted model with `Current.tenant_id == nil` raises
      `BelongsToTenant::TenantContextMissing`.
- [ ] Cross-tenant leak spec is green: with `Current.tenant = tenant_a`, no
      tenant_b row is reachable through any normal ActiveRecord call.
- [ ] All migrations are reversible (`db:rollback STEP=N` for the count of
      migrations in this step round-trips cleanly).
- [ ] Seeds populate without error after `bin/rails db:reset`.
- [ ] All previously-green RSpec specs (~1361) remain green.
- [ ] New specs cover: `BelongsToTenant` default scope, the leak scenario, the
      `tenants.slug` validation, the `footages` denormalization callback's raise
      behavior.
- [ ] Brakeman, bundler-audit, Dependabot — clean.

---

## 8. Manual playbook

Run after the implementer reports green:

1. `bin/rails db:reset` — fresh DB, migrations apply forward, seeds populate.
2. `bin/rails db:rollback STEP=<count of new migrations>` — every migration
   rolls back cleanly. Re-run `bin/rails db:migrate` and `bin/rails db:seed` to
   land back on the green state.
3. `bin/rails console` —
   - `Tenant.count` → `1`. `Tenant.first.slug` → `"primary"` (or whatever
     `:owner.tenant_slug` says).
   - `User.first.respond_to?(:role)` → `false`. Same for `:name`.
   - `Current.tenant = Tenant.first; Video.count` → integer (no raise).
   - `Current.reset; Video.count` → raises
     `BelongsToTenant:: TenantContextMissing`.
   - `Current.tenant = Tenant.first; Footage.new(project: nil).valid?` → raises.
4. `bundle exec rspec` — green, including the new leak spec.
5. `bundle exec rspec spec/<path-to-leak-spec>.rb` — green standalone.
6. Visit `/`, `/channels`, `/videos`, `/saved_views` in the browser — all load
   as before; the seeded user is implicitly current via the existing
   `before_action`.
7. `bin/rails console` — `t2 = Tenant.create!(name: "Test", slug: "test")`,
   `Current.tenant = t2; Video.count` → `0` (no leak from tenant_a).

---

## 9. File-scope inventory

Implementer (Lane 1 rails-impl) touches:

- `db/migrate/<timestamp>_*.rb` — one migration per table for the three-step
  add-reference / backfill / set-not-null pattern. Plus one for `tenants.slug`,
  one for the `footages` not-null tightening, and one for the `users.role` +
  `users.name` drops.
- `app/models/concerns/belongs_to_tenant.rb` — new.
- `app/models/{video,playlist,playlist_item,video_stat,video_upload, saved_view,bulk_operation,bulk_operation_item,mcp_access_token}.rb`
  — include `BelongsToTenant`.
- `app/models/footage.rb` — tighten `before_validation` callback.
- `app/models/user.rb` — drop `role` / `name` references if present.
- `db/seeds.rb` — tenant slug, `Current` wrap, drop `role` / `name` references.
- `spec/factories/*.rb` — add `tenant` to every newly-tenanted factory.
- `spec/support/cross_tenant_leak_spec.rb` (or `spec/system/...`) — new.
- `spec/models/concerns/belongs_to_tenant_spec.rb` — new.
- `spec/models/footage_spec.rb` — assert the raise on missing project.
- `spec/models/tenant_spec.rb` — assert slug validation + uniqueness.

Out of bounds for this step:

- `app/controllers/**` — controllers do not change.
  `before_action :set_current_tenant_and_user` is the parallel patch's
  territory.
- `app/mcp/**` — Step B owns the auth concern wiring into MCP.
- `docs/**` — Step C owns the doc updates.
- Anything under `extras/` — CLI / website are downstream consumers; they get
  touched in later phases when bearer-token UX matters.

## 10. Open questions

- Confirm the seed default `tenant_slug` is `"primary"` if `:owner.tenant_slug`
  is absent. (Plan says `"primary"`; credentials may or may not have the key.)
- Confirm there is no caller of `User#role` or `User#name` left in the codebase.
  A repo-wide grep at implementation start should confirm zero hits before the
  migration drops the columns; any hit pauses the step.
