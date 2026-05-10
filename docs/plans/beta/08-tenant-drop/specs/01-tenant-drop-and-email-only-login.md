# Phase 8 — Tenant Drop + Email-Only Login

> **Status:** dispatched 2026-05-10. First concrete dispatch following the
> 2026-05-09 realignment. Implementation lane: **rails** (single lane — no Rust,
> no Astro this round).
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; Resolved
>   ambiguity #9 ("Tenant model — full drop, DB reseed").
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — ADR.
>   "Migration posture" section locks destructive-and-reseed.
> - `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` — sets
>   the trajectory for Phase 9 (`GoogleIdentity` rename); explicitly **out of
>   scope** here.
> - `docs/plans/beta/08-tenant-drop/log.md` — phase log; "Next" section names
>   this dispatch.
> - `CLAUDE.md` — top-level project rules (yes/no booleans, Confirmable
>   bulk-as-foundation, secrets in credentials, monospace 13px, etc.).

## Goal

Translate ADR 0003's commitment into code. Drop tenant scoping from every layer
(schema, models, concerns, `Current`, controllers, MCP rack app, Doorkeeper
boundary check, storage paths, seed, factories, specs). In the same sweep,
narrow `User` to the thin auth-only shape (email + password only — no
`username`, no `tenant_id`) and switch the login form to **email-only**
authentication. Reseed via `db:seed` from the new `:owner` credentials block
(`{ email, password }`).

This is the prerequisite for every other realignment work unit. It is
intentionally narrow: schema expansion (Notes 1 / 4 / 6 / 7 from the realignment
doc) lands in later specs.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                           |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Scope:** Tenant drop only. `GoogleIdentity` rename is a Phase 9 spec.                                                                                                            |
| Q2  | **Storage paths:** Flatten. Drop `tenant-{id}/` prefix everywhere. New shape: `composites/`, `exports/`, `thumbnails/`, `footage/`, `projects/<project_id>/` for notes.            |
| Q3  | **User model shape:** Thin auth-only. Columns: `id`, `email` (citext, unique, NOT NULL), `password_digest`, `created_at`, `updated_at`. No `tenant_id`. No `username`. No `admin`. |
| Q4  | **Seed shape:** `db/seeds.rb` reads `Rails.application.credentials.owner.{email, password}`. No `tenant_name`, no `tenant_slug`, no `username`. Seeds one User. No Tenant.         |
| Q5  | **Schema expansion:** Out of scope. Domain tables shed `tenant_id` only; further per-domain expansion lives in later work-unit specs.                                              |
| Q6  | **Login identifier:** **Email only.** No username path remains. No "email or username" copy. Form field labeled `email`.                                                           |

## Migration posture (LOCKED)

**Destructive-and-reseed.** Per ADR 0003 "Migration posture":

- No production data exists; pito has not shipped to anyone outside the
  developer's machine.
- The migration drops columns, drops tables, drops the concern, drops
  `Current.tenant`, drops the `username` column, drops the storage prefix, and
  reseeds via `db:seed` to reach the new shape.
- ADR 0003 + git history are the only artifacts of the prior shape. No backfill.
  No data preservation.
- **Rollback is explicitly NOT supported.** A `down` method is permitted for
  Rails' migration bookkeeping but it does not have to restore prior data;
  document that in the migration body. `rails db:rollback` of this migration is
  out of scope for testing.

## Files touched

### Schema / migration

- `db/migrate/<NN>_drop_tenant_and_username.rb` (new) — single migration named
  per Rails 8.1 convention (`<YYYYMMDDHHMMSS>_drop_tenant_and_username.rb`).
  Scope:
  - Drop foreign-key constraint and `tenant_id` column from each of:
    `api_tokens`, `bulk_operation_items`, `bulk_operations`, `channels`,
    `collections`, `footages`, `games`, `google_identities`, `notes`,
    `oauth_access_grants`, `oauth_access_tokens`, `oauth_applications`,
    `playlist_items`, `playlists`, `project_references`, `projects`,
    `saved_views`, `sessions`, `timelines`, `users`, `video_stats`,
    `video_uploads`, `videos`, `youtube_api_calls`.
  - Drop every index on `tenant_id` (single-column AND composite). Indexes that
    lose their first column become useless; replace ONLY where the spec calls
    for it (see "Index replacements" below).
  - Drop `username` column from `users` (and the `index_users_on_username`
    unique index). The `index_users_on_email` unique index stays.
  - Drop the `tenants` table (after every FK to it has been dropped).
- `db/schema.rb` — auto-regenerated; verify no `tenant_id` columns remain and no
  `tenants` table remains.

#### Index replacements (the ones worth keeping after the prefix is gone)

The current schema has composite indexes that survive a column drop only if
their first column is something other than `tenant_id`. Otherwise drop the
index. Specifically:

- `channels`: drop `index_channels_on_tenant_id_and_oauth_identity_id` and
  `index_channels_on_tenant_id_and_star`. Keep
  `index_channels_on_oauth_identity_id` (already exists). Add a partial index on
  `(star)` only if the implementation agent finds query callsites that filter by
  `star = true` without other predicates.
- `collections`: drop `index_collections_on_tenant_id_and_name`. Add
  `index_collections_on_name` (no uniqueness — name can repeat install- wide;
  the prior uniqueness was per-tenant, which collapses).
- `footages`: drop `index_footages_on_tenant_id_and_local_path`. Replace with
  `index_footages_on_local_path` UNIQUE (filenames are now globally unique —
  confirm in the manual playbook).
- `games`: drop `index_games_on_tenant_id_and_title`. Add `index_games_on_title`
  (no uniqueness).
- `google_identities`: drop the four tenant-prefixed indexes. Replace the unique
  `(tenant_id, google_subject_id)` with a unique index on `(google_subject_id)`
  alone — Google subject IDs are globally unique identifiers, so the
  install-wide uniqueness is correct. Keep `index_google_identities_on_user_id`.
- `notes`: drop `index_notes_on_tenant_id_and_path`. Replace with a unique index
  on `(project_id, path)` — note paths must be unique per project, not per
  tenant. Confirm this matches the Phase 4 design intent (it does —
  `NotesFilesystem.root_for(note)` keys on project, not tenant; the `tenant_id/`
  segment was an isolation prefix not a uniqueness requirement).
- `projects`: drop `index_projects_on_tenant_id_and_name`. Add
  `index_projects_on_name` (no uniqueness — same reasoning as collections).
- `saved_views`: keep the existing `(kind, url)` unique index (it does not
  include `tenant_id`).
- `youtube_api_calls`: drop the three tenant-prefixed composite indexes. Replace
  with non-tenant equivalents on `(client_kind, created_at)`,
  `(google_identity_id, created_at)`, and `(outcome, created_at)` — preserves
  the analytics query shapes.
- `videos`: drop `index_videos_on_tenant_channel_youtube_id` and
  `index_videos_on_tenant_id_and_star`. Keep `index_videos_on_youtube_video_id`
  (already unique). Keep `index_videos_on_channel_id`. Add no replacement for
  `(tenant_id, star)` — stars are rare, sequential scan is fine until the
  install grows past a threshold worth indexing.

The implementation agent owns the final index list and may flag any additions
that surface during the sweep.

### Models (delete / edit)

- **Delete:** `app/models/tenant.rb`.
- **Delete:** `app/models/concerns/belongs_to_tenant.rb`.
- **Edit:** `app/models/current.rb` — remove `:tenant`, the `tenant_id` reader,
  and the comment block referencing `BelongsToTenant`. Final attribute list:
  `:user, :token, :session`.
- **Edit:** `app/models/user.rb` — drop `belongs_to :tenant`; drop the
  `username` validation block (`USERNAME_REGEX`, format / uniqueness); drop the
  `find_by_username_or_email` class method. Keep `has_secure_password`,
  `has_many :sessions`, password length validation, email presence + format +
  case-insensitive uniqueness.
- **Edit:** `app/models/session.rb` — remove `include BelongsToTenant`; drop
  `tenant: user.tenant` from `Session.create_for!`; remove the
  `unscoped.create!` workaround (no default scope to bypass anymore; plain
  `create!` is fine). Update the doc comment.
- **Edit:** `app/models/api_token.rb` — drop `belongs_to :tenant`; drop
  `tenant:` keyword from `generate!` (signature becomes
  `generate!(user:, name:, scopes:, expires_at: nil)`); update doc comment.
- **Edit:** `app/models/google_identity.rb` — drop `include BelongsToTenant`;
  drop the `uniqueness: { scope: :tenant_id }` constraint on `google_subject_id`
  (replace with global uniqueness, see schema section).
- **Edit:** `app/models/oauth_application.rb` — drop `belongs_to :tenant` and
  the `tenant_id` presence validation. Remove the explanatory comment about
  Doorkeeper bypassing `BelongsToTenant`.
- **Edit:** `app/models/oauth_access_token.rb` — drop `belongs_to :tenant`, the
  `before_validation :denormalize_tenant_from_application` callback, and the
  comment block referencing `BelongsToTenant`. Keep the `user` reader
  (resource-owner resolution).
- **Edit:** `app/models/oauth_access_grant.rb` — drop `belongs_to :tenant` and
  the `denormalize_tenant_from_application` callback.
- **Edit:** `app/models/footage.rb` — drop `include BelongsToTenant`; drop
  `before_validation :denormalize_tenant_from_project`; drop
  `MissingProjectError`; tighten
  `validates :local_path, uniqueness: { scope: :tenant_id }` to plain
  `uniqueness: true` (matches the new index).
- **Edit:** every other model that includes `BelongsToTenant` — remove the
  include and any `belongs_to :tenant` line. The implementation agent enumerates
  from the `git grep -l 'BelongsToTenant' app/models/` output. At minimum:
  `app/models/channel.rb`, `app/models/video.rb`, `app/models/video_stat.rb`,
  `app/models/video_upload.rb`, `app/models/playlist.rb`,
  `app/models/playlist_item.rb`, `app/models/project.rb`,
  `app/models/project_reference.rb`, `app/models/collection.rb`,
  `app/models/game.rb`, `app/models/note.rb`, `app/models/saved_view.rb`,
  `app/models/timeline.rb`, `app/models/youtube_api_call.rb`,
  `app/models/bulk_operation.rb`, `app/models/bulk_operation_item.rb`. Remove
  any tenant-scoped scopes that exist on these models (the implementation agent
  surfaces them during the sweep).

### Controllers

- **Edit:** `app/controllers/application_controller.rb` — no behavioural change
  required; the `Sessions::AuthConcern` no longer pins `Current.tenant` (see
  below). Update any comment referencing tenant pinning.
- **Edit:** `app/controllers/concerns/sessions/auth_concern.rb` — drop
  `Current.tenant = result.session.tenant` from the success branch.
- **Edit:** `app/controllers/concerns/api/auth_concern.rb` — drop
  `tenant = token.tenant`, drop `Current.tenant = tenant`, drop the
  defense-in-depth check `user.tenant_id != tenant&.id`. Replace with a simpler
  `user.nil?` check (still raise `Api::Unauthorized` with `invalid_token`
  reason).
- **Edit:** `app/controllers/sessions_controller.rb`:
  - Replace `params[:identifier]` with `params[:email]` everywhere.
  - Drop `User.unscoped.find_by_username_or_email(identifier)`; replace with
    `User.find_by(email: email_param)` (no `unscoped` needed — no default scope
    anymore).
  - Update the `audit` payload keys: `identifier_attempted` becomes
    `email_attempted`.
  - Rename the `@identifier` ivar to `@email`.
  - Update the flash message text per the copy questions section (architect
    calls out the touchpoint; user picks the wording).
- **Edit:** `app/controllers/sessions/auth_concern.rb` — already covered above;
  no second edit pass needed.
- **Sweep:** every controller for `Current.tenant` references; remove. Common
  sites the implementation agent will hit: any controller that scopes a query
  (e.g., `Channel.where(tenant_id: Current.tenant_id)` becomes `Channel.all`).
- **Sweep:** every controller for `current_user.tenant` / `Current.user.tenant`
  references; remove.
- **Sweep:** `app/controllers/settings/oauth_applications_controller.rb` (or
  equivalent) — drop the `where(tenant_id: Current.tenant_id)` filter on the
  index action; the surface lists every application install-wide.

### Views

- **Edit:** `app/views/sessions/new.html.erb`:
  - Replace `<label for="login_identifier">email or username</label>` with an
    email-only label (copy question — see below).
  - Rename input `name="identifier"` to `name="email"`, `id="login_identifier"`
    to `id="login_email"`, `value="<%= @identifier %>"` to
    `value="<%= @email %>"`.
  - Update `autocomplete="username"` to `autocomplete="email"`.
  - Update the `type="text"` to `type="email"` (browser-side validation
    - correct mobile keyboard).
  - Update the helper paragraph at the top — it currently mentions "your pito
    account"; copy stays unless the user requests a change.
- **Sweep:** every other view for `username` / "email or username" / `tenant`
  references. The implementation agent enumerates via
  `git grep -i 'username\|or email\|tenant' app/views/`. Likely no remaining
  sites outside of `sessions/new.html.erb` and possibly a Settings header
  showing `Current.user.username`; update those to `Current.user.email` (or keep
  as initials if the design uses an avatar fallback — implementation agent's
  call, document in log.md).

### MCP layer

- **Edit:** `app/mcp/rack_app.rb`:
  - Drop `tenant = token.tenant` and `Current.tenant = tenant`.
  - Drop the defense-in-depth check `user.tenant_id != tenant&.id`.
  - Keep the `user.nil?` failure path (treat as `invalid_token`).
- **Sweep:** `app/mcp/tools/*.rb` — drop any `Current.tenant` references inside
  individual tools. The `save_note` tool already operates on
  `Rails.root.join("docs/notes")` and does not reference tenant; verify every
  tool follows that pattern.
- **Sweep:** `app/mcp/resources/*.rb` — same sweep.
- **Sweep:** `app/mcp/tool_auth.rb` — `require_scope!` already operates on
  `Current.token`; no tenant ref expected.

### Doorkeeper

- **Edit:** `config/initializers/doorkeeper.rb`:
  - Drop `Current.tenant = auth_result.session.tenant` from the
    `resource_owner_authenticator` block.
  - Drop `Current.tenant = auth_result.session.tenant` from the
    `admin_authenticator` block.
  - Update the comment header "Custom tenant-aware models — required for
    `BelongsToTenant` to apply" to reflect the new framing (`OauthApplication`
    is a thin Doorkeeper subclass with no extra scoping).

### Storage paths

- **Edit:** `app/lib/notes_filesystem.rb`:
  - `root_for(note)`: drop the `note.tenant_id.to_s` segment. New shape:
    `<PITO_NOTES_PATH>/projects/<project_id>/<file>.md`.
  - `project_dir(project)`: drop the `project.tenant_id.to_s` segment. New
    shape: `<PITO_NOTES_PATH>/projects/<project_id>/`.
  - Update doc comment header (lines 1-13) to reflect the flat layout.
- **Edit:** `app/lib/pito/assets_root.rb`:
  - Delete the `tenant_root(tenant)` method outright (callers go away).
  - Update the doc comment block (the "tenant-scoped consumers" line becomes
    "future per-install asset trees use `path(...)` directly").
- **Sweep:** any service / job that previously called
  `Pito::AssetsRoot.tenant_root(...)` — replace with direct
  `Pito::AssetsRoot.path(...)` or a domain-specific top-level segment (e.g.,
  `Pito::AssetsRoot.path("composites")`,
  `Pito::AssetsRoot.path("thumbnails", footage.id.to_s, ...)`,
  `Pito::AssetsRoot.path("exports")`, `Pito::AssetsRoot.path("footage")`). The
  implementation agent enumerates via
  `git grep -l 'tenant_root\|tenant-{\|tenant-#' app/ lib/`.
- **Edit:** `config/storage.yml` — no change required; the `local` service root
  already points at `PITO_ASSETS_PATH`. The flat layout is achieved by the
  application code, not the storage backend.
- **Sweep:** any composite-cover or export builder that hard-codes
  `tenant-#{tenant.id}/` in a path-build expression. Replace with the flat
  top-level folder (`composites/`, `exports/`, `thumbnails/`, `footage/`).

### Seed

- **Edit:** `db/seeds.rb`:
  - Remove the entire `tenant = Tenant.find_or_initialize_by(...)` block and the
    `Current.tenant = tenant` pin.
  - Remove `tenant_name`, `tenant_slug`, and `owner_username` derivations. New
    owner derivation: `owner_email = owner_creds&.dig(:email)` and
    `owner_password = owner_creds&.dig(:password)`.
  - User seeding: `User.find_or_initialize_by(email: owner_email)`; drop the
    `username` lookup branch and the `owner.username = ...` line; drop
    `owner.tenant = tenant`.
  - ApiToken seed: drop `tenant: tenant` from `ApiToken.generate!(...)`; drop
    the `tenant_id: tenant.id` predicate from
    `ApiToken.exists?(name: "dev", ...)`.
  - Channel / Video / VideoStat seed: drop every `ch.tenant = tenant`,
    `video.tenant = tenant`, `stat.tenant = tenant` line.
  - Project / Collection / Game / ProjectReference / Note / Timeline seed: drop
    every `tenant: tenant` keyword.
  - Update the warning copy about a missing `:owner` block — should describe the
    new shape (`email`, `password`).
- The dev token banner output stays. The `voyage_api_key` AppSetting bootstrap
  stays.

### Credentials

- The architect cannot edit `config/credentials.yml.enc`. The user runs
  `bin/rails credentials:edit --environment development` and
  `--environment test` after the implementation lands.
- New `:owner` block shape (per Q4):
  ```yaml
  owner:
    email: <your-email>
    password: <your-password>
  ```
- The user-required step is called out in the manual playbook section below.

### Documentation (post-implementation; dispatched separately to docs-keeper)

The Rails implementation does NOT touch these files. After the rails-impl
dispatch lands and the user validates, the master agent dispatches
`pito-docs-keeper` against this list:

- `docs/architecture.md` — drop the Tenant section; rewrite "Tenant + User +
  ApiToken" → "User + ApiToken"; drop the IDOR and BelongsToTenant mentions;
  replace with a "Single-install, multi-user" paragraph pointing at ADR 0003.
- `docs/auth.md` — drop tenant references (§5 BelongsToTenant section, §10
  single-tenant simplification rationale); switch login description to
  email-only.
- `docs/setup.md` — update the `:owner` credentials block shape (lines 86-118
  today); drop the tenant set-up paragraphs; update the worked example to match
  `{ email, password }`. Drop the line "creates 1 Tenant
  - 1 User from the `:owner` credentials block, ..." in §5; replace with
    "creates 1 User from the `:owner` credentials block, ...".
- `docs/mcp.md` — drop any tenant-scoping language; update the auth preamble.
- `CLAUDE.md` — update the "Architecture notes" section (currently states
  "`Tenant` and `User` exist as seeded singletons at the schema level only — no
  signup, no login..."); drop the Tenant references and clarify User as
  auth-only.

These edits are listed here for traceability; they are NOT part of the
rails-impl dispatch's file scope.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows no `tenants` table.
- [ ] `db/schema.rb` shows no `tenant_id` column on any `create_table`.
- [ ] `db/schema.rb` shows no `username` column on `users`.
- [ ] `db/schema.rb` shows no `index_users_on_username`.
- [ ] `db/schema.rb` shows no foreign-key constraint pointing to `tenants`.
- [ ] `db/schema.rb` `create_table "users"` lists exactly:
      `email, password_digest, created_at, updated_at` (plus `id`).
- [ ] The migration's `up` runs cleanly on a freshly-loaded schema:
      `bin/rails db:drop db:create db:migrate` succeeds.

### Models / Concerns / Current

- [ ] `app/models/tenant.rb` does not exist.
- [ ] `app/models/concerns/belongs_to_tenant.rb` does not exist.
- [ ] `app/models/current.rb` declares `attribute :user, :token,     :session`
      only.
- [ ] `git grep 'BelongsToTenant' app/` returns zero matches.
- [ ] `git grep 'belongs_to :tenant' app/` returns zero matches.
- [ ] `git grep 'Current.tenant' app/` returns zero matches.
- [ ] `app/models/user.rb` does not validate `username`, does not define
      `find_by_username_or_email`, does not call `belongs_to :tenant`.
- [ ] `app/models/session.rb` does not include `BelongsToTenant`;
      `Session.create_for!` signature has no `tenant:` keyword.
- [ ] `app/models/api_token.rb` `generate!` signature has no `tenant:` keyword.
- [ ] `app/models/google_identity.rb` does not include `BelongsToTenant` and
      validates `google_subject_id` with global uniqueness.

### Controllers / Auth

- [ ] `Sessions::AuthConcern` does not set `Current.tenant`.
- [ ] `Api::AuthConcern` does not set `Current.tenant` and does not perform the
      cross-tenant defense-in-depth check.
- [ ] `SessionsController#create` reads `params[:email]`, looks up the user via
      `User.find_by(email: ...)`, and authenticates.
- [ ] `app/views/sessions/new.html.erb` has no "or username" copy and no
      `name="identifier"` field.

### MCP / Doorkeeper

- [ ] `Mcp::RackApp#call` does not set `Current.tenant` and does not perform the
      cross-tenant check.
- [ ] `git grep 'tenant' app/mcp/` returns zero matches.
- [ ] `config/initializers/doorkeeper.rb` does not set `Current.tenant`.
- [ ] OAuth flow (`/oauth/authorize` → `/oauth/token`) succeeds in a manual
      smoke against `bin/dev`.

### Storage

- [ ] `app/lib/notes_filesystem.rb`'s `root_for(note)` returns
      `<PITO_NOTES_PATH>/projects/<project_id>` (no tenant segment).
- [ ] `app/lib/pito/assets_root.rb` does not define `tenant_root`.
- [ ] `git grep 'tenant_root\|tenant-{\|tenant-#' app/ lib/` returns zero
      matches.
- [ ] After reseed, on-disk note files land at
      `<PITO_NOTES_PATH>/projects/<id>/<file>.md`.

### Seed / Credentials

- [ ] `db/seeds.rb` does not reference `Tenant`.
- [ ] `db/seeds.rb` does not reference `username`.
- [ ] `db/seeds.rb` reads `Rails.application.credentials.owner.email` and
      `.password` only.
- [ ] `bin/rails db:seed` completes idempotently when run twice in a row.
- [ ] After `db:seed`, exactly one User row exists with the seeded email;
      `User.first.authenticate(<seeded password>)` returns the user.

### Tests

- [ ] `bundle exec rspec` passes (count adjusts down by the IDOR / tenant-spec
      deletions; the implementation agent reports the delta).
- [ ] No spec references `Tenant`, `tenant_id`, `Current.tenant`,
      `BelongsToTenant`, or `find_by_username_or_email`. Verified via
      `git grep`.
- [ ] New test cases enumerated in the "Tests" section below all pass.

## Test sweep

The implementation agent owns the full sweep. The enumeration below is
exhaustive; any spec the agent touches must end in one of the three buckets
(delete / update / add).

### Specs to delete outright

| Path                                                     | Reason                                                                |
| -------------------------------------------------------- | --------------------------------------------------------------------- |
| `spec/factories/tenants.rb`                              | Tenant factory; the model is gone.                                    |
| `spec/models/tenant_spec.rb`                             | Tenant model spec.                                                    |
| `spec/models/concerns/belongs_to_tenant_spec.rb`         | The concern is gone (verify path; may be elsewhere — agent confirms). |
| Every `*_idor_spec.rb`                                   | The 12-rule IDOR coverage is archived per ADR 0003.                   |
| Every in-file `describe "IDOR"` / `context "IDOR"` block | Same reason — agent enumerates via `git grep -n 'IDOR' spec/`.        |
| `spec/requests/cross_tenant_*` (if any)                  | Cross-tenant request tests retire with the tenant model.              |

### Specs to update

The agent enumerates the full set via
`git grep -l 'Tenant\|tenant_id\|Current\.tenant\|BelongsToTenant\|username' spec/`.
Expected sites (non-exhaustive):

| Path                                      | Edit                                                                                                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/factories/users.rb`                 | Drop `tenant`, drop `username`. Final factory: email + password.                                                                                  |
| `spec/factories/channels.rb`              | Drop `tenant`.                                                                                                                                    |
| `spec/factories/videos.rb`                | Drop `tenant`.                                                                                                                                    |
| `spec/factories/video_stats.rb`           | Drop `tenant`.                                                                                                                                    |
| `spec/factories/projects.rb`              | Drop `tenant`.                                                                                                                                    |
| `spec/factories/collections.rb`           | Drop `tenant`.                                                                                                                                    |
| `spec/factories/games.rb`                 | Drop `tenant`.                                                                                                                                    |
| `spec/factories/footages.rb`              | Drop `tenant` (was inferred via `before_validation`; now plain).                                                                                  |
| `spec/factories/notes.rb`                 | Drop `tenant`.                                                                                                                                    |
| `spec/factories/timelines.rb`             | Drop `tenant`.                                                                                                                                    |
| `spec/factories/saved_views.rb`           | Drop `tenant`.                                                                                                                                    |
| `spec/factories/api_tokens.rb`            | Drop `tenant:` keyword from any `generate!` call sites used by traits.                                                                            |
| `spec/factories/sessions.rb`              | Drop `tenant:` keyword.                                                                                                                           |
| `spec/factories/google_identities.rb`     | Drop `tenant`.                                                                                                                                    |
| `spec/factories/oauth_applications.rb`    | Drop `tenant`.                                                                                                                                    |
| `spec/factories/bulk_operations.rb`       | Drop `tenant`.                                                                                                                                    |
| `spec/factories/bulk_operation_items.rb`  | Drop `tenant`.                                                                                                                                    |
| `spec/factories/youtube_api_calls.rb`     | Drop `tenant`.                                                                                                                                    |
| `spec/factories/playlists.rb`             | Drop `tenant`.                                                                                                                                    |
| `spec/factories/playlist_items.rb`        | Drop `tenant`.                                                                                                                                    |
| `spec/factories/project_references.rb`    | Drop `tenant`.                                                                                                                                    |
| `spec/factories/video_uploads.rb`         | Drop `tenant`.                                                                                                                                    |
| `spec/models/user_spec.rb`                | Drop username validation tests; drop `find_by_username_or_email` block; drop tenant association block. Replace per the "New tests" section below. |
| `spec/models/session_spec.rb`             | Drop tenant pinning assertions; update `Session.create_for!` signature expectation.                                                               |
| `spec/models/api_token_spec.rb`           | Drop tenant association; update `generate!` signature.                                                                                            |
| `spec/models/google_identity_spec.rb`     | Drop tenant association tests; update `google_subject_id` uniqueness assertion to global.                                                         |
| `spec/models/oauth_application_spec.rb`   | Drop tenant tests.                                                                                                                                |
| `spec/models/oauth_access_token_spec.rb`  | Drop tenant denormalization tests.                                                                                                                |
| `spec/models/oauth_access_grant_spec.rb`  | Drop tenant denormalization tests.                                                                                                                |
| Every other `spec/models/*_spec.rb`       | Drop `it { is_expected.to belong_to(:tenant) }` lines; drop tenant set-up; rewrite scope tests.                                                   |
| Every `spec/requests/*_spec.rb`           | Drop tenant context; remove `Current.tenant=` set-ups; rewrite IDOR-style tests as auth-required tests.                                           |
| Every `spec/system/*_spec.rb`             | Drop tenant context.                                                                                                                              |
| `spec/requests/sessions_spec.rb`          | Rewrite for email-only login. Drop username path coverage.                                                                                        |
| `spec/requests/api/**/*_spec.rb`          | Drop tenant set-up; drop the cross-tenant defense-in-depth assertions on bearer-token tests.                                                      |
| `spec/requests/mcp/*_spec.rb` (if exists) | Drop tenant set-up.                                                                                                                               |
| `spec/lib/notes_filesystem_spec.rb`       | Update path expectations to flat shape; drop tenant_id from arguments.                                                                            |
| `spec/lib/pito/assets_root_spec.rb`       | Drop the `tenant_root` example block outright.                                                                                                    |
| `spec/jobs/*_spec.rb`                     | Drop tenant set-ups in shared contexts.                                                                                                           |
| `spec/services/**/*_spec.rb`              | Drop tenant set-ups; rewrite path expectations for flat layout where applicable.                                                                  |

### New tests to add (exhaustive coverage mandate)

The implementation agent writes these. Each is named explicitly so the reviewer
can check existence + behavior without guesswork.

#### `spec/models/user_spec.rb` (new top of the file replaces the old one)

- **Email validation:**
  - `it "is invalid with a blank email"` — empty / whitespace-only / nil.
  - `it "is invalid with a malformed email"` — no `@`, missing host, etc.
  - `it "rejects emails longer than 254 characters"` (boundary). The
    implementation agent picks the right `length` validation and the constant;
    spec asserts the boundary.
  - `it "is case-insensitive on email uniqueness via citext"` — create
    `USER@example.com`; build `user@example.com`; assert `not be_valid`.
  - `it "accepts a valid email"`.
  - `it "treats whitespace at the boundaries"` — assert the rule (the
    implementation agent picks: strip on save vs. reject; spec encodes that
    choice). Recommendation: **strip surrounding whitespace** on write (matches
    the SessionsController behavior on the identifier today).
- **`has_secure_password`:**
  - `it "round-trips a valid password"` — `authenticate("right")` ⇒ user;
    `authenticate("wrong")` ⇒ false.
  - `it "rejects empty passwords on authenticate"` — `authenticate("")` ⇒ false.
  - `it "rejects passwords shorter than 8 characters"`.
  - `it "accepts passwords of exactly 8 characters"`.
  - `it "does not re-validate password length on a row whose password is untouched"`
    — preserved from the existing spec.

#### `spec/requests/sessions_spec.rb` (rewrite; new test list)

- **GET /login (happy):** form renders 200, contains `name="email"` and
  `name="password"`, contains no `name="identifier"`.
- **POST /login with valid email + valid password (happy):** redirects to
  `root_path` (or the intended URL); `Set-Cookie` includes `pito_session`; flash
  notice present.
- **POST /login with valid email + wrong password (sad):** renders `:new` with
  status `:unprocessable_content`; flash alert text matches the agreed copy; no
  `pito_session` cookie set.
- **POST /login with malformed email (edge / sad):** form re-renders with the
  same error message as wrong-password (timing-attack resistance: the
  user-visible message MUST NOT distinguish "no such email" from "wrong
  password").
- **POST /login with blank email (edge):** form re-renders with the generic
  invalid message.
- **POST /login with non-existent email (sad):** form re-renders with the same
  generic message; the constant-time `bcrypt_dummy_compare` still runs.
- **POST /login with extra params (flaw test):** smuggle a stray `tenant_id`,
  `username`, or `admin` param; assert it has no effect on the response or the
  session record.
- **DELETE /session (happy):** logs out; cookie cleared; redirects to `/login`
  with notice.
- **Authenticated request to a protected route:** 200.
- **Unauthenticated request to a protected route:** redirects to `/login`;
  intended URL stashed.
- **Rate-limit:** N consecutive failures throttle subsequent attempts per the
  existing throttle behavior. (Preserve the existing `SessionThrottle` coverage;
  only update to email-keyed.)

#### `spec/requests/mcp/auth_spec.rb` (or equivalent — name per existing convention)

- **Authenticated MCP call (happy):** Bearer token resolves; `Current.user` is
  set; tool runs.
- **Unauthenticated MCP call (sad):** 401 with the standard envelope and
  `WWW-Authenticate` header.
- **MCP call with revoked token (sad):** 401 `revoked_token`.
- **MCP call with expired token (sad):** 401 `expired_token`.
- **Rack-app drops tenant context:** assert that during a successful request the
  rack app does NOT call `Current.tenant=` (introspect via a spy / test-only
  hook the implementation agent designs, OR simply assert via `Current.tenant`
  being nil after the request).
- **MCP call with stray `tenant_id` smuggled in the JSON-RPC params (flaw
  test):** the param is ignored; the call succeeds against the install scope
  with no observable difference.
- **`save_note` writes to `docs/notes/`:** path matches
  `<repo>/docs/notes/<YYYY-MM-DD-HH-MM-SS>-<slug>.md`. (Already covered by the
  existing tool spec; verify it still passes after the sweep.)
- **`list_docs` returns docs without tenant filtering:** preserved test; verify
  it still passes.

#### `spec/requests/api/auth_spec.rb`

- **Bearer auth: ApiToken (happy):** `Current.user` set; no `Current.tenant`.
- **Bearer auth: Doorkeeper OauthAccessToken (happy):** same; the
  `defense-in-depth` cross-tenant check is gone — assert that a token whose
  resource owner exists succeeds without any tenant check.
- **Bearer auth: invalid token (sad):** 401.
- **Bearer auth: revoked / expired (sad):** 401 with correct reason.

#### `spec/lib/notes_filesystem_spec.rb`

- **`root_for(note)`:** returns `<PITO_NOTES_PATH>/projects/<project_id>`
  exactly (no tenant segment).
- **`project_dir(project)`:** same shape.
- **`write` round-trip:** writes `body`; reads it back; absolute path matches
  the flat layout.
- **`delete_project_dir`:** removes the directory; second invocation is a no-op.

#### `spec/lib/pito/assets_root_spec.rb`

- Replace the existing `tenant_root` examples with examples for the new
  domain-specific top-level segments. At minimum: `path("composites")`,
  `path("thumbnails", "1", "frame.jpg")`, `path("exports")`, `path("footage")`
  all resolve under the assets root and reject `..` traversal.

#### `spec/db/seeds_spec.rb` (new — reseed integration)

- **Happy:** with the `:owner` credentials block populated, run
  `Rails.application.load_seed`; assert exactly one User row exists with the
  seeded email; assert `User.first.authenticate(<seeded password>)` returns the
  user.
- **Idempotency:** run the seed twice; assert `User.count == 1` and the row was
  not duplicated; the dev-token path (which prints a banner) is a no-op on the
  second run because `ApiToken.exists?(name: "dev")` is true.
- **Sad — malformed `:owner`:** stub credentials to return a block missing
  `email`; expect a clear failure (the warning printed by the current seed
  becomes a stronger signal — implementation agent picks the failure shape; spec
  encodes it).

#### `spec/services/storage_paths_spec.rb` (new — round-trip integration)

The implementation agent picks the host file for these tests; the content is
what matters:

- **Composite cover round-trip:** write a composite cover (or stub it); assert
  the on-disk path shape matches `composites/<filename>` (no `tenant-X/`
  prefix).
- **Thumbnail round-trip:** assert `thumbnails/<footage-id>/<frame>.jpg`.
- **Export round-trip:** assert `exports/<filename>`.
- **Legacy tenant path read returns not-found:** assert that a request for an
  old-style `tenant-1/composites/foo.png` URL routes to not-found / 404. No
  fallback.

#### `spec/models/oauth_access_token_spec.rb` updates

- Drop the `denormalize_tenant_from_application` examples.
- Add: `it "resolves resource_owner_id to a User"` (preserved behavior).

## Manual playbook (post-implementation)

Architect outlines; reviewer fills in remaining steps after spec lands.

1. **Update credentials (user-required step).** Run
   `bin/rails credentials:edit --environment development`. Replace the existing
   `:owner` block with:
   ```yaml
   owner:
     email: <your-email>
     password: <your-password>
   ```
   Repeat for `--environment test`.
2. **Drop and recreate the database.**
   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```
   Confirm the seed output prints "user: <email> (id=...)" and prints the
   dev-token banner once.
3. **Visit `/login`.** Confirm the form has a single "email" field (not "email
   or username"). Submit valid email + password. Confirm redirect to `/` with
   the signed-in flash.
4. **Try malformed inputs.** Logout. Submit empty email; submit malformed email;
   submit valid email with wrong password. Each path re-renders the form with
   the agreed generic message.
5. **MCP from Claude Mobile.** Re-pair the MCP connection (Doorkeeper token
   rotation per ADR 0004 is a separate phase, but if any tokens were tied to the
   prior `User` shape, re-issue via `/settings/oauth_applications`). Confirm
   `dev:save_note` lands a file under `docs/notes/`.
6. **Storage paths flat.** Open a previously-uploaded composite cover (game
   cover art via `bin/dev`) and confirm it loads. Confirm the on-disk file is at
   `<PITO_ASSETS_PATH>/active_storage/...` (Active Storage's own layout) — no
   `tenant-X/` segment. For notes, confirm the file is at
   `<PITO_NOTES_PATH>/projects/<project_id>/<file>.md` (no tenant segment).
7. **Run the full RSpec suite.**
   ```bash
   bundle exec rspec
   ```
   Confirm green. Note the spec count delta in `log.md`.
8. **Verify Sidekiq web `/sidekiq`.** HTTP basic auth still works; the surface
   is unchanged by the tenant drop.
9. **Verify Doorkeeper.** Visit `/settings/oauth_applications`; confirm the list
   renders without a tenant filter. Create a test application and run a full
   OAuth dance via curl or via a re-paired MCP client.
10. **Reviewer fills in:** any further smoke steps surfaced during the review
    pass.

## Cross-stack scope

| Surface           | Status                                                                                                                                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                                                                                                 |
| MCP rack app      | **In scope.** Drops tenant pinning. Same lane.                                                                                                                                                              |
| Doorkeeper        | **In scope.** Drops tenant denormalization + the resource-owner-authenticator tenant pin. Same lane.                                                                                                        |
| `pito` CLI (Rust) | **Skipped.** No tenant references in the CLI today; the API surface it consumes drops the tenant boundary at the server side. CLI parity sweeps separately if any client-side reference shows up post-impl. |
| Astro / website   | **Skipped.** N/A here.                                                                                                                                                                                      |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Login form label.** The existing label reads `email or username`. The new
   field is email-only. Suggested options:
   - `email` (matches the existing minimal style)
   - `email address`
   - `your email`
2. **Login form placeholder.** No placeholder today. Decide whether to add one
   (e.g., `you@example.com`) or leave the field blank.
3. **Login form helper text** at the top of `app/views/sessions/new.html.erb`.
   Current:
   `sign in with your pito account. forgot your password? recovery is not yet available — reset via bin/rails credentials:edit for now.`
   Confirm whether this stays as-is or shifts.
4. **Generic invalid-credentials error.** Today: `invalid email or password.`
   Should this become `invalid email or password.` (no change) or something
   tighter (e.g., `invalid credentials.`)? The security best practice is to NOT
   distinguish "no such email" from "wrong password"; the current copy already
   follows that rule.
5. **Audit-log event keys.** The existing audit calls log
   `identifier_attempted: identifier`. Renaming to `email_attempted` is the
   obvious symmetry; user confirms or picks alternative.
6. **`docs/setup.md` `:owner` block prose.** The lines that explain the block
   (currently around lines 86-117 of `setup.md`) need to describe the new
   `{ email, password }` shape and drop the tenant set-up paragraph. The
   architect calls out the file + section; user reviews the docs-keeper draft
   when that dispatch lands.
7. **Sessions / logout flash messages.** Current: `signed in.` / `signed out.` /
   `please log in.` These are tenant-agnostic already; confirm no change.
8. **MCP tool descriptions.** Audit `app/mcp/tools/*.rb` for any description
   string referencing "tenant" or "your tenant's data". The existing `save_note`
   description does not. The implementation agent reports any hit; user picks
   new copy.
9. **Settings page header.** If the current header renders
   `Current.user.username`, the new render is `Current.user.email` (or the
   email's local part). User picks.
10. **Error messages that previously said "no such tenant" or similar.**
    Implementation agent enumerates; user reviews.

## Open questions (architect cannot decide; master agent surfaces to

user)

1. **Does any service reference a hard-coded `tenant-#{tenant.id}/` path string
   that the implementation agent should treat as "delete the directory on a
   fresh dev machine"?** ADR 0003's "destructive-and- reseed" posture covers
   data loss; this question is about whether the implementation agent ships a
   one-shot `bin/rake pito:flatten_storage` task to clean the on-disk layout for
   developers who already have a populated `<PITO_ASSETS_PATH>` /
   `<PITO_NOTES_PATH>`. Recommendation: **no rake task; document the manual step
   ("rm -rf <PITO*NOTES_PATH>/* <PITO*ASSETS_PATH>/*; rerun db:seed") in the
   manual playbook**. The user has only one machine; a one-shot task is
   over-engineered.
2. **Does the existing `index_users_on_email` need any rework?** The index
   already exists and is unique; per Q3 the column stays citext. Recommendation:
   **no rework**; verify the index survives the migration as-is.
3. **The seed currently mints a default `dev` ApiToken with scopes
   `[DEV_READ, DEV_WRITE, YT_READ, YT_WRITE, PROJECT_READ, PROJECT_WRITE]`.**
   ADR 0004 (MCP scope simplification) collapses the catalog to `dev` + `app`
   later. Should this Phase 8 spec (a) keep the existing scope list and let
   Phase 9 / the scope-simplification dispatch rotate it, or (b) collapse the
   seed scopes to `dev` + `app` now? Recommendation: **(a) — keep existing
   scopes**; scope simplification is a separate dispatch and folding it in here
   violates Q1 ("Tenant drop only").

## Non-goals (explicit)

- **`GoogleIdentity` rename.** Phase 9 spec.
- **Channel / Video schema expansion.** Realignment work unit 4.
- **MCP scope simplification (9 → 2 scopes).** Per ADR 0004; separate dispatch.
- **`pito` CLI parity sweep.** No CLI changes ship in this dispatch.
- **Astro / website changes.** N/A.
- **Migration rollback testing.** Destructive-and-reseed posture; the `down`
  method (if any) is for Rails bookkeeping only.
- **Single-binary distribution / install wizard.** Realignment work unit 12;
  deferred ~6 months.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`, depending on the agent
re-prefix follow-up status at dispatch time). Touches:

- `db/migrate/`, `db/schema.rb`, `db/seeds.rb`
- `app/models/`, `app/models/concerns/`
- `app/controllers/`, `app/controllers/concerns/`
- `app/views/sessions/`
- `app/mcp/`
- `app/lib/`, `lib/`
- `config/initializers/doorkeeper.rb`, `config/storage.yml` (verify only)
- `spec/**`

No `extras/cli/`, no `extras/website/`, no `docs/` (that is docs-keeper's
separate dispatch after validation).

## Reviewer checkpoints (post-implementation)

The reviewer agent runs:

1. `git grep 'Tenant\|tenant_id\|Current\.tenant\|BelongsToTenant\|find_by_username_or_email\|username' app/ lib/ spec/ db/ config/`
   → expect zero matches except in:
   - migration body (the column drop migration itself)
   - `db/schema.rb` (the migration version comment line)
   - any historical-context comment the implementation agent flags in advance
2. `bundle exec rspec` — green.
3. `bundle exec rubocop` — green (or no new violations).
4. `bundle exec brakeman -q` — green (or no new findings).
5. Manual playbook §1-§9 above.
6. Spec file count delta logged in `docs/plans/beta/08-tenant-drop/log.md`.
