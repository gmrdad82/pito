# Phase 4 — Project Workspace · Session Log

## 2026-05-04 — Step 0 — MCP Dev KB surface

**State at start:** Phase 3 (Channel Revamp) committed and pushed. The
multi-repo split was consolidated into the monolith earlier in the week (commit
`2a920e3`), so `pito-sh` is now `extras/cli/`, the website lives at
`extras/website/`, and the dev knowledge base merged into `docs/`. Phase 4
master spec (`docs/plans/beta/04-project-workspace/specs/project-workspace.md`)
is in place but no Phase 4 implementation has started. The MCP server at
`mcp.pitomd.com` (Cloudflare tunnel, single-user, no auth concerns yet) was
running with the existing Channel/Video tool surface only — no docs surface, no
Mobile-side capture path.

**Decisions captured before execution:**

- The user wanted natural conversation flow between Desktop Claude (this Claude
  Code session, file-system access) and Claude Mobile (over the existing MCP
  server). Claude Code's first sketch was a generic three-tool docs surface
  (`list_docs`, `read_doc`, `write_doc`). The user pushed back on the
  over-engineered shape and reframed the requirement: Mobile is a
  scratchpad-and-recovery surface, not a generic file system. Desktop curates;
  Mobile captures.
- Locked tool surface:
  - `list_docs` — filterable, mtime-sortable enumeration under `docs/`.
  - `read_doc` — single-file read by relative path, anywhere under `docs/`
    (logs, plans, specs, ADRs, curated reference docs).
  - `save_note` — write-only into `docs/notes/`. Server-generated filename
    `YYYY-MM-DD-HH-MM-SS-<slug>.md`. No overwrite. Multiple captures of the same
    thought are fine; cleanup is Desktop's job per the user's preference. Mobile
    never edits, deletes, or renames.
- Path safety: lexical containment via `Pathname#cleanpath`, traversal rejected.
  Symlink resolution via `realpath` was specced but skipped in implementation —
  Mobile cannot create symlinks, so practical risk is near zero. Captured as the
  single spec/implementation deviation in the reviewer playbook.
- Credentials wired up live in parallel: Voyage AI API key + a GitHub
  fine-grained PAT scoped to `gmrdad82/pito` with Contents:Read-only +
  Metadata:Read-only. Voyage embed call returned a 1024-dim vector for 1 token
  billed; GitHub releases endpoint returned 200 with zero releases yet (workflow
  hasn't run).
- Two Phase 4 master spec amendments dropped out of the credential verification:
  - Voyage call gating (§3.5) — defaults `false` in dev/test, `true` in prod,
    env-var override. The user explicitly said don't fire Voyage on dummy data.
  - `pito version` prints the short build SHA (7 chars) instead of semver (§7),
    with §8.1 restating the served filename is always `pito` (no `-<sha>`
    suffix).

**What landed (file-level):**

- **Step 0 sibling spec:**
  `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md` (new).
- **Step 0 implementation:** `app/lib/dev_doc_path.rb` (path-safety helper);
  `app/mcp/tools/list_docs.rb`, `read_doc.rb`, `save_note.rb`; spec coverage at
  `spec/lib/dev_doc_path_spec.rb` and
  `spec/mcp/tools/{list_docs,read_doc,save_note}_spec.rb`. 62 new examples, 0
  failures. Full suite 746 / 0. Brakeman 0 warnings. RuboCop 0 offenses. The MCP
  server (`app/mcp/pito_server.rb`) auto-registers any `Mcp::Tools::*` class via
  cold-require — no edits to the server itself.
- **Folder normalization:** 16 phase folders renamed `<NN>-plan.md` → `plan.md`
  via `git mv` so `list_docs(name_pattern: "plan.md")` works cleanly. `beta.md`
  updated for the live phase index (14 path pointers). Frozen historical files
  (postgres-migration / channel-revamp specs and additions, pre-2026-05-04
  playbooks) intentionally left with their old `<NN>-plan.md` references so they
  remain accurate historical records.
- **CLAUDE.md additions:** "Logging convention" section (codifying this log
  entry's format) + "MCP Dev KB surface (Mobile interop)" section.
- **Phase 4 master spec amendments**
  (`docs/plans/beta/04-project-workspace/specs/project-workspace.md`):
  - §3.5 "Voyage call gating (2026-05-04 amendment)" — flag, env override,
    EmbedJob short-circuit, `voyage:smoke_test` rake task.
  - §7 "Version output — short Git SHA (2026-05-04 amendment)" — `pito version`
    and `pito --version` print 7-char SHA from build-time embed (build.rs or
    vergen, cli-impl decides edge cases).
  - §8.1 served-filename restatement (always `pito`, no `-<sha>` suffix).
  - §15 acceptance-criteria additions for the three new behaviors.
  - §14 "Step 0 — MCP Dev KB surface (precedes Phase A)" pointer to the sibling
    spec.
- **Step 0 additions.md entry:**
  `docs/plans/beta/04-project-workspace/additions.md` (new) — records the scope
  addition with rationale.
- **Reviewer playbook:**
  `docs/orchestration/playbooks/2026-05-04-mcp-dev-kb-surface.md` — gates
  summary, six minor spec ambiguities resolved by implementation, one
  spec/implementation deviation (path-safety is lexical via `cleanpath`, NOT
  `realpath` as the spec said — symlink resolution skipped).
- **Follow-ups index** (`docs/orchestration/follow-ups.md`) — three new entries
  from the monolith pivot: CI cli-job working-directory not exercising
  workspace-root clippy; `Procfile.dev` / `bin/dev` / Rails-controller wiring
  for `extras/cli/target/release/pito` (zero references currently — Phase 4
  decides); 14+ stale `pito-sh` comments in Rails controllers / config (rename
  sweep).
- **Empty inbox folder:** `docs/notes/.gitkeep`.
- **Commit:** `5faad26` "Add MCP Dev KB surface (Phase 4 Step 0)" — 34 files,
  +1,699 / −13. Pushed to `origin/main`.

**Where we stand:**

- Phase 4 — Project Workspace. Step 0 (MCP Dev KB surface) shipped. Phase A
  (sequential foundation, 9 steps via `pito-rails` agent) is queued and
  unblocked: Voyage credentials + GitHub PAT both in place; Voyage gated off in
  dev/test until real notes flow. The user's go-ahead is the only thing standing
  between us and Phase A's `add_notes_syncing_at_to_tenants` migration.
- Open items for the next session to address (small, non-blocking):
  - One spec/implementation deviation in the path-safety helper (lexical vs
    realpath) — decide whether to amend the spec to match implementation, or
    tighten the helper. Low practical risk.
  - Six minor spec ambiguities resolved by implementation defaults (H1-only
    first_heading, CLAUDE.md inclusion rules, slug hygiene, integer/ISO8601
    formats, recursive globbing, prefix traversal rejection) — capture in spec
    if locking is desired.
  - `CLAUDE.md` line 32 references `docs/auth.md` which doesn't exist on disk.
    Phase 12 territory; leave for now.
  - One untracked test note `docs/notes/2026-05-04-00-02-40-test-note.md` from
    manual validation. User asked to leave it for now.
  - 1 low Dependabot alert raised by GitHub at push time — separate from the
    existing CLI-side alert; review on dashboard.
- Forward-looking: the Phase 4 master spec lists Phase B's six parallel
  workstreams (controllers/views/Stimulus, NoteSyncJob+cron+lock, `pito footage`
  subcommand, GitHub Actions, design refresh, ADR addendum + log) — those fan
  out after Phase A converges.

**References (full paths so Mobile can `read_doc` them):**

- `docs/plans/beta/04-project-workspace/specs/project-workspace.md` — master
  spec for Phase 4.
- `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md` — Step 0
  sibling spec.
- `docs/plans/beta/04-project-workspace/additions.md` — scope additions.
- `docs/orchestration/playbooks/2026-05-04-mcp-dev-kb-surface.md` — Step 0
  reviewer playbook.
- `docs/mcp.md` — MCP server docs (now includes the Dev KB surface section).
- `CLAUDE.md` — root project instructions (Logging convention + MCP Dev KB
  surface sections).

## 2026-05-04 — Phase A — Foundation

**State at start:** Step 0 (MCP Dev KB surface) committed and pushed
(`5faad26`). Voyage AI key + GitHub PAT both verified end-to-end (1024-dim
embedding returned; releases endpoint reachable). Phase A's go-ahead arrived;
nine sequential foundation steps + the Voyage gating flag fan out from a single
`pito-rails` agent dispatch — no Phase B controllers, views, jobs, Stimulus,
design refresh, ADR addendum, GitHub Actions, or Rust footage subcommand in this
entry.

**Decisions captured during execution:**

- **`ruby-vips` requires `require: false` in the Gemfile.** libvips 8.18 is not
  installed on the dev host (Arch `extra/libvips` available via pacman but never
  pulled in). `gem "ruby-vips"` ordinarily auto-requires via
  `Bundler.require(*Rails.groups)`, which then calls
  `Vips.attach_function "vips_init"`, which dlopens `libvips.so.42` at boot and
  aborts with `LoadError`. Pinning the gem at `~> 2.2` with `require: false`
  keeps Bundler resolution honest (image_processing 1.14 needs
  `ruby-vips >= 2.0.17`) without firing the eager dlopen at boot.
  `image_processing/vips.rb` lazily `require "vips"` the moment a variant is
  generated — Phase A never exercises a variant in spec, so the host needs
  libvips before Phase B's cover-art tests run. Captured in the Phase B
  prerequisites list below.
- **Voyage gating flag location → `config/application.rb`.** The amendment in
  §3.5 left the choice between `application.rb` and per-env initializers to the
  implementer. Centralising the flag in the application config block keeps the
  env-var override (`PITO_VOYAGE_ENABLED`) and per-environment defaults (false
  in dev/test, true in prod) in a single branchless place. Per-env initializers
  would have spread the rule across three files for no benefit.
- **`active_storage.variant_processor = :vips` lives in `application.rb`, not
  per-env.** Same reasoning: the choice is global and never differs per
  environment. The spec's only constraint is "NOT mini_magick".
- **Local `PITO_ASSETS_PATH` and `PITO_NOTES_PATH` default to `tmp/...`** inside
  the repo. The `/var/lib/pito-*` defaults from §5 / §6.1 work on Hetzner
  (root-writable mount), but locally on Arch they require sudo to create.
  `.env.example`, `.env.development`, and `.env.test` all point at
  `tmp/pito-{assets,notes}` (and `tmp/pito-{assets,notes}-test` in the test env)
  so `bin/dev` and `bin/rspec` run without root. Production (Hetzner) ignores
  `.env` entirely and falls back to the original `/var/lib/pito-*` defaults via
  `ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets")` in
  `config/storage.yml`.
- **Migration class names: `CreateProjectNotes` (file
  `20260504000008_create_project_notes.rb`).** A historical
  `20260426150334_create_notes.rb` (production-notes Alpha leftover, then
  dropped in `20260426213600_drop_productions_and_notes.rb`) declares
  `class CreateNotes`, so reusing the same class name throws
  `ActiveRecord::DuplicateMigrationNameError` even though the table got dropped.
  Renaming the new class to `CreateProjectNotes` keeps the new table name
  `notes` (per §3.5) without colliding on the class.
- **Migration timestamps: explicit sequence `20260504000001..000009`.** AS
  install was generated at wall-clock time (`20260504001930`) but renamed to
  `20260504000002` so the sequence in §3.8 stays tight and obvious in
  `db/migrate` listings. The renumber is invisible to Rails (the version is the
  timestamp prefix) and keeps the directory human-scannable.
- **Routing approach for the importer download.** The architect's task was
  explicit: route shell only, controller body in Phase B. The route has
  `to: "footage_importer/downloads#show"` plus the named helper
  `footage_importer_download_path`. We assert the named helpers via the routes
  table and `route_names` introspection — both `route_to` and `recognize_path`
  would force-load the missing `FootageImporter` namespace at spec time, which
  falsely reports a "broken" route. The routes table contains the row; that's
  the contract Phase A owes Phase B.
- **Default-create defaults at the model layer.** Each new model declares
  `attribute :name, :string, default: "Untitled X"` (Project, Collection,
  Game.title, Note.title, Timeline.title) on top of the same DB-side default.
  The DB default suffices for SQL-only inserts; the model-level default lets
  `Project.new.name == "Untitled project"` without round- tripping through the
  DB, which matters for forms / inspection / spec assertions in Phase B.
- **Footage `tenant_id` denormalization.** Spec §3.4 marks `tenant_id` nullable
  but says "denormalized for scoping". A `before_validation` callback fills
  `tenant_id` from `project.tenant_id` if missing. The uniqueness scope on
  `local_path` is `(tenant_id, local_path)`, so ungating writes by hydrating
  tenant_id eagerly is the simpler path. The column stays nullable at the schema
  level so the Phase B importer can land partial rows during diff resolution.
- **Project polymorphic association cascade.** `ProjectReference` has
  `belongs_to :project` and `belongs_to :referenceable` (polymorphic). Game /
  Collection don't declare an inverse `has_many` of references — the spec only
  requires the Project-side associations and a model layer validation that
  `referenceable_type ∈ {Game, Collection}` and cross-tenant references are
  rejected. Skipping the inverse keeps Game and Collection model files focused;
  Phase B can add it if the reverse direction is needed for the references pane.

**Gem additions (Phase 4 §14 step 5):**

- `image_processing ~> 1.14` — Active Storage variant pipeline. Pinned loose
  because Active Storage tracks the latest patch internally.
- `ruby-vips ~> 2.2`, `require: false` — variant processor. Loose pin because
  libvips API stability is good and the gem rarely breaks.
- `aasm ~> 5.5` — Timeline state machine. Latest released line is 5.5; the spec
  asked for `~> 5.6` but the highest published version is 5.5.2, so I tightened
  to 5.5.
- `commonmarker ~> 2.4` — GFM markdown rendering for Phase B's note view. Gem
  lands now; the renderer helper that uses it is Phase B.
- `neighbor ~> 0.6` — pgvector AR bridge (`Note.has_neighbors :embedding`).
  Wired now so Phase 9/10's similarity surface has zero rework.

**What landed (file-level summary by §14 step):**

- **Step 1 — `add_notes_syncing_at_to_tenants` migration.**
  `db/migrate/20260504000001_add_notes_syncing_at_to_tenants.rb`. Reverse: drops
  the column. Tenant model picks up the column implicitly (no explicit attribute
  needed; Rails reads the column).
- **Step 2 — Active Storage install.**
  `db/migrate/20260504000002_create_active_storage_tables.active_storage.rb`
  (rename of the wall-time-generated migration to keep §3.8 sequencing tight).
  Adds the three AS tables.
- **Step 3 — new-model migrations.** `20260504000003_create_collections.rb`,
  `20260504000004_create_games.rb` (jsonb `platforms`, fk to collections),
  `20260504000005_create_projects.rb`,
  `20260504000006_create_project_references.rb` (polymorphic columns +
  uniqueness index per `[project_id, referenceable_type, referenceable_id]`),
  `20260504000007_create_footages.rb` (kind/source/orientation enums,
  `bit_depth` default 8, `tenant_id`-scoped `local_path` unique index),
  `20260504000008_create_project_notes.rb` (table `notes` with
  `embedding vector(1024)` and `(tenant_id, path)` unique),
  `20260504000009_create_timelines.rb` (state default 0, fk to videos optional).
  All reversible — verified by rolling back all 9 and re-migrating cleanly.
- **Step 4 — models.** `app/models/project.rb`, `collection.rb`, `game.rb`
  (cover_art variants declared via `cover_art_thumbnail/_card/_full`),
  `footage.rb` (enums, game-platform allowlist, commentary-track consistency,
  tenant denormalization), `note.rb` (`has_neighbors :embedding`), `timeline.rb`
  (aasm machine), `project_reference.rb` (allowlist + cross-tenant rejection).
  `tenant.rb` updated for new associations and the `notes_syncing_at` column
  (column read implicitly).
- **Step 5 — gems + variant processor + Voyage flag.** Gemfile + Gemfile.lock
  updated. `config/application.rb` sets
  `config.active_storage.variant_processor = :vips` and
  `config.voyage_embeddings_enabled` per the §3.5 amendment.
- **Step 6 — `storage.yml`.** `local` service now reads
  `ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets")`. The
  `config.active_storage.service = :local` line was already in `development.rb`
  and `production.rb`; verified no duplication.
- **Step 7 — Docker compose volumes + .env files.** `docker-compose.yml`
  declares `pito_notes` and `pito_assets` named volumes (unmounted; reserved for
  the Hetzner cutover when Rails moves into a container). `.env.example`,
  `.env.development`, `.env.test` add `PITO_ASSETS_PATH` and `PITO_NOTES_PATH`
  defaults pointing into `tmp/` so local boots don't require sudo. Voyage gating
  flag and the override env var documented in `.env.example` (commented out).
- **Step 8 — routes.** `config/routes.rb` adds default RESTful
  `resources :projects/:collections/:games/:footages/:notes/:timelines`, the
  `footage_importer_download` GET stub, and the nested
  `api/projects/:id/footages` index/create. Controllers (other than the importer
  stub, which is also Phase B) intentionally not created.
- **Step 9 — factories + seeds + cover-art fixture.**
  `spec/fixtures/files/cover_art.jpg` (64x64 JPEG, generated locally via
  `convert -size 64x64 xc:'#cc6633'`, committed as a binary blob). Factories:
  `projects`, `collections`, `games` (with `:with_collection` and
  `:with_cover_art` traits), `footages` (with `:with_game` trait), `notes`,
  `timelines` (with `:exported` and `:uploaded` traits), `project_references`
  (with `:collection` trait). `db/seeds.rb` extends with one Collection, one
  Game (cover_art attached from the fixture), one Project referencing both Game
  and Collection, one Note (DB row only — disk file lands in Phase B's
  NoteSyncJob), and one Timeline in `editing`. Seed verified end-to-end against
  the live dev DB.

**Spec coverage delta:**

- 7 new model spec files (`project_spec.rb`, `collection_spec.rb`,
  `game_spec.rb`, `footage_spec.rb`, `note_spec.rb`, `timeline_spec.rb`,
  `project_reference_spec.rb`).
- `tenant_spec.rb` extended for the six new associations and the
  `notes_syncing_at` column.
- `spec/routing/project_workspace_routing_spec.rb` — named-helper + routes-table
  introspection (no `route_to` / `recognize_path` to keep Phase A free of Phase
  B controller stubs).
- `spec/lib/voyage_embeddings_flag_spec.rb` — config flag default in test env +
  `Rails.application.config.voyage_embeddings_enabled` responds.
- Suite final: **855 examples, 0 failures** (up from 746 / 0 at Step 0 close —
  net +109 examples).

**QA gates:**

- `bundle exec rspec` — 855 / 0.
- `bundle exec brakeman --no-pager -q` — 0 warnings.
- `bundle exec rubocop` over the 36 changed/new files — 0 offenses.
- `bin/rails db:rollback STEP=9 && bin/rails db:migrate` — clean both
  directions.
- `bin/rails db:seed` — full pipeline runs to completion (including the
  channels/videos slow path); the new Phase 4 sample lands. Verified separately
  via `bin/rails runner` for fast iteration.

**Where we stand:**

- Phase A complete. Phase B's six parallel workstreams unblocked:
  - **Controllers, views, panes, Stimulus, nav update** (`pito-rails`).
    Default-create instant-new actions for Project/Collection/Game/Note/
    Timeline; the three-pane Project show; nav `[projects]` insertion after
    `[videos]`; horizontal-scroll mobile panes; saved-views horizontal scroll.
    Routes already in place.
  - **`NoteSyncJob` + cron + lock UX** (`pito-rails`). 5-minute Sidekiq cron,
    tenant-wide lock via `Tenant#notes_syncing_at`, banner + disabled save
    buttons + 423 on mutating note APIs. Notes::EmbedJob short-circuit reads
    `Rails.application.config.voyage_embeddings_enabled` (already wired).
  - **`pito footage` subcommand** (`cli-impl`). New module under
    `extras/cli/src/footage/`. Subcommand wiring in `src/main.rs`. The importer
    download endpoint route is in place.
  - **GitHub Actions** (`pito-rails`). Single workflow for Rails + Rust matrix;
    cleanup workflow for `pito-*` releases.
  - **Design refresh** (`docs-keeper`). Seven rules in `design.md` + panes
    section + saved views section.
  - **ADR 0001 addendum + log** (`docs-keeper`). One-line image-asset carve-out;
    this log entry stays as the running thread for Phase B.
- Prerequisites Phase B owners need before they start:
  - **Install libvips on the dev host.** `sudo pacman -S libvips` (Arch).
    Without it, `image_processing/vips.rb` fails at first variant generation.
    Phase A specs avoid variant generation; Phase B's cover-art tests will need
    libvips. Worth flagging as the very first manual step in the Phase B
    reviewer playbook.
  - **`bin/rails voyage:smoke_test` rake task.** Listed in §3.5 and §15 but not
    in the Phase A §14 step list; treating it as Phase B work alongside
    Notes::EmbedJob (same surface, same Voyage code path).
  - **`commonmarker` rendering pipeline integration.** Gem landed in Phase A;
    the helper that calls it lands in Phase B.
- Open spec ambiguities worth surfacing for the architect:
  - §13 lists `resources :projects do member { get :panes } end`. §9.1
    explicitly drops the `panes` member action ("the panes belong to the show
    page"). Phase A landed `resources :projects` without the `:panes` member,
    matching §9.1. If §13's intent should override, Phase B can add the member
    route + panes action; Phase A's choice is recorded here.
  - §3.4 marks `footages.tenant_id` nullable; the spec's stated rationale is
    "denormalized for scoping". Phase A enforces tenant hydration via
    `before_validation`, so in practice every saved row has tenant_id. Whether
    to tighten the column to NOT NULL is a Phase B decision once the importer's
    exact write path is in code.
  - §11.2 (Video aasm machine: scheduled → published → unpublished) is not part
    of Phase A's model list; left for Phase B.
- Anything unexpected that the architect should know:
  - `db:seed` is slow on first run (~6+ minutes for 100 channels + 250 videos
    with rich stats). The Phase 4 sample at the end of seeds.rb runs in <1s once
    the channels/videos finish. If the reviewer playbook hits a 2-minute
    timeout, the Phase 4 portion will not have landed yet — re-run with a longer
    timeout or extract the Phase 4 block into a separate seed task.
  - The `git status` after Phase A includes a new `spec/fixtures/files/`
    directory. The `cover_art.jpg` blob inside is a 64x64 JPEG generated
    locally; size is well under any sensible repo blob budget.

**References (full paths so Mobile can `read_doc` them):**

- `docs/plans/beta/04-project-workspace/specs/project-workspace.md` — master
  spec.
- `db/migrate/20260504000001..000009*.rb` — the nine Phase A migrations.
- `app/models/{project,collection,game,footage,note,timeline, project_reference,tenant}.rb`
  — the model layer.
- `config/application.rb` — variant processor + Voyage gating flag.
- `config/routes.rb` — Phase 4 route shells.
- `config/storage.yml` — `local` service now reads `PITO_ASSETS_PATH`.
- `.env.example`, `.env.development`, `.env.test` — Phase 4 env vars.
- `spec/factories/{projects,collections,games,footages,notes, timelines,project_references}.rb`
  — Phase A factories.
- `spec/models/*_spec.rb` (the seven new ones), `spec/models/tenant_spec.rb`
  (extended), `spec/routing/project_workspace_routing_spec.rb`,
  `spec/lib/voyage_embeddings_flag_spec.rb` — coverage.
- `spec/fixtures/files/cover_art.jpg` — cover-art seed fixture.
- `db/seeds.rb` — extended sample at the bottom.
- `docker-compose.yml` — named volumes for `pito_notes` / `pito_assets`.

### Post-review refinements (2026-05-04)

Two surgical follow-ups landed on top of Phase A, both inside the existing
foundation surface:

(a) **`ProjectReference` auto-denormalize tenant_id.** Mirroring `Footage`'s
shape, `app/models/project_reference.rb` now declares
`before_validation :denormalize_tenant_from_project` with the same
`self.tenant_id ||= project&.tenant_id` body. The canonical
`project.games << game` shovel now succeeds without the caller threading
`tenant_id` through. A second guard, `validate :tenant_must_match_project`,
fails the row if `tenant_id` is set explicitly to a value that disagrees with
`project.tenant_id` — so the `||=` semantics are preserved (explicit matching
tenants honoured) while cross-tenant misuse is still rejected.
`spec/models/project_reference_spec.rb` adds three examples in a
`tenant denormalization (before_validation)` describe block: the shovel succeeds
and stamps tenant_id, an explicit matching tenant_id is preserved, a disagreeing
explicit tenant_id is rejected. ProjectReference spec count 9 → 12.

(b) **Voyage gating flag pivots from `Rails.application.config` to
`AppSetting`.** New migration
`db/migrate/20260504000010_add_voyage_embeddings_enabled_to_app_settings.rb`
adds `voyage_embeddings_enabled :boolean, null: false, default: false`
(reversible via `t.remove`). The `config.voyage_embeddings_enabled` block plus
the `PITO_VOYAGE_ENABLED` env-var override are removed from
`config/application.rb`; the same env var is removed from `.env.example`
(replaced with a one-paragraph pointer to `AppSetting`). The model picks up a
class method `AppSetting.voyage_embeddings_enabled?` that reads the de-facto
singleton (`AppSetting.first`) and returns `false` when no row exists, so Phase
B's `Notes::EmbedJob` can short-circuit safely on a fresh DB.
`spec/lib/voyage_embeddings_flag_spec.rb` is deleted; its replacement lives in
`spec/models/app_setting_spec.rb` as two new describe blocks covering default
value, runtime flip, missing-singleton fallback, and idempotent flip cycles.
Seeds gain a production-only block that sets
`AppSetting.first.voyage_embeddings_enabled = true` (idempotent — guarded by
`AppSetting.exists?`). The single `Note` model comment line referencing the old
`Rails.application.config` flag is updated to point at the new class method.
AppSetting spec count 8 → 14.

(c) **Net spec delta.** Suite went from 855 / 0 (Phase A close) to 862 / 0 (this
dispatch close) — +7 examples net (+3 ProjectReference, +6 AppSetting, −2 from
deleting `voyage_embeddings_flag_spec.rb`). Brakeman 0 warnings. RuboCop 0
offenses on the eight files touched. Migration runs cleanly in both directions
on dev and test DBs.
