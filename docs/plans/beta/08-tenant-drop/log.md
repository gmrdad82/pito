# Phase 08 — Tenant Drop · Log

## 2026-05-10 — Realignment paperwork landed; tenant-drop spec dispatch pending

**Done:**

- Realignment finished: 10 ambiguities resolved + 2 structural calls
  (Login-with-Google drop, destructive-and-reseed migration posture).
- ADRs landed:
  - **0003** updated with the destructive-and-reseed migration posture and the
    owned/tracked retirement (the `connected` flag plus the owned-vs-tracked
    distinction is collapsed; see ADR for details).
  - **0004** — MCP scope simplification to `dev` + `app`.
  - **0005** — Doorkeeper stays for Claude Mobile.
  - **0006** (new) — drop Login-with-Google.
- IDOR spec archived to `docs/decisions/archives/idor-spec.md`.
- Mobile notes triage: 5 notes deleted (their content is captured durably in the
  realignment doc and ADRs); 5 preserved (still load-bearing for unwritten
  work-unit specs — Video/Channel/Analytics/Game/Calendar surfaces).
- Phase 7.5 pre-specs 08 / 09 / 10 deleted outright in this cleanup pass:
  - `08-timelines-resurrection-prespec.md` — superseded by direct
    `Video.project_id` association scheduled in the tenant-drop-and-rebuild work
    (realignment work unit 4).
  - `09-mcp-sync-prespec.md` — superseded by the per-domain MCP coverage matrix.
  - `10-terminal-sync-prespec.md` — superseded by the per-domain CLI coverage
    matrix.
  - Phase 7.5 `dropped.md` updated with a 2026-05-10 entry recording the
    deletions.

**Decisions:**

- Phase numbering for the tenant-drop work lives at
  `docs/plans/beta/08-tenant-drop/`. (The legacy `08-youtube-data-sync/` folder
  predates the realignment and will be reconciled by the architect when phase
  numbering is revisited per the realignment doc's open notes.)
- Migration posture for the tenant drop is **destructive-and-reseed** (per ADR
  0003): drop `tenant_id` columns, drop the `Tenant` model, drop
  `BelongsToTenant`, drop `Current.tenant`, drop seed entries for tenants, and
  reseed. No data preservation; the running install is dev-only.

**Next:**

- Architect-spec dispatch: write the tenant-drop implementation spec under
  `docs/plans/beta/08-tenant-drop/specs/`. The spec should cover, at minimum:
  - Drop `tenant_id` columns from every table that carries one.
  - Drop the `Tenant` model and the `BelongsToTenant` concern.
  - Drop `Current.tenant` and every `Current.tenant`-derived scope / filter.
  - Drop seed entries that materialize a tenant.
  - Reseed flow that produces a working dev install without tenants.
- After the tenant drop lands, the next dispatch is MCP scope simplification
  (ADR 0004), followed by per-domain spec dispatches in the order specified in
  the realignment doc.

**Cross-references:**

- `docs/realignment-2026-05-09.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0006-drop-sign-in-with-google.md`
- `docs/orchestration/follow-ups.md`

## 2026-05-10 — rails-impl dispatch landed (Spec 01: tenant drop + email-only login)

**Done:**

- Schema migration `db/migrate/20260510021811_drop_tenant_and_username.rb` drops
  `tenant_id` from all 24 domain tables, drops `users.username` and
  `index_users_on_username`, drops the `tenants` table, replaces tenant-
  prefixed composite indexes with the post-drop equivalents (collections.name,
  footages.local_path UNIQUE install-wide, games.title, google_identities.
  google_subject_id UNIQUE install-wide, notes (project_id, path) UNIQUE
  per-project, projects.name, plus the three youtube_api_calls analytics
  composites without the tenant prefix).
- Models: deleted `app/models/tenant.rb` and
  `app/models/concerns/ belongs_to_tenant.rb`. `app/models/current.rb` now
  declares only `:user, :token, :session`. `User` rewrote to email + password
  only (no `username`, no `tenant`, no `find_by_username_or_email`); strips
  whitespace on assignment; max email length 254. `Session` no longer has the
  `unscoped.create!` workaround. `ApiToken#generate!` signature collapsed to
  `(user:, name:, scopes:, expires_at: nil)`. Every domain model dropped
  `include BelongsToTenant` / `belongs_to :tenant`. `GoogleIdentity` validates
  `google_subject_id` install-wide unique. `Footage` dropped
  `MissingProjectError` and the `denormalize_tenant_from_project` callback;
  `local_path` uniqueness is install-wide. `Note` path uniqueness is now
  per-project. `OauthApplication` / `OauthAccessToken` / `OauthAccessGrant`
  reduced to thin Doorkeeper subclasses.
- Controllers: `SessionsController` posts `email` (not `identifier`); audit keys
  renamed `identifier_attempted` → `email_attempted`; flash copy left verbatim.
  `Sessions::AuthConcern` and `Api::AuthConcern` drop the `Current.tenant` pin
  and the cross-tenant defense-in-depth check (the bearer dispatch still rejects
  tokens whose user is gone as `invalid_token`). `Mcp::RackApp` follows the same
  shape. Doorkeeper initializer drops `Current.tenant` from both authenticator
  blocks. Settings controllers (`tokens`, `oauth_applications`, `youtube`,
  `sessions`) drop the `where(tenant_id: ...)` scopes; `notes_controller`,
  `footages_controller`, `api/footages_controller`, `channels_controller`,
  `projects_controller`, `games_controller`, `collections_controller`,
  `auth/google_callbacks_controller`, `timelines_controller` drop every tenant
  pin / argument.
- Lib / services / jobs: `NotesFilesystem` layout is now
  `<root>/projects/<project_id>/`. `Pito::AssetsRoot.tenant_root` removed;
  `NotesLockGuard` rewrote to an install-wide AppSetting key. `NoteSyncJob` runs
  install-wide (legacy positional arg ignored). `Notes::EmbedJob` drops the
  `Note.unscoped` workaround and the `tenant_id` field from the Meilisearch
  payload. `Youtube::Auditor` / `Youtube::Quota` / `Google::RevokeToken` drop
  the tenant column. `lib/tasks/tokens.rake` drops the tenant lookup.
- View: `app/views/sessions/new.html.erb` is email-only with
  `placeholder="you@example.com"`.
- Seed: `db/seeds.rb` reads only
  `Rails.application.credentials.owner. {email, password}`. No tenant creation,
  no username. Seed runs idempotently and the destructive
  `bin/rails db:drop db:create db:migrate db:seed` flow was tested locally.
- Specs: deleted `spec/factories/tenants.rb`, `spec/models/tenant_spec.rb`,
  `spec/models/cross_tenant_leak_spec.rb`,
  `spec/models/concerns/belongs_to_tenant_spec.rb`,
  `spec/support/tenant_context.rb`. Rewrote / updated every factory to drop the
  `tenant` association. Rewrote `spec/models/user_spec.rb`,
  `spec/models/session_spec.rb`, `spec/models/api_token_spec.rb` for the new
  shapes. Rewrote `spec/requests/sessions_spec.rb` for email-only login (every
  enumerated case from the spec landed: happy POST, wrong password, malformed
  email, blank email, unknown email, stray-param flaw test, throttle,
  intended-URL redirect, logout, gating). Rewrote
  `spec/requests/api/auth_concern_spec.rb` and
  `spec/requests/mcp/rack_app_auth_spec.rb` for the no-tenant-check shape and
  the user-deleted flaw test. Rewrote
  `spec/requests/mcp/oauth_token_acceptance_spec.rb` for the no-cross-tenant
  case. Updated `spec/lib/notes_filesystem_spec.rb`,
  `spec/lib/pito/ assets_root_spec.rb`, `spec/lib/notes_lock_guard_spec.rb`,
  `spec/jobs/note_sync_job_spec.rb`, `spec/jobs/notes/embed_job_spec.rb`,
  `spec/decorators/channel_decorator_spec.rb`, `spec/seeds_spec.rb`, plus every
  model and request spec that touched tenant.
- Config: deleted `config/initializers/console_tenant.rb` (the auto-pin is
  unnecessary now that the tenant model is gone).

**Test posture:**

- `bundle exec rspec`: **1662 examples, 0 failures, 0 pending.** Spec count
  delta from the pre-Phase-8 run: roughly -1 (the IDOR / cross-tenant-leak /
  belongs_to_tenant model specs went away; the User / Session / ApiToken /
  NotesLockGuard / sessions / api auth / mcp rack-app / mcp oauth / footages /
  notes / project_reference rewrites added back the new exhaustive coverage).
  The new test cases the spec enumerated all landed; an additional handful were
  added during the sweep (e.g., the rack-app `tenant_id` smuggling flaw test,
  the per-project `path` uniqueness "permitted across projects" assertion).
- `bundle exec rubocop`: 420 files inspected, no offenses.
- `bundle exec brakeman -q -w2`: 0 security warnings.

**Files touched (high-level counts):**

- 1 new migration
- 1 deleted model (`Tenant`), 1 deleted concern (`BelongsToTenant`), 1 deleted
  initializer (`console_tenant`)
- 16 model edits
- 11 controller edits
- 4 lib / service / job edits, plus 1 rake task edit
- 1 view rewrite (`sessions/new.html.erb`), 1 layout edit (`new.html.erb`
  placeholder)
- 1 seed rewrite, 1 mcp tool edit (`create_channel`)
- 23 factory edits, 5 deleted spec files, ~30 spec rewrites / updates, 2
  support-file edits

**Manual playbook (user-runnable):**

1. `bin/rails credentials:edit --environment development` — replace the existing
   `:owner` block with `{ email: <you>, password: <pw> }`. Repeat for
   `--environment test`.
2. Optional storage cleanup before reseed:
   `rm -rf <PITO_NOTES_PATH>/* <PITO_ASSETS_PATH>/*` to drop the legacy
   `tenant-X/` segments from disk (no rake task ships per the locked open
   question).
3. `bin/rails db:drop db:create db:migrate db:seed` — verify the seed prints
   `user: <email> (id=…)` and the dev-token banner exactly once.
4. `bin/dev`. Visit `/login`. Confirm the form has a single `email` input (with
   `you@example.com` placeholder), no "or username" copy. Submit valid + invalid
   combos.
5. Visit `/settings/oauth_applications`, `/settings/tokens`,
   `/settings/sessions`, `/settings/youtube` — confirm renders, no tenant filter
   visible.
6. Re-pair the MCP connection from Claude Mobile / Desktop. Confirm
   `dev:save_note` lands a file under `docs/notes/`.
7. Open a previously-uploaded composite cover; verify the on-disk path has no
   `tenant-X/` prefix. Confirm note files now live at
   `<PITO_NOTES_PATH>/projects/<id>/<file>.md`.

**Out-of-scope (next dispatches the master agent should consider):**

- `pito-docs-keeper` for the prose rewrites enumerated in the spec
  (`docs/architecture.md`, `docs/auth.md`, `docs/setup.md`, `docs/mcp.md`, the
  Architecture-notes paragraph in `CLAUDE.md`).
- `pito-reviewer` to run the spec's reviewer checkpoints.
- The user runs `bin/rails credentials:edit` for the `:owner` block shape change
  before the manual playbook walkthrough — the rails-impl dispatch cannot edit
  `config/credentials.yml.enc`.

**Cross-references:**

- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/realignment-2026-05-09.md`
