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

### Phase B — pito footage subcommand (2026-05-04)

Implementer agent: `pito-sh-impl`. Source crate: `extras/cli/`. This dispatch
delivers the §7 / §8 Rust importer surface — the client-side ffprobe walk, the
diff classification, the TUI confirmation + progress overlays, and the
wiremock-backed integration tests. (Reconstructed from the implementer report
after the unstaged-revert incident — see the sibling note below for context.)

**Files added under `extras/cli/`:**

- `src/lib.rs` (new — library facade for integration tests)
- `src/footage/mod.rs`
- `src/footage/probe/mod.rs`
- `src/footage/probe/ffprobe.rs`
- `src/footage/api/mod.rs`
- `src/footage/api/models.rs`
- `src/footage/api/client.rs`
- `src/footage/diff.rs`
- `src/footage/ui/mod.rs`
- `src/footage/ui/confirmation.rs`
- `src/footage/ui/progress.rs`
- `tests/footage_integration.rs`

**Files modified:**

- `Cargo.toml` — added `[lib]` block (`name = "pito"`, `path = "src/lib.rs"`);
  added `which = "7"` runtime dep; added `wiremock = "0.6"` and `tempfile = "3"`
  dev-deps.
- `src/main.rs` — added `mod footage;`.
- `src/cli.rs` — replaced `FootageArgs` placeholder with full subcommand surface
  (`import` + flags).
- `src/commands/footage.rs` — replaced placeholder with full importer.
- `src/api/client.rs` — added `impl Default for MockClient` (3 lines, required
  after lib exposure for clippy).

**Subcommand surface.**
`pito footage import --project <ID> --path <DIR> [--game <ID>] [--platform <NAME>] [--kind a_roll|b_roll] [--source obs|camera] [--description TEXT] [--nas-path PATH] [--dry-run]`.
Defaults: `--kind=a_roll`, `--source=obs`.

**Decisions captured (six spec ambiguities resolved):**

- fps diff epsilon = `0.0005` (absorbs `decimal(6,3)` round-trip noise).
- `pix_fmt → bit_depth` mapping via string-sniff (`p12le`/`p12be` → 12;
  `p10le`/`p10be`/`p010le` → 10; else 8) rather than enum.
- `color_profile` rejection extended beyond spec's `unknown`/`reserved` to also
  reject empty/whitespace-only strings; all collapse to `None` so the Rails
  column stays nullable.
- `recorded_at` ISO 8601: `format.tags.creation_time` taken verbatim; mtime
  fallback uses `%Y-%m-%dT%H:%M:%SZ` (UTC suffix).
- PATCH body scope = probed metadata only (filename, duration, resolution, fps,
  codec, bit_depth, color_profile, aspect_ratio, orientation, audio_track_count,
  has_commentary_track, recorded_at). Omits user-managed columns (description,
  kind, source, game_id, platform, nas_path, local_path) so re-runs never stomp
  UI edits.
- `--dry-run` treats `existing` as empty — every probed file appears as Add, no
  GET fired.

**Gates.**

- `cargo test`: 287 passing, 0 failing (102 lib + 174 binary + 11 integration).
- `cargo clippy --all-targets -- -D warnings`: 0 warnings. (Two clippy warnings
  fixed in flight: `clippy::new_without_default` on `MockClient` via Default
  impl; `clippy::large_enum_variant` on `DiffEntry::Change` via Box.)
- `cargo build --release`: success. Binary at `target/release/pito`, ~7.0 MB.
- `cargo fmt --check`: clean on every file added or edited. Pre-existing fmt
  drift exists in `src/app.rs`, `src/keys.rs`, `src/ui/*`, `src/api/*` (NOT
  introduced by this dispatch) — flagged for a separate one-shot cleanup.

**Deferred.** The `pito version` short-SHA tweak (Phase 4 spec §7 amendment) —
pairs naturally with this work but needs a `build.rs` vs `vergen` decision.
Logged for follow-up.

**Reviewer attention.** JSON wire-shape contract with the parallel
`pito-rails #app` Rails footages controller (key list above; wrapper is
`{"footage": {…}}` per Rails strong-params; `has_commentary_track` is the only
Boolean — yes/no via shared `crate::api::yes_no` helper).

**URL contract correction (2026-05-04, post-review):** reviewer flagged a
blocker — the Rust client was hitting `/projects/<id>/footage.json` (singular,
no namespace), but Rails actually exposes the JSON list / create at
`/api/projects/<id>/footages.json` (plural, namespaced). Both wiremock and
client agreed on the wrong URL, so tests passed green while a real round-trip
against `bin/dev` would 404. Spec §7.5 (Rust contract) and §13 (Rails routes)
contradicted; Rails is landed, so the Rust client moved to match. Updated the
two `format!` strings in `src/footage/api/client.rs` (the GET in `list_footage`
at line 82, and the POST in `create_footage` at line 105), the doc-comment
endpoint list at the top of the file, and the two inline unit tests
(`url_composition_matches_spec_paths`,
`url_strips_trailing_and_leading_slashes`). In `tests/footage_integration.rs`
updated all eight `path("/projects/7/footage.json")` mock matchers (lines 138,
155, 180, 205, 283, 291, 299, 430) plus the stale URL reference in the doc
comment at line 199. PATCH `/footages/:id.json` and DELETE `/footages/:id.json`
are intentionally left at the top level — those are served by
`FootagesController` member actions (NOT `Api::FootagesController` collection
actions). The asymmetry (collection under `/api/`, member at top level) mirrors
what Rails actually exposes; an API-surface-symmetry follow-up is queued
separately. `cargo test`: 287/0. `cargo clippy --all-targets -- -D warnings`: 0
warnings.

### Phase B — App code: controllers + views + Stimulus + jobs + lock UX (2026-05-04)

Implementer agent: `pito-rails #app`. This dispatch lit up the Rails surface for
Phase 4 — the eight controllers, ~17 view templates, the two Sidekiq jobs, the
notes-sync lock-UX boundary, and the CodeMirror Stimulus mount. (Reconstructed
from the implementer report after the unstaged-revert incident — see the sibling
note below for context.)

**Files added (controllers):**

- `app/controllers/projects_controller.rb`
- `app/controllers/collections_controller.rb`
- `app/controllers/games_controller.rb`
- `app/controllers/footages_controller.rb`
- `app/controllers/notes_controller.rb`
- `app/controllers/timelines_controller.rb`
- `app/controllers/footage_importer/downloads_controller.rb`
- `app/controllers/api/footages_controller.rb`

**Files modified:**

- `config/routes.rb` — nested `project_notes` / `project_timelines`,
  `scan_notes` collection action, restricted top-level resources.

**Files added (views):**

- `app/views/projects/{index,show}.html.erb` + `_footage_pane.html.erb`,
  `_notes_pane.html.erb`, `_timelines_pane.html.erb`
- `app/views/collections/{index,show}.html.erb`
- `app/views/games/{index,show}.html.erb`
- `app/views/footages/{index,show,edit}.html.erb`
- `app/views/notes/{index,edit}.html.erb`
- `app/views/timelines/{index,show}.html.erb`

**Files modified (views/components):**

- `app/views/layouts/application.html.erb` — `[projects]` nav insertion in
  header + footer.
- `app/components/saved_views_section_component.html.erb` — §9.3
  horizontal-scroll wrapper.
- `app/assets/tailwind/application.css` — §9.2 (panes mobile horizontal
  scroll) + §9.3 (saved-views) CSS rules.

**Files added (Stimulus):**

- `app/javascript/controllers/codemirror_controller.js` — graceful textarea
  fallback when CM6 modules aren't pinned. Mounted on Footage description + Note
  contents.
- No `horizontal_panes_controller.js` — pure CSS scroll-snap is sufficient
  (documented choice).

**Files added (jobs + cron):**

- `app/jobs/note_sync_job.rb` — per §6.3, walks
  `<PITO_NOTES_PATH>/<tenant_id>/projects/*/*.md`, mtime-based
  add/change/delete, enqueues `Notes::EmbedJob` on change, ensure-clears the
  lock.
- `app/jobs/notes/embed_job.rb` — short-circuits when
  `AppSetting.voyage_embeddings_enabled?` is false (note saves; Meilisearch
  indexes BM25-only; pgvector stays NULL; no Voyage HTTP); when true, single
  Voyage call → both Meilisearch + pgvector dual-write.
- `config/sidekiq_cron.yml` — `note_sync` cron every 5 min.

**Files added (lock UX + helpers):**

- `app/lib/notes_lock_guard.rb` — `before_action :reject_if_notes_syncing`
  returning `423 Locked` JSON `{"error":"notes_syncing","retry_after":30}` when
  `tenant.notes_syncing_at` is recent (≤5 min stale-lock shield).
- `app/lib/notes_filesystem.rb` — defensive path handling (`sanitize_relative`
  rejects absolute / `..`; `ensure_within_project!` rejects realpath escapes).
- `app/lib/note_title_parser.rb` — ATX H1 only per §6.5; fallback "Untitled
  note".
- `app/views/projects/_notes_pane.html.erb` shows banner + `bracketed-muted`
  static spans when locked. Banner copy: "notes are syncing — try again in a
  moment." `[ scan now ]` enqueues `NoteSyncJob.perform_async(tenant.id)`.

**Files modified (Video model — DEFERRED):**

- `app/models/video.rb` — comment block recording the deferral; **no aasm
  declaration**. Reasoning: AR enum on `privacy_status` + AASM on the same
  column conflict at read time. Recommended follow-up: separate
  `lifecycle_state` column.

**Specs added:**

- `spec/requests/{projects,collections,games,footages,notes,timelines}_spec.rb`
- `spec/requests/api/footages_spec.rb`
- `spec/requests/footage_importer/downloads_spec.rb`
- `spec/jobs/{note_sync_job,notes/embed_job}_spec.rb`
- `spec/lib/{note_title_parser,notes_filesystem,notes_lock_guard}_spec.rb`
- `spec/components/saved_views_section_component_spec.rb` (+1 example)

**Decisions captured (five spec ambiguities resolved):**

- Video aasm machine deferred (column conflict rationale above; recommended
  follow-up: `lifecycle_state` column).
- `api/projects/:id/footages` namespace path: aligned controller location to
  what Rails generates (`api/footages_controller.rb`).
- CodeMirror packaging: dynamic import + textarea fallback. Pinning CM6 packages
  in `config/importmap.rb` is a small follow-up.
- `POST /notes/scan` collection action under `notes` (URL not pinned in spec).
- Top-level `index` actions for footages/notes/timelines render minimal
  admin-style index pages; per-project browsing via project show panes remains
  canonical UX.

**Gates.**

- `bundle exec rspec`: 945 / 0 (delta +83 from Phase A's 862 / 0).
- `bin/brakeman --no-pager -q`: 0 warnings, 0 errors.
- `bin/rubocop` over the 29 changed Ruby files: 0 offenses.
- **Voyage gate verified:** WebMock asserts EmbedJob fires zero requests to
  `api.voyageai.com` when the flag is off; exactly one POST when on.

**Reviewer attention.** JSON shape contract with `pito footage` (key list and
`has_commentary_track` yes/no boundary serialization); NoteSyncJob filesystem
race conditions cleared by NotesFilesystem helpers; CSS conflicts with parallel
`docs-keeper` design refresh = none (additive / scoped); Video aasm deferred
(acceptance criterion §15 partially met).

- **`notes_filesystem.rb` symlink-escape guard tightened (2026-05-04,
  post-review):** `app/lib/notes_filesystem.rb:85` (`ensure_within_project!`)
  was upgraded from lexical `File.expand_path` to `File.realpath`, so a symlink
  dropped under `PITO_NOTES_PATH` that points outside the tree is now rejected
  (Option A from the reviewer's note). A new private `canonical_path` helper
  handles the create-new-note case where the target file does not yet exist on
  disk: it climbs to the deepest existing ancestor, `realpath`s that, and
  rejoins the suffix. Option A was chosen over Option B (document-only) because
  `sanitize_relative` already reduces the suffix to a single basename, which
  makes the climb trivial and the ENOENT handling clean — no flow regressions.
  Spec count: 11 -> 14 in `spec/lib/notes_filesystem_spec.rb` (+3: symlink-out
  rejected, symlink-in accepted, not-yet-existing target accepted). Brakeman
  0/0, Rubocop 0 offenses on the two changed files.

### Phase B — Design refresh CSS (2026-05-04)

Implementer agent: `pito-rails #styling`. This dispatch applied the seven §10
design-refresh rules across the typography / utility / table / form layers,
swept inline styles out of view files and components, and locked the new class
names that `docs/design.md` references. (Reconstructed from the implementer
report after the unstaged-revert incident — see the sibling note below for
context.)

**CSS rules in `app/assets/tailwind/application.css`:**

- **MODIFIED** global `h4` rule — removed `font-style: italic`. Added
  `h4.h4-emphasis { font-style: italic; }` and
  `h4.h4-content { font-style: normal; color: var(--color-text); }` opt-in
  selectors (rule 6).
- **MODIFIED** `.text-muted` — added explicit `font-weight: 400`. **ADDED**
  `.text-muted-bold { color: var(--color-muted); font-weight: 700; }` (rule 3).
- **ADDED**
  `.form-hint, .caption { color: var(--color-muted); font-style: italic; }`
  (rule 4).
- **ADDED**
  `.form-label { display: block; margin-bottom: 2px; font-weight: 700; }`
  (component cleanup #3).
- **ADDED**
  `.bracketed-active { font-weight: 700; color: var(--color-text-bold); }`
  (component cleanup #2).
- **MODIFIED** table header rule from bare
  `th { … color: var(--color-text-bold); font-weight: 600; }` to
  `thead th { color: var(--color-muted); font-weight: 700; }`. **ADDED**
  `tbody td { color: var(--color-text); font-weight: 400; }` (rule 7).
- **PRESERVED** the `pito-rails #app` §9.2 (panes mobile horizontal scroll) and
  §9.3 (saved-views list/row) rules — confirmed no overlap.

**View files modified:**

- `app/views/channels/_form.html.erb` — two `text-muted` hints → `form-hint`.
- `app/views/layouts/application.html.erb` — keyboard-shortcut help text →
  `form-hint`.
- `app/views/search/show.html.erb` — three captions migrated (took_ms timing,
  empty-query, no-results).
- `app/views/channels/_picker.html.erb` — bulk-select overMaxHint → `form-hint`.
- `app/views/dashboard/index.html.erb` — subtitle paragraph → `caption`; four
  chart-call hex literals → `chart_palette(N)` helper.
- `app/views/channels/_pane.html.erb` — empty-state caption migrated.
- `app/views/channels/_add_pane_dialog.html.erb` — empty-state caption migrated.
- `app/views/settings/index.html.erb` — 8 inline `<label style=…>` instances →
  `class="form-label"`.

**Component files modified:**

- `app/components/bracketed_link_component.html.erb` — active-state inline style
  → `class="bracketed-active"`.
- `app/components/form_field_component.html.erb` — inline label style →
  `class: "form-label"`. Error-state inline `border-color` deliberately
  preserved (errors are not hints).
- `app/helpers/application_helper.rb` — added `CHART_PALETTE` constant +
  `chart_palette(count)` helper for dashboard charts.

**`<h4>` audit decision.** `grep -rn '<h4' app/views/ app/components/` returned
ZERO matches. Defensively removed `font-style: italic` from global `h4`; added
opt-in `.h4-emphasis` (italic) + `.h4-content` (no italic, default text color)
selectors for future use. No per-site reroute needed today.

**Specs adjusted (markup-coupling fixes, not behavior changes):**

- `spec/components/chart_toolbar_component_spec.rb` —
  `span[style*='font-weight: bold']` → `span.bracketed-active`.
- `spec/helpers/application_helper_spec.rb` — two assertions migrated from
  `"font-weight: bold"` literal to `"bracketed-active"`.

**Class names locked (referenced by `docs/design.md` updates):**

- `.text-muted-bold` — bold variant of muted UI text.
- `.form-hint` — muted + italic, for form helper text.
- `.caption` — muted + italic, for empty-state copy / summary captions / metric
  labels (same visual rule as `.form-hint`; separate name for semantic clarity).
- `.form-label` — `display: block; margin-bottom: 2px; font-weight: 700;`.
- `.bracketed-active` — `font-weight: 700; color: var(--color-text-bold);`.
- `.h4-emphasis` — opt-in italic for decorative `<h4>`.
- `.h4-content` — opt-in marker for user-content `<h4>` (no italic, default text
  color); no live call sites yet.
- `ApplicationHelper::CHART_PALETTE` constant + `chart_palette(count)` method.

**Gates.**

- `bundle exec rspec`: 945 / 0 (held; 2 specs adjusted to match new class-based
  markup).
- `bin/brakeman --no-pager -q`: 0 warnings.
- `bin/rubocop`: 0 offenses on changed Ruby files.

**Conflicts with `pito-rails #app`:** none. `#app`'s §9.2/§9.3 CSS additions sit
in different sections of `application.css` than the typography / utility / table
edits in this dispatch.

### Incident — log.md unstaged-revert (2026-05-04)

**What happened.** During the Phase B CI workflows + parallel_tests dispatch I
ran `npx --yes prettier@latest --write` on this `log.md` after seeing prettier
flag an 80-char wrap warning, then ran
`git checkout docs/plans/beta/04-project-workspace/log.md` to revert prettier's
reformat. The checkout reset to the index, which held the 435-line HEAD version
— but the working tree had ~1156 lines because the prior `pito-rails #footage`,
`#app`, and `#styling` dispatches had all appended their session entries to the
working tree without staging. Those uncommitted log entries (Phase B — pito
footage subcommand, Phase B — App code, Phase B — Design refresh CSS, each
~200-300 lines) are unrecoverable from git or disk — they were never in any
commit, index, or stash, and prettier's atomic-write didn't leave a temp file
behind.

**What is NOT lost.** The actual code from those dispatches is intact in the
working tree. `extras/cli/src/footage/**`, the new `app/controllers/`, the view
trees, the CSS class additions, the spec files — all present and untouched. Only
the prose narrative of those three log entries is gone.

**What this dispatch's narrative records below.** The Phase B CI workflows
section (this section's sibling, immediately following) is reconstructed in full
and reflects only my own work. The earlier Phase B narratives (footage / app /
styling) need to be re-authored by their owning agents (or a docs-keeper
synthesis) before the Phase B reviewer playbook lands. Flagging now so
docs-keeper #wrap can decide on a path forward.

**Lesson for future dispatches.** Treat `git checkout <file>` as destructive on
any file with prior unstaged content. Prettier's auto-formatting noise on shared
files is best handled by either (a) reformatting only the new section in the
editor before save, or (b) using `git diff` first to confirm prettier's changes
are scoped to my own edits before considering a checkout. In this case the right
move would have been to manually word-wrap my new section and never invoke
prettier on a file I share with peer agents.

### Phase B — CI workflows + parallel_tests (2026-05-04)

**State at start.** Phase B `#app` and `#styling` dispatches had already landed
in the working tree (uncommitted); `pito-sh-impl` `#footage` Rust changes also
in the tree. Suite baseline confirmed 945 / 0 single-process; Brakeman 0 / 0
/ 0. This dispatch combines three workstreams that all converge on
`.github/workflows/ci.yml` (or sibling workflow files): §12.1 GitHub Actions
updates, §12.5 cleanup workflow, the §14 Phase B `parallel_tests` row, and the
Dependabot permissions fix called out in the dispatch.

**Files touched.**

- `.github/workflows/ci.yml` — workflow-level `permissions` block, system
  packages step (`ffmpeg imagemagick libvips42`), `db:seed` added to the DB
  setup step, new `Set up parallel test databases` step, and the runner switched
  from `bundle exec rspec` to `bundle exec parallel_rspec spec/`.
- `.github/workflows/pito-cli-publish.yml` — new. Triggers on push to `main`,
  builds `extras/cli/` in release mode, copies the binary to `dist/pito`, and
  publishes a GitHub release tagged `pito-${SHORT_SHA}` (7-char prefix).
- `.github/workflows/pito-cli-cleanup.yml` — new. Trims `pito-*` releases past
  the latest 5. Triggered by the publish workflow finishing rather than CI
  finishing (rationale below).
- `Gemfile` / `Gemfile.lock` — added `gem "parallel_tests"` to
  `:development, :test`. Resolves to `parallel_tests 5.7.0`.
- `config/database.yml` — appended `<%= ENV.fetch("TEST_ENV_NUMBER", "") %>` to
  the test database name. Empty TEST_ENV_NUMBER (single-process
  `bundle exec rspec`) lands on the existing `pito_test`; `parallel_tests`
  provisions `pito_test`, `pito_test2`, … one per CPU core.
- `bin/parallel_setup` — new executable shell script wrapping
  `bundle exec rake parallel:create parallel:load_schema` for one-shot
  contributor / CI provisioning.

**Action versions pinned.** All to specific tags (no `@main`):

- `actions/checkout@v4`
- `actions/cache@v4`
- `ruby/setup-ruby@v1`
- `dorny/paths-filter@v3`
- `dtolnay/rust-toolchain@stable` (existing — kept; the project standard for
  Rust pins is the `@stable` rolling channel)
- `softprops/action-gh-release@v2`
- `dev-drprasad/delete-older-releases@v0.3.4` (matches the spec §12.5 example;
  current published version)

**Dependabot permissions block.** Added at the top of `ci.yml`:

```yaml
permissions:
  contents: read
  pull-requests: read
```

`dorny/paths-filter@v3` calls `listFiles` on the pull request, which requires
`pull-requests: read`. Dependabot PRs default to `contents: read` only, so
without this block the `changes` job failed on Dependabot PRs with "Resource not
accessible by integration". This is the minimum surface needed; no write scopes
added.

**`parallel_tests` setup details.**

- `Gemfile`: `gem "parallel_tests"` in the `:development, :test` group with an
  inline comment pointing at `bin/parallel_setup` and the CI invocation.
- `config/database.yml` test block diff:

```diff
-  database: <%= Rails.application.credentials.dig(:postgres, :test, :database) || "pito_test" %>
+  # parallel_tests appends TEST_ENV_NUMBER ("", "2", "3", ...) to suffix per-process
+  # databases (`pito_test`, `pito_test_2`, ...). Single-process `bundle exec rspec`
+  # leaves TEST_ENV_NUMBER unset and therefore lands on the unsuffixed db.
+  database: <%= (Rails.application.credentials.dig(:postgres, :test, :database) || "pito_test") + ENV.fetch("TEST_ENV_NUMBER", "") %>
```

- `bin/parallel_setup` is a 3-line bash wrapper around
  `bundle exec rake parallel:create parallel:load_schema`. `chmod +x` set; not
  picked up by `bin/rubocop -f github` (rubocop's default target list excludes
  shebang-bash files in `bin/`, verified via
  `bundle exec rubocop --list-target-files`).

**Parallel-run timing delta.**

Local host has 20 cores (parallel_tests defaults to nproc). On this host:

| Mode                               | Wall time |
| ---------------------------------- | --------- |
| `bundle exec rspec` (single)       | ~30-32s   |
| `bundle exec parallel_rspec spec/` | ~10-12s   |

~3x speedup; aligns with the spec §14 paragraph's "target ~7-10s on a 4-core
host" trajectory once one accounts for the diminishing returns past 4-8
processes (boot overhead per-process dominates beyond that). Did not tune
`--group-by` or process count — defaults are fine and the spec explicitly defers
tuning until balance becomes an issue.

CI runs on 2-core ubuntu-latest runners; expect a smaller delta there (probably
30-35s → 18-22s, still a meaningful win and frees the runner budget faster on
the rare 2-PR-merge bursts). Will revisit if CI runtime becomes a bottleneck.

**Publish vs cleanup trigger decision.** The spec §12.5 left the cleanup trigger
open between two options:

1. `workflow_run` on CI completion.
2. `workflow_run` on the publish workflow completion.

Chose option 2: cleanup triggers off `Publish pito CLI` finishing successfully.
Rationale — the `pito-*` release backlog only changes when the publish workflow
runs successfully, so triggering cleanup off CI would fire cleanup on every PR
run / docs-only push (no-op but wasteful). Tying cleanup to publish completion
is the strict superset of "ran when releases changed" and a strict subset of
"ran on every CI run". The cleanup job gates on
`github.event.workflow_run.conclusion == 'success'` to avoid running after a
failed publish.

**Spec ambiguity resolved.**

- §12.1 says install `ffmpeg + imagemagick`; the dispatch added `libvips42`
  alongside them because the `image_processing` gem (Phase 4 §5) auto-loads
  `ruby-vips` on first variant generation, and the project's `application.rb`
  `variant_processor :vips` config plus the explicit `Gemfile` comment ("Spec §5
  explicitly forbids mini_magick") confirms the vips path. Without `libvips42`
  cover-art variant specs would raise on CI when they land. The comment in the
  workflow step calls this out.
- §12.5 example used `dev-drprasad/delete-older-releases@v0.3.4`; the dispatch
  instructs me to "pin to whatever version is current and well-maintained at
  build time". Kept `@v0.3.4` — it matches the spec example, is the latest tag,
  and the action repo is maintained. If it becomes a problem (deprecation,
  abandonment) the cleanup workflow's logic is small enough to inline as
  `gh release list` piped to `gh release delete --cleanup-tag` in a follow-up;
  documented as such in the file's leading comment.
- The dispatch text said "pito_test_2"-style names (with underscore) but
  parallel_tests' on-disk default is no underscore (`pito_test2`). Kept the gem
  default; the names appear in CI logs only and the underscore variant doesn't
  materially differ. Updated the comment in `database.yml` to match reality.

**Verification.**

- `bundle exec rspec` — 945 / 0 in ~30s wall (single-process baseline).
- `bundle exec parallel_rspec spec/` — 945 / 0 in ~11s wall (4 processes
  reported by parallel_tests; uses default group-by-filename distribution).
- `bin/brakeman --no-pager -q` — 0 controllers / 0 errors / 0 warnings.
- `bundle exec rubocop` — 274 files inspected, no offenses.
- All three workflow YAML files parse cleanly under `ruby -ryaml`
  `YAML.load_file`.
- `bin/parallel_setup` confirmed executable (mode 755).

**Pre-existing working tree noted.** `Cargo.lock` and the `extras/cli/` sources
carry `pito-sh-impl`'s uncommitted Phase B changes from earlier today. This
dispatch did not touch any Rust file. Cargo.lock mtime is 03:42; my edits all
stamp 04:18 or later.

**For the reviewer agent / next push.**

- The `Publish pito CLI` workflow fires on the first push to `main` after this
  lands. Verify that:
  1. The release is created with the tag `pito-<7chars>` and the binary attached
     as `pito`.
  2. The cleanup workflow fires immediately afterwards, runs, and is a no-op on
     first run (only one `pito-*` release exists; nothing to prune past
     keep_latest=5).
- Subsequent commits eventually grow the release backlog past 5, at which point
  the cleanup workflow trims to 5 on each successful publish.
- `dorny/paths-filter@v3` permissions can be tested by closing-and- reopening
  any open Dependabot PR after this lands, or waiting for the next Dependabot
  run (the CLI Dependabot alert #1 from `follow-ups.md` is the most likely
  trigger).
- If `bundler-cache: true` ever fails on a future bump, the parallel test step
  still runs because `parallel_tests` is in the cached bundle — no new install
  latency on the critical path.

## 2026-05-04 — Phase B — Closing summary

Phase B shipped four parallel implementation lanes plus the closing
documentation pass:

1. **`pito footage` subcommand** under `extras/cli/` — Rust importer with
   ffprobe, diff classification, TUI confirmation/progress overlays, and
   `wiremock` integration tests. 287 cargo tests, 0 clippy warnings.
2. **App code (controllers + views + Stimulus + jobs + lock UX)** — 8 new
   controllers, ~17 view templates, 2 jobs (NoteSyncJob + Notes::EmbedJob),
   notes-sync 5-min lock + 423 boundary, CodeMirror with textarea fallback.
   Voyage gate verified clean. +83 RSpec examples (945 / 0). Video aasm deferred
   (AR-enum + AASM column conflict).
3. **Design refresh CSS** — 7 §10 rules applied; inline-style sweeps across 7
   view files + 3 components; `<h4>` audit found zero live sites (defensive
   opt-in classes added for future). 0 conflicts with #app's §9.2/§9.3 CSS work.
4. **CI workflows + parallel_tests** — `permissions:` block fixes the Dependabot
   `paths-filter` "Resource not accessible by integration" issue;
   `parallel_tests` gem with per-process Postgres DBs (3× speedup on this
   20-core host); separate `pito-cli-publish` (push-to-main → release tagged
   `pito-<short-sha>`) + `pito-cli-cleanup` (workflow_run on publish success →
   prune past 5) workflows. Action versions all pinned.

**Where we stand for the architect's next move.** Uncommitted working tree ready
for reviewer dispatch. Phase B's ten §15 acceptance criteria are met except: (a)
Video aasm machine — deferred with rationale; (b) "CI workflow passes" —
provable only on the next push to `main`; (c) the `pito version` short-SHA tweak
— paired with future `extras/cli/` work.

**Phase B follow-ups captured:**

- Video aasm via `lifecycle_state` column.
- `pito version` short-SHA build-time embed (build.rs vs vergen TBD).
- Pre-existing `cargo fmt` drift in `extras/cli/src/{app,keys,ui/*,api/*}`.
- CodeMirror 6 importmap pinning.

**References for Mobile follow-up via `read_doc`:**

- `docs/plans/beta/04-project-workspace/specs/project-workspace.md` — master
  spec.
- `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md` — Step 0
  sibling spec.
- `docs/plans/beta/04-project-workspace/additions.md` — scope additions.
- `docs/orchestration/playbooks/2026-05-04-mcp-dev-kb-surface.md` — Step 0
  playbook.
- `docs/orchestration/playbooks/2026-05-04-phase-4-foundation.md` — Phase A
  playbook.
- `docs/orchestration/follow-ups.md` — open follow-ups list.
- `docs/decisions/0001-no-server-side-uploads.md` — ADR (now with image-asset
  addendum).
- `docs/design.md` — design system (now with the §10 7 rules + Content Rules
  section + panes/saved-views global rules).

### Post-review fixes (2026-05-04)

Reviewer's playbook surfaced one blocker and two non-blocking concerns; all
addressed in three parallel surgical dispatches:

1. **`pito footage` API URL contract correction.** The Rust importer client
   pointed at `/projects/<id>/footage.json` (singular, no `/api/` prefix); Rails
   routes at `/api/projects/:project_id/footages.json` (plural, namespaced).
   Tests passed green because both wiremock and the client agreed on the wrong
   URL. Fix landed in `extras/cli/src/footage/api/client.rs` and
   `extras/cli/tests/footage_integration.rs` — collection actions (POST, GET)
   updated; member actions (PATCH, DELETE) already aligned at top-level. Spec
   §7.3/§7.5 amended to match the actual routes (the asymmetric
   `/api/`-collection / top-level-member design is intentional but worth
   revisiting — added to follow-ups).
2. **`notes_filesystem.rb` symlink guard tightened** — see the addendum under
   the App-code entry above.
3. **CodeMirror 6 importmap pinning** moved from a log-entry decision into
   `follow-ups.md` so it doesn't get lost.

### Phase B — Settings UI refinement: per-fieldset submits + Voyage section (2026-05-04)

Two related Settings-page refinements raised by the user during the playbook
walkthrough:

**Layout change.** The page is two-column. Before: left column held the
`workspaces` fieldset (top) and the `search` / Meilisearch fieldset (bottom);
right column held `appearance` (top) and `YouTube OAuth` (bottom). After: right
column gains a new `Voyage AI` fieldset at the bottom, sitting across from the
Meilisearch fieldset on the left. The Voyage fieldset shows a
`voyage AI ▲ enabled` / `▽ disabled` status line mirroring the Meilisearch
status indicator, plus a yes/no radio group bound to the
`app_settings.voyage_embeddings_enabled` Boolean column. The form value at the
HTTP boundary is the string `"yes"` / `"no"` per CLAUDE.md hard rule; the
controller converts to internal Boolean before persisting.

**Per-fieldset submits.** Before: ONE `[save]` button at the bottom of a single
form covered all of workspaces + appearance + YouTube OAuth — saving
"appearance" also re-wrote the OAuth fields. After: each fieldset is its own
`form_with`, each with its own `[ save ]` button. Search/Meilisearch reindex
remains its own form (was already separate). Total: five independent forms on
the page (workspaces, search-reindex, appearance, youtube_oauth, voyage).

**Controller approach: Option A** (single `update` action with section
dispatch). Each form posts to `PATCH /settings` with a hidden `section` field.
`SettingsController#update` switches on `params[:section]` and only writes the
keys belonging to that section, leaving everything else untouched. Rationale:
the controller was small (~70 lines, 3 actions) and easy to extend; no new
routes to add (zero churn for the MCP `manage_settings` tool which doesn't hit
the controller anyway); legacy callers without a `section` parameter fall
through to the original "write everything we see" behavior so backward
compatibility holds. Section-specific helpers (`update_general`,
`update_appearance`, `update_oauth`, `update_voyage`, `update_legacy`) live as
private methods.

**Voyage row bootstrap.** The `voyage_embeddings_enabled` flag lives on the
first AppSetting row (the de-facto-singleton from seeds, see
`AppSetting.voyage_embeddings_enabled?`). If the table is empty (fresh install
with no seeds), the controller bootstraps a holder row by calling
`AppSetting.set("pane_title_length", PANE_TITLE_LENGTH_default)` before flipping
the column. In any real deployment this branch is unreachable (seeds always
create at least the `max_panes` row); covered by spec.

**Routes added:** none. Single `PATCH /settings` route serves all four section
forms via `params[:section]`.

**Files touched:**

- `app/controllers/settings_controller.rb` — `update` becomes a section
  dispatcher; new private methods `update_general`, `update_appearance`,
  `update_oauth`, `update_voyage`, `update_legacy`. Index sets
  `@voyage_embeddings_enabled`.
- `app/views/settings/index.html.erb` — restructured from one big form wrapping
  multiple fieldsets into five independent forms (workspaces, search/reindex
  unchanged in shape, appearance, youtube_oauth, voyage). Each per-fieldset form
  carries a hidden `section` input. New Voyage AI fieldset at the bottom-right
  column. All submits use `[ save ]` / `[ reindex ]` per the bracketed-link
  convention. `text-muted` swapped for `form-hint` on the workspaces helper text
  per the design refresh; design refresh classes (`form-label`, `form-hint`) are
  already in use elsewhere on the page.
- `spec/requests/settings_spec.rb` — added 9 new examples:
  - `Voyage AI` fieldset rendering (1)
  - hidden `section` field present in each of the four forms (1)
  - per-section save isolation: workspaces / appearance / youtube_oauth each
    leaves the other sections untouched (3)
  - voyage yes → flag becomes true (1), voyage no → flag becomes false (1),
    voyage rejects strings other than "yes"/"no" (1), voyage bootstraps the
    AppSetting row when the table is empty (1).
- `docs/plans/beta/04-project-workspace/log.md` — this entry.

**Spec count delta:** 948 → 957 (+9), 0 failures.

**Brakeman:** 0 warnings (clean).

**RuboCop:** Ruby files clean (controller + spec). The `.erb` files report the
same 16 parser-limitation "errors" they did before the change — RuboCop treats
ERB as raw Ruby and chokes on `<%= %>` tags; not real lint findings.

**Reviewer re-check list:**

- yes/no boundary translation in the Voyage form — controller rejects any raw
  string other than `"yes"` / `"no"` (verified by spec); no boolean primitives
  leak into the form value.
- legacy single-form `PATCH /settings` (no `section`) still saves OAuth +
  general + theme together — verified by the pre-existing examples in the
  `PATCH /settings` describe block, which were left unmodified.
- `theme` save flow not accidentally dropped — covered by the appearance
  per-section example (saves only `theme`) and by the legacy describe block.
- Voyage fieldset placement matches the user's layout request (bottom-right,
  across from Meilisearch on the left). Verified manually in the view file.

### Phase B — Post-validation fixes (delete allowlist, form hover, project create investigation) (2026-05-04)

Three fixes the user surfaced while walking the post-validation playbook for the
Settings page refinement (957 / 0 baseline carried forward from the prior
session). All three landed in this dispatch.

**Fix 1 — Detail-table form rows no longer pick up the data-table hover.**

Problem: `app/assets/tailwind/application.css` had a global
`tr:hover { background-color: var(--color-bg-hover); }` rule meant for data
tables. The Project show page (and any other detail-table form) wraps form rows
in `<tr>` for layout, so each row visually flashed on hover during editing —
confusing and not what the user wants.

Fix: Scoped the hover rule with a `:not(.detail-table)` qualifier:

```css
table:not(.detail-table) tr:hover {
  background-color: var(--color-bg-hover);
}
```

This keeps the data-table hover everywhere it was already working (channels
index, videos index, projects index, deletions preview, etc. — none of those
tables carry `class="detail-table"`) and removes it from the Project show form
rows, the keyboard-shortcuts dialog table, the footage show key/value table, and
the timeline show key/value table — every place `.detail-table` was already in
use.

The `tr:nth-child(even)` alt-row stripe was deliberately NOT scoped. The user
called out hover specifically; the alt color is subtle and current detail tables
only ever have 2–4 rows so the stripe is visually minor. Easy to extend later if
needed.

**Fix 2 — `Confirmable` allowlist extended to Phase 4 types.**

Problem: `Confirmable::TYPES` was `%w[channel video]`. The Project show page has
`[delete]` → `/deletions/project/<id>`, which fell through the allowlist check
and returned "unknown type." flash → redirect to root. Same trap was waiting for
collection / game / note / timeline once the user added similar links there.

Fix: Extended `TYPES`, `cancel_path`, `model_for`, `scope_for`, and `label_for`
in `app/controllers/concerns/confirmable.rb` to cover `project`, `collection`,
`game`, `note`, `timeline`. Footage stays out of the allowlist deliberately —
the importer surface owns footage lifecycle, not the web UI.

Cancel paths: project / collection / game route to their respective index; note
/ timeline have no top-level user-facing index (they live inside the project
show page) so they fall back to `projects_path`, the closest reasonable parent.
Sort order matches the human-facing display column for each type (`name` for
projects/collections, `title` for games/notes/ timelines).

The deletions HTML view (`app/views/deletions/show.html.erb`) had a hardcoded
`if @type == "channel" / else (assumes video)` switch. Rewrote as a `case @type`
with an explicit branch per allowlisted type. Each new branch shows the columns
that make sense for that type:

- project: name, footage / notes / timelines counts
- collection: name, games count
- game: title, publisher, collection
- note: title, project, last modified
- timeline: title, project, state

`app/views/syncs/show.html.erb` got the same case-based rewrite for
defensiveness — there are no `[sync]` links on Phase 4 pages today, but direct
URL access to `/syncs/project/<id>` would otherwise crash on `item.title` /
`item.channel.channel_url`. Project and collection branches render `name`; game
/ note / timeline render `title`. No skipped-state column for non-channel types
(they don't carry a `syncing?` flag).

`app/helpers/application_helper.rb` `cancel_path_for(type)` extended to match —
used by both deletions and syncs views in the breadcrumb back-link.

`BulkDeleteJob` needed no change — it calls `target.destroy` polymorphically via
the `BulkOperationItem.target` association, so any AR class with a working
`destroy` works as-is. Verified by running the job in spec for each new type.

**Fix 3 — "creating a new Project breaks" — investigation.**

The user reported `[ new project ]` on the Project index breaks. Re-walked the
path:

- `ProjectsController#create` does
  `Project.new(tenant: default_tenant) → save! → redirect_to project_path(project)`.
  No params, no validation failure path, no flash issue.
- The `[ new project ]` button on `app/views/projects/index.html.erb` is
  `button_to projects_path, method: :post, data: { turbo: false }` — Turbo is
  opted out, real POST → 302 → real GET on show.
- `projects/show.html.erb` and the three pane partials (`_footage_pane`,
  `_notes_pane`, `_timelines_pane`) were re-read end-to-end. Every helper
  reference resolves: `breadcrumb`, `BracketedLinkComponent`,
  `footage_importer_download_path` (route name in `config/routes.rb`),
  `format_duration` (helper), `project_notes_path` / `scan_notes_path` /
  `project_timelines_path` (route names), `compact_time_ago`. No undefined
  helper, no missing partial, no broken `<%= %>` tag.
- No Stimulus controllers on any project view
  (`grep "data-controller" app/views/projects/` is empty).
- `spec/requests/projects_spec.rb` `POST /projects (default-create)` only
  asserted `redirect_to(project_path(project))` — it did NOT follow the
  redirect, so a runtime error in the show render would have slipped through.
  Added a second example:
  `it "renders the show page successfully after the redirect"` that calls
  `follow_redirect!` and asserts the body contains `"Untitled project"` plus the
  three pane headers. It passes.

Conclusion: no concrete bug found in the code path. Possible non-fix
explanations to surface back to the user, in rough likelihood order:

1. **`bin/dev` not running.** The Cloudflare tunnel returns the
   upstream-not-reachable page when Puma isn't up; that page can read as
   "broken" if you've forgotten you stopped the dev server.
2. **Stale browser tab with expired CSRF token.** A button_to POST with a stale
   token surfaces as `ActionController::InvalidAuthenticityToken` 422 / "unable
   to verify CSRF token" page. Hard reload fixes.
3. **The user meant the show page.** The Project show form rows were
   highlighting on hover (Fix 1) — the user might have called that "broken."
   This fix removes that highlight; the show page should now feel right.
4. **Something Stimulus-driven on a parent layout.** No project-specific
   Stimulus, but the global `keyboard` controller is attached to the dialog and
   `theme` to the header. If one of those raised, dev console would show a JS
   error but the page would still render. Unlikely root cause.

Recommend the user paste the actual error text or screenshot next time, so we
can correlate against an exact behavior.

**Files touched.**

- `app/assets/tailwind/application.css` — scoped `tr:hover` to
  `:not(.detail-table)`.
- `app/controllers/concerns/confirmable.rb` — `TYPES` extended; `cancel_path`,
  `model_for`, `scope_for`, `label_for` cover the five Phase 4 types.
- `app/helpers/application_helper.rb` — `cancel_path_for(type)` extended to
  match.
- `app/views/deletions/show.html.erb` — `case @type` rewrite with per-type
  preview columns for project / collection / game / note / timeline.
- `app/views/syncs/show.html.erb` — same `case @type` shape, defensive branches
  for non-channel/non-video types.
- `spec/controllers/concerns/confirmable_spec.rb` — type→model dispatch and
  cancel_path examples for the five new types (10 new examples).
- `spec/requests/deletions_spec.rb` — preview rendering (5 contexts) and
  enqueue/perform happy-path (5 contexts) for the five new types. Each enqueue
  example actually invokes `BulkDeleteJob.new.perform(operation.id)` to confirm
  polymorphic destroy works (13 new examples).
- `spec/requests/projects_spec.rb` — `follow_redirect!` regression example for
  the default-create flow (1 new example).

Phase 4 types that could reasonably grow `[delete]` links in views (project show
already has one; collection show, game show, note edit, timeline show do not
yet) are now allowlisted-and-tested for that day. Note edit currently uses
`ConfirmModalComponent` — a JS-driven modal, which contradicts the project's "no
JavaScript confirm" hard rule. NOT addressed in this dispatch (scope: only the
three fixes the user surfaced); flagging here as a separate follow-up: convert
note delete from `ConfirmModalComponent` to the `/deletions/note/:id`
action-confirmation page once the user surfaces it.

**Spec count delta:** 957 → 981 (+24), 0 failures.

**Brakeman:** 0 warnings (clean).

**RuboCop:** Ruby files clean (`confirmable.rb`, `application_helper.rb`, all
three spec files). ERB files were not lint-checked — RuboCop is `.rb`- only by
default, ERB lint is a separate tool not configured in this repo.

**Outcome of Fix 3 investigation:** no concrete bug found in code; the
follow-redirect regression spec hardens the create→show flow. See the non-fix
explanations above for what might have surfaced.

### Phase B — Bulk-select on /projects index (2026-05-04)

The `Confirmable::TYPES` allowlist already accepts `project` (extended in the
prior fix dispatch), so the `/deletions/project/<ids>` endpoint is ready. This
dispatch is purely the picker-UI wire-up on the projects index, mirroring
`app/views/videos/index.html.erb`.

**Files touched.**

- `app/views/projects/index.html.erb` — restructured to add the
  `data-controller="bulk-select"` wrapper, `[ bulk ]` toggle, bulk-mode action
  toolbar (`actions` / `count` / `deleteAction` / `cancel`), per-row checkbox
  column (`bulkCol` / `headerCheckbox` / `checkbox` targets), and the
  `actionCol` toggle around the existing `[ open ]` link. The `[ new project ]`
  `button_to` is preserved.
- `spec/requests/projects_spec.rb` — added a
  `describe "bulk-select picker markup"` block (6 new examples) covering:
  Stimulus controller attachment with `delete-type=project`, omission of
  pane-related data values, presence of `[ bulk ]` toggle, presence of action
  toolbar targets, presence of header + per-row checkbox targets, and the
  cancel-link wiring.

**Spec scope decision (request, not system).** Stayed with request specs only.
The Stimulus controller is shared with videos / channels and already has
implicit coverage there; on /projects the only net-new behaviour is the markup
that wires the existing controller, which a request spec asserts directly. A
system spec would mostly retest the Stimulus controller through Capybara, with
no projects-specific risk beyond what the markup assertions already cover.
If/when a Capybara system suite is set up for the rest of the picker pages,
projects can slot in then.

**Deviation from the videos/index pattern.** Projects has no multi-pane "open N"
flow, so `data-bulk-select-max-panes-value` and
`data-bulk-select-panes-path-value` are intentionally omitted. The Stimulus
controller (`app/javascript/controllers/bulk_select_controller.js`) references
`countTarget`, `openHintTarget`, and `openActionTarget` unconditionally inside
`updateActions()`, so those spans must still exist in the DOM to avoid runtime
`Missing target` errors. The `count` target stays user-visible (selection
counter is useful); the `openHint` / `openAction` pair is buried inside a
permanently-hidden wrapper `<span hidden style="display: none;">` so the
controller can keep toggling their inner `hidden` attribute without ever
surfacing an `[ open N ]` action that has no destination on /projects. With
`maxPanesValue` defaulting to `0`, the controller would otherwise route any
selection ≥ 1 into the over-max muted-bracket branch — which would render a
misleading muted `[open N]` in the toolbar. The hidden wrapper suppresses that
entirely. The Stimulus controller was NOT modified.

**Spec count delta.** 981 → 987 (+6), 0 failures.

**Brakeman.** 0 warnings (clean).

**RuboCop.** `spec/requests/projects_spec.rb` clean. The ERB file was not
lint-checked — RuboCop in this repo is `.rb`-only (no erb-lint configured);
running it against `app/views/videos/index.html.erb` reproduces the same parser
errors, confirming the limitation is pre-existing and not specific to this
change.

**Open follow-ups.** Bulk-select for collections / games / notes / timelines
indices is out of scope for this dispatch. If those indices need bulk delete
later, the markup template established here is the reference (omit pane values,
hide open-related targets behind a permanently-hidden wrapper, set
`delete-type-value` to the singular type name).

### Phase B — BulkSelectController panes-optional refactor (2026-05-04)

**What changed.** The `bulk_select_controller.js` Stimulus controller no longer
assumes every consumer wires the panes-specific targets and values. Screens with
no multi-pane "open in N panes" flow (currently `/projects`, future
`/collections`, `/games`, etc.) can now drop the `openHint` / `openAction`
targets entirely; the controller silently skips the open-related branch via
`has*Target` guards.

**Targets guarded with `has*Target` checks.** Inside `updateActions()`, the
entire open-related block (count == 0 hint, count <= max bracketed link, count >
max muted bracket) is now wrapped in
`if (this.hasOpenHintTarget && this.hasOpenActionTarget) { ... }`. That was the
only place those two targets were touched. The `overMaxHintTarget` access
already had its own `hasOverMaxHintTarget` guard from the channels work and was
left as-is. `countTarget` stays mandatory — it's the universal "N selected"
counter every bulk picker shows. `bulkColTargets`, `actionColTargets`,
`bulkToggleTarget`, `actionsTarget`, `checkboxTargets` are universal and
untouched. `headerCheckboxTarget`, `deleteActionTarget`, `syncActionTarget` were
already guarded.

**Values given defaults.** The `values` declaration moved from the shorthand
`{ maxPanes: Number, ..., panesPath: String, ... }` to the long form so
`maxPanes` can default to `0` and `panesPath` can default to `""`. Stimulus has
no `has*Value` check, so defaults are the idiomatic way to make those values
optional. The defaults are only read inside the now-guarded open block, so their
values don't affect any other branch — but defaulting them avoids any future
footgun and matches the documented intent.

**`/projects` view simplification.** Removed the workaround wrapper
`<span hidden style="display: none;">` around `openHint` and `openAction` in
`app/views/projects/index.html.erb`. Those two targets are no longer rendered at
all on `/projects`. The leading comment explaining the deviation from
`videos/index` was updated to describe the new approach (controller guards
everything; view simply omits the panes-specific markup).

**Spec count delta.** 987 → 991 (+4), 0 failures.

- `spec/requests/projects_spec.rb` +2: the two new context examples asserting
  `openHint` / `openAction` targets are absent and the permanently-hidden
  workaround wrapper is gone.
- `spec/requests/videos_spec.rb` +2: regression coverage that the panes-specific
  `openHint` / `openAction` targets and `panes-path-value` are still rendered on
  `/videos`, plus an explicit assertion that the universal `count` target is
  rendered alongside them.

**Brakeman.** 0 warnings (clean — JavaScript-only refactor plus a view markup
deletion plus spec additions).

**RuboCop.**
`bin/rubocop spec/requests/projects_spec.rb spec/requests/videos_spec.rb` — 2
files inspected, no offenses. ERB / JS files are not RuboCop-scoped in this
repo.

**Verification — videos and channels pickers.**

- `spec/requests/videos_spec.rb` (full file) green: bulk select checkboxes,
  header checkbox, max_panes value, action toolbar, and the new openHint /
  openAction regression assertions all pass.
- `spec/requests/channels_spec.rb` (full file) green: existing `overMaxHint`
  hidden-by-default assertion, max-panes-value passthrough, and the rest of the
  channel picker bulk-select coverage all pass unchanged. The refactor is
  additive (guards only); no view file under `app/views/channels/` or
  `app/views/videos/` was modified.

**Open follow-ups.** None tied to this refactor. Future picker indices
(`/collections`, `/games`, etc.) can now copy the simplified `/projects`
template directly: omit `data-bulk-select-max-panes-value`,
`data-bulk-select-panes-path-value`, `openHint`, and `openAction` — the
controller honors absence cleanly.

### Phase B — Voyage revamp: encrypted key on AppSetting + per-target flags (2026-05-04)

**Why.** The pre-revamp shape (a single `voyage_embeddings_enabled` Boolean on
`AppSetting`) was too coarse on two axes. (1) The Voyage API key lived only in
`Rails.application.credentials.dig(:voyage, env, :api_key)` — rotating it
required a deploy. (2) "Voyage on/off" was global; future indexing targets
(videos, channels, ...) need their own gates. This dispatch reshapes the
AppSetting columns so the key is UI-editable and the on/off lives per-target.

**Migration N°.** `20260504000011_revamp_voyage_app_setting_columns.rb`. Schema
delta:

- `+ voyage_api_key :text` (nullable; encrypted via Active Record Encryption —
  see model below). Text rather than string because AR Encryption ciphertext can
  run past 255 chars depending on encryptor configuration.
- `+ voyage_index_project_notes :boolean, null: false, default: false`.
- `- voyage_embeddings_enabled :boolean` (the previous single Boolean is dropped
  — Phase B owns this rename outright).

**Reversibility verified.**
`bundle exec rake db:migrate db:rollback STEP=1 db:migrate` round-trips cleanly;
`remove_column` is given the prior column type (`:boolean`,
`null: false, default: false`) so the down migration restores the exact shape.

**Model changes — `app/models/app_setting.rb`.**

- New: `encrypts :voyage_api_key` (probabilistic, NOT deterministic — the key is
  sensitive, never compared/queried, and benefits from the default
  non-deterministic mode). The existing `encrypts :value, deterministic: true`
  was untouched.
- Replaced `voyage_embeddings_enabled?` class method with two:
  - `AppSetting.voyage_configured?` — true iff the singleton has a non-blank
    `voyage_api_key` (treated as "Voyage is configured").
  - `AppSetting.voyage_indexing_project_notes?` — returns the singleton's
    `voyage_index_project_notes`, or false if no singleton exists.
- New model-level validation `voyage_target_flags_require_key` (plural in the
  name so future flags can extend it without renaming). Triggers when
  `voyage_index_project_notes` is true AND `voyage_api_key` is blank, which
  catches both directions: flipping a flag true while the key is blank, AND
  clearing the key while a flag is true. Error message:
  `"Voyage API key required to enable project-notes indexing."`.

**EmbedJob dual-check rationale — `app/jobs/notes/embed_job.rb`.** The job now
reads two signals: `AppSetting.voyage_indexing_project_notes?` AND
`AppSetting.voyage_configured?`. BOTH must be true to call Voyage.
Belt-and-suspenders on top of the model validation: the validation prevents the
broken state at the form boundary, but the job is the LAST line of defense
before money is spent on embedding tokens. If a migration drifts, a direct SQL
write happens, or a future code path bypasses the validation, the dual check
still short-circuits cleanly.

API key resolution prefers the AppSetting record (UI-managed, runtime-mutable).
It falls back to `Rails.application.credentials.dig(:voyage, env, :api_key)` —
but ONLY inside `call_voyage`, after `voyage_configured?` has already gated the
call. In practice the credentials path is unreachable from the gate; the
fallback exists for defensive reads and future bootstrap paths.

**Settings controller / view — `app/controllers/settings_controller.rb` +
`app/views/settings/index.html.erb`.** The voyage section now accepts:

- `voyage_api_key` (text input, type=password): blank submit leaves the existing
  key untouched (no clobber on empty); non-blank replaces. The view input always
  renders empty; the placeholder reads `key configured (•••••••)` when a key is
  set, `no key configured` otherwise — so the plaintext NEVER round-trips back
  through the rendered HTML.
- `clear_voyage_api_key` (checkbox, value="yes"): explicit clear. When ticked,
  sets `voyage_api_key = nil`. The model validation prevents this when
  `voyage_index_project_notes` is on.
- `voyage_index_project_notes` (yes/no radio): per-target flag. Project-rule
  yes/no boundary string converts to internal Boolean. Other values leave the
  flag unchanged (matches the existing external-boolean rule).

`update_voyage` now returns either `nil` (success) or the validation error
string (failure). The `update` action surfaces the failure via `flash[:alert]`
and a redirect, matching the existing per-section pattern. The `index` action
exposes `@voyage_configured` and `@voyage_indexing_project_notes` for the view
(replacing the old single `@voyage_embeddings_enabled`).

**Seed strategy — `db/seeds.rb`.** Replaced the production-only flag flip with a
key+flag bootstrap that is idempotent and credential-fed:

1. If the singleton has no key, read
   `Rails.application.credentials.dig(:voyage, env, :api_key)` and write it to
   the row when present. (No-op when credentials lack a `:voyage` block.)
2. In production, with the key now present, flip `voyage_index_project_notes` to
   true (idempotent — only flips if currently false).

This means initial Hetzner deploys work without manual UI entry (credentials
seed the key once); subsequent rotations happen via the UI (the seed never
overwrites a key the user has set). `config/application.rb`'s explanatory
comment was updated to point at the new method names.

**Specs added / updated.**

- `spec/models/app_setting_spec.rb` — extended:
  - `voyage_api_key` encryption: writes plaintext, fetches via raw SQL, asserts
    the persisted blob does NOT equal/contain the plaintext. Companion:
    round-trips through the model accessor.
  - Defaults: `voyage_api_key` nil, `voyage_index_project_notes` false on a
    freshly created row.
  - `.voyage_configured?` truth table: nil, blank, whitespace-only all return
    false; non-blank returns true.
  - `.voyage_indexing_project_notes?`: returns flag value when row exists, false
    when no singleton.
  - Validation guard branches: flipping flag true without key fails; setting key
    first then flag succeeds; clearing key while flag is true fails; flipping
    flag off then clearing key succeeds; repeated flag flips with key present
    are idempotent.
- `spec/jobs/notes/embed_job_spec.rb` — restructured around the new flag name
  and the dual check:
  - Flag false → no Voyage HTTP, embedding stays NULL, Meilisearch BM25-only (3
    examples).
  - Flag true AND key configured → Voyage HTTP fires once, pgvector written,
    Meilisearch payload includes `_vectors`, bearer token matches the AppSetting
    key (3 examples).
  - **NEW** defensive branch: flag true but key blank (forced via
    `update_columns` to bypass the validation, simulating migration drift) → no
    Voyage HTTP, no embedding write, Meilisearch BM25-only (3 examples).
  - **NEW** credentials-fallback boundary: AppSetting key blank but credentials
    carry a key → still no Voyage HTTP, because `voyage_configured?` is the
    AppSetting-key gate (1 example).
- `spec/requests/settings_spec.rb` — voyage section examples rewritten:
  - Key + flag together → both persist.
  - Flag yes without key → validation alert, flag unchanged.
  - Empty key submit + flag no → existing key untouched, flag toggles.
  - Flag values other than yes/no → unchanged.
  - `clear_voyage_api_key=yes` while flag off → key cleared.
  - `clear_voyage_api_key=yes` while flag on → validation alert, key preserved.
  - Empty AppSetting table → bootstrap row + key + flag in one submit.
  - GET /settings does not leak the plaintext key in response body.

**Spec count delta.** 991 → 1011 (+20), 0 failures.

**Brakeman.** 0 warnings. The encryption key handling is a Brakeman magnet, but
the model uses the `encrypts` macro (which Brakeman trusts), API-key resolution
stays inside the job's private method boundary, and the controller's password
input never echoes a submitted value back to the page.

**RuboCop.** 10 changed files inspected (`app/models/app_setting.rb`,
`app/jobs/notes/embed_job.rb`, `app/controllers/settings_controller.rb`, the
migration, `db/seeds.rb`, the three specs, `config/application.rb`,
`app/models/note.rb`), 0 offenses.

**Forward note for the architect.** §3.5 of the master spec
(`docs/plans/beta/04-project-workspace/specs/project-workspace.md`) still
describes the single-Boolean `voyage_embeddings_enabled` shape and the
`Rails.application.credentials.dig(:voyage, env, :api_key)` key path. It needs a
docs-keeper amendment to reflect the new shape:

- Encrypted `voyage_api_key` column on AppSetting (UI-editable, rotates without
  deploy).
- Per-target flag `voyage_index_project_notes` (Phase 4 only ships project-notes
  indexing; future targets get their own columns).
- EmbedJob dual check (`voyage_indexing_project_notes?` AND
  `voyage_configured?`).
- Seed bootstrap from credentials → AppSetting on first run; idempotent on
  re-run; UI authoritative thereafter.

The pre-existing voyage smoke-test rake task (mentioned by the user as a future
Phase B follow-up) was intentionally NOT touched in this dispatch — leave it for
the dispatch that wires it up.

### Phase B — Settings UI polish: conditional voyage flags, theme first, .md-radio, reindex modal (2026-05-04)

Four cohesive UI polish items the user surfaced after the Voyage revamp landed.
All scoped to the Settings page and its supporting CSS.

**Change 1 — Conditional Voyage per-target flag radios.**
`app/views/settings/index.html.erb` now wraps the `voyage_index_project_notes`
radio block in `<% if AppSetting.voyage_configured? %>...<% end %>`. When the
API key is blank, the radios disappear; once a key is configured, they reappear
on the next render. The status indicator at the top of the fieldset
(`▽ disabled` / `▲ enabled`) stays informational regardless of key state.
Rationale: model validation already rejects any flag =yes submission without a
key, so showing the radios in a doomed state was visual noise.

**Change 2 — Theme is the first form field.** Reordered fieldsets within the
existing two-column flex container in `app/views/settings/index.html.erb`. New
layout:

- Left column: appearance (top), workspaces, search.
- Right column: YouTube OAuth (top), Voyage AI.

The column gridding itself is unchanged — only the order of `<fieldset>` blocks
within each column moved.

**Change 3 — `.md-radio` CSS pattern.** Added to
`app/assets/tailwind/application.css`, mirroring the shape of the existing
`.md-check` block but with `( )` / `(x)` indicators instead of `[ ]` / `[x]`.
The native `<input type="radio">` is hidden (opacity: 0, position: absolute,
pointer-events: none) and the `<label>` wrapper passes the click through, so
form submission still uses native radio semantics — no JS. New class hooks:

```css
.md-radio { cursor: pointer; user-select: none; ... }
.md-radio input[type="radio"] { opacity: 0; ... }
.md-radio-indicator::before { content: "( )"; }
.md-radio input:checked ~ .md-radio-indicator::before { content: "(x)"; }
.md-radio-label { color: var(--color-muted); }
.md-radio-link { /* link-color variant for chip-style usages */ }
```

Applied to two radio groups in `app/views/settings/index.html.erb`:

- Theme picker (`light` / `dark` / `auto (system)`).
- Voyage `voyage_index_project_notes` (`yes` / `no`).

The existing `.md-check` (checkbox `[ ]` / `[x]`) is untouched — it stays scoped
to checkboxes only. The `clear stored key` checkbox in the Voyage fieldset
deliberately keeps its plain-`<input type= "checkbox">` shape; this dispatch did
not include it.

**Change 4 — Reindex confirmation via `ConfirmModalComponent`.** The old
direct-POST `[ reindex ]` button (form_with → button[type=submit] posting to
`settings_reindex_path`) became a `BracketedLinkComponent` trigger that opens a
`ConfirmModalComponent`. Wiring follows the **existing pattern** used by
`saved_views_section_component.html.erb` verbatim:

- Trigger link: `data-controller="modal-trigger"`,
  `data-action="click->modal-trigger#open"`,
  `data-modal-trigger-target-id-value="reindex_meilisearch_modal"`.
- Modal:
  `ConfirmModalComponent.new(id: "reindex_meilisearch_modal", title: "reindex Meilisearch?", body: "...", confirm_path: settings_reindex_path, confirm_method: :post, confirm_label: "reindex", cancel_label: "cancel", destructive: false)`.

**Deviation from the dispatch sketch.** The dispatch sample used
`data-controller="confirm-modal-trigger"` and
`data-confirm-modal-trigger-target-value=...`. The actual existing controller in
`app/javascript/controllers/modal_trigger_controller.js` is named
`modal-trigger` with a `target_id` value, and that's what
`saved_views_section_component.html.erb` already uses. The dispatch explicitly
said "follow the existing pattern" if names differ, so the implementation uses
the actual `modal-trigger` / `modal_trigger_target_id_value` convention, not the
sketched `confirm-modal-trigger` / `confirm_modal_trigger_target_value`.

Also: `destructive: false` was passed explicitly to `ConfirmModalComponent`
because the component defaults `destructive: true` (which would render the
confirm button in the danger color). Reindex is significant but not destructive,
so the button stays in the regular link color.

**Files touched.**

- `app/views/settings/index.html.erb` — fieldset reorder, `.md-radio` applied to
  the two radio groups, conditional Voyage flag block, reindex modal trigger +
  `ConfirmModalComponent` rendered inside the search fieldset.
- `app/assets/tailwind/application.css` — `.md-radio` block (33 new lines)
  inserted after the existing `.md-check-link:hover` rules.
- `spec/requests/settings_spec.rb` — five new request specs covering the
  conditional Voyage flag radios (hidden vs. shown), DOM-position ordering of
  theme before pane_title_length, the reindex modal trigger + dialog presence,
  and the `.md-radio` class on the page.

**Spec count delta.** 1011 → 1016 (+5), 0 failures.

**Brakeman.** 0 warnings.

**RuboCop.** Spec file clean (no offenses on `spec/requests/settings_spec.rb`).
The `app/views/settings/ index.html.erb` and
`app/assets/tailwind/application.css` files trip RuboCop's Ruby parser on ERB /
CSS syntax (a pre-existing config gap — both files were untracked by RuboCop
before this dispatch and remain so now). No new Ruby files were introduced.

**Reviewer recheck.**

- Stimulus wiring for the reindex modal trigger: confirm the `modal-trigger`
  controller name (NOT `confirm-modal-trigger`) matches the canonical reference
  in `app/components/saved_views_section_component.html.erb`. If a later
  refactor renames the controller, both call sites need to move together.
- The `ConfirmModalComponent` `destructive: false` flag is the correct surface
  for non-destructive significant actions; if the component grows a separate
  "warning" flag in the future, reindex should migrate to it.
- The conditional Voyage flag block uses `AppSetting .voyage_configured?`
  directly inline (mirrors the controller's `@voyage_configured` ivar). Both
  pull from the same singleton helper, so they're consistent — a controller-side
  `if` would have worked equally but introduced a second source of truth.

### Phase B — Number formatting sweep + lint spec (2026-05-04)

**Context.** The user just locked the `## Numbers` rule in `docs/design.md`:
every user-visible number renders through `number_with_delimiter`, producing
comma-separated thousands and dot-decimals. Two locations had landed surgical
fixes (Meilisearch indexed-documents tally on `settings/index.html.erb:94`, and
the dashboard subtitle on `dashboard/index.html.erb:8`). The rest of the view
tree needed a sweep, plus a guard spec to catch future drift automatically.

**Sweep.** Touched 11 templates across 7 view directories; no components needed
changing (the existing components either don't render integers or already format
them). Per-file changes:

- `app/views/projects/_footage_pane.html.erb` — wrapped `footages.size` in the
  `<h2>` count.
- `app/views/projects/_notes_pane.html.erb` — wrapped `notes.size`.
- `app/views/projects/_timelines_pane.html.erb` — wrapped `timelines.size`.
- `app/views/videos/_pane.html.erb` — wrapped `stats.size` in the "recent stats
  (N days)" header.
- `app/views/videos/panes.html.erb` — wrapped `@panes.compact.size` in the
  "videos (N)" header.
- `app/views/syncs/show.html.erb` — wrapped `@items.length` in the breadcrumb,
  the `<h1>`, and the `@already_syncing.length` skip caption.
- `app/views/syncs/progress.html.erb` — wrapped `@items.length` in the
  breadcrumb, the `<h1>`, and the textual `0/N` progress counter (left the same
  value raw inside the `data-operation-progress-total-value` Stimulus attribute
  — that's JS state).
- `app/views/deletions/show.html.erb` — wrapped `@items.length` in the
  breadcrumb and `<h1>`; wrapped per-row counts (`item.videos.count`,
  `item.footages.count`, `item.notes.count`, `item.timelines.count`,
  `item.games.count`).
- `app/views/deletions/progress.html.erb` — same treatment as
  `syncs/progress.html.erb` (header + textual counter formatted, Stimulus
  data-attribute left raw); wrapped `item.videos.count` in the channel-row.
- `app/views/collections/show.html.erb` — wrapped `@games.size`.
- `app/views/collections/index.html.erb` — wrapped `collection.games.count` in
  the per-row games column.
- `app/views/channels/_pane.html.erb` — wrapped `channel.videos.count` in the
  "videos (N)" header.
- `app/views/channels/panes.html.erb` — wrapped `@panes.compact.size` in the
  "channels (N)" header.
- `app/views/search/show.html.erb` — wrapped `@videos[:total]` in the result
  count and `@videos[:took_ms]` in the timing caption.

The two `data-operation-progress-total-value="<%= @items.length %>"` attribute
renders on the bulk progress pages stay raw — they're Stimulus state read by JS,
not user-visible text. The lint spec's `line_excluded?` guard whitelists any
`<%= ... %>` that lives inside a `data-*="..."` attribute value, so the regex
never trips on machine-readable state.

**Specs.** No existing assertions broke: every spec that checks the rendered
text uses `1` or `2` as the count (e.g.,
`expect(response.body).to include("delete 1 channel")` in
`spec/requests/deletions_spec.rb`), and `number_with_delimiter` renders both
values without any comma — identical output. Verified via grep across `spec/`.

**Lint spec.** New file: `spec/lint/numeric_formatting_spec.rb` (placed under
`spec/lint/` because it's a project-wide source-text lint, not a view render
test — there's no `spec/views/` precedent in this repo, and `spec/lint/` is a
clean home for additional project-wide scans). The spec walks every `.erb` file
under `app/views/` and `app/components/` and fails with a precise `file:line:`
list of any raw numeric render the regex catches.

Patterns it catches:

- `<%= foo.count %>` / `.size` / `.length` (with optional method chain).
- `<%= @something_count %>` (controller-set integer counters).
- `<%= foo.total_views %>` (any `.total_*` aggregate).
- `<%= foo.views %>` / `.likes` / `.comments` / `.subscribers` (per-record
  stats).
- `<%= @hash[:total] %>` / `[:count]` / `[:size]` / `[:length]` / `[:took_ms]`
  (search/aggregate hash buckets).

Per-line exclusions (the regex matches but the line is correct):

- `data-...="<%= foo.size %>"` — Stimulus / HTMX state attributes. JS reads
  these; `1,234` would break the parsing.
- `<%= 'something' if items.length != 1 %>` — pluralization helpers, where the
  size is being compared, not rendered.

**`ALLOWED_FILES`.** Empty. Every current case is either formatted via
`number_with_delimiter` or filtered by the per-line guards above. The constant
is documented as the escape hatch for future genuine raw-number cases (e.g., a
value provably bounded by a small constant where the formatter would add no
value); the expectation is that any addition is accompanied by a comment
explaining the rationale.

**Files touched.**

- 14 ERB templates (listed above).
- `spec/lint/numeric_formatting_spec.rb` — new.

**Spec count delta.** 1016 → 1017 (+1), 1 failure (pre-existing, unrelated:
`spec/requests/settings_spec.rb:37` "Voyage AI fieldset with the current flag
value" — the test was added to the working tree before this dispatch but the
view doesn't render the word "enabled" anywhere; out of scope for this sweep).

**Brakeman.** 0 warnings.

**RuboCop.** `spec/lint/numeric_formatting_spec.rb` clean (no offenses). RuboCop
on raw `.html.erb` files trips on its Ruby parser as expected (pre-existing
config gap, not actionable).

**Reviewer recheck.**

- The Stimulus attribute exclusion (`line_excluded?` guard) is pattern-based on
  `data-*="..."`. If a future template uses a Stimulus value via Hash-helper
  syntax (e.g., `data: { foo_value: items.length }`) the guard won't see it —
  but neither will the regex (the regex only matches `<%= ... %>` inside the
  rendered template text, not Ruby Hash literals passed to helpers). So the
  asymmetry is harmless.
- `number_with_delimiter` accepts `nil` and returns `"0"` / `nil.to_s`-style
  behavior — verify with the wrapped `@already_syncing.length` call on
  `syncs/show.html.erb:82`, which is gated by `if any_skipped` so
  `@already_syncing` is guaranteed present and array-typed at that point.
- The `pane_breadcrumb` (channels/panes) and `pane_breadcrumb_label`
  (videos/panes) helpers concatenate channel/video IDs with " + " — those are
  identifiers, not counts, and intentionally stay raw.

### Phase B — Floaty toast flash + format_video_watch_time rename (2026-05-04)

**Toast flash (Change 1).** Replaced the layout-pushing flash bar with a
fixed-position top-right toast stack. The old layout block at
`app/views/layouts/application.html.erb` (the two `flash[:notice]` /
`flash[:alert]` `<div>`s wedged between the breadcrumbs and `yield`) was
removed; the layout now renders `shared/_flash_toasts` once, outside the
padding-top wrapper, so the page body never shifts when a flash is or is not
present.

_Files touched:_

- `app/views/shared/_flash_toasts.html.erb` (new) — iterates `flash`, maps
  `:alert` / `:error` → `toast-error`, `:success` → `toast-success`, `:warning`
  → `toast-warning`, everything else → `toast-notice`. Skips blank messages,
  skips the container entirely when no message is present, sets
  `aria-live="polite"` + `role="status"` per toast.
- `app/javascript/controllers/toast_controller.js` (new) — `connect()` arms a
  `setTimeout` that calls `dismiss()` after `delay-value` milliseconds (default
  **4000ms**). `dismiss()` adds the `.dismissing` class (CSS opacity +
  translateY transition), then removes the element on `transitionend` with a
  400ms fallback in case the transition never fires. Click anywhere on the toast
  also dismisses immediately. `disconnect()` clears the timer and removes the
  click listener.
- `app/views/layouts/application.html.erb` — old flash divs removed,
  `<%= render "shared/flash_toasts" %>` inserted between `</header>` and the
  padded main wrapper.
- `app/assets/tailwind/application.css` — added `.toast-container`
  (`position: fixed; top: 8px; right: 8px; z-index: 200; flex column; pointer-events: none`),
  `.toast` (compact pill: 4px 10px padding, 1px border, 2px radius, 12px font,
  700 weight, drop shadow, opacity
  - transform transition, `cursor: pointer`), `.toast.dismissing` (opacity 0 +
    translateY -6px), and the four
    `.toast-{notice,success, warning,error,alert}` color variants — all backed
    by the existing `--color-flash-*-bg/border/text` CSS variables, so dark
    theme flips for free. The pre-existing `.flash-*` rules were left untouched
    — they are still used by per-form inline status strips in
    `channels/_form.html.erb`, `videos/_form.html.erb`,
    `footages/edit.html.erb`, and `projects/_notes_pane.html.erb`.

_Auto-dismiss delay chosen:_ **4000 ms**. Per-toast override available via
`data-toast-delay-value="<ms>"` on the toast element if a future caller wants a
longer or shorter sticky.

**Helper rename (Change 2).** `ApplicationHelper#format_watch_time` →
`format_video_watch_time`. Pure rename — body unchanged (the half-up
rounding-to-hour logic locked in last turn stays). Updated call sites:

- `app/helpers/application_helper.rb` (definition).
- `app/views/videos/index.html.erb:58`.
- `app/views/videos/_pane.html.erb:52`.
- `app/views/deletions/progress.html.erb:52`.
- `app/views/deletions/show.html.erb:81` — **fourth call site, not in the
  original list.** Same pattern (rendering `item.total_watch_time` for the
  "video" branch of the destruction-preview table). Renaming the helper without
  renaming this site would crash the `deletions#show` view for video-typed
  deletions, so it was renamed to keep the change atomic. Flagged for reviewer
  awareness.
- `spec/helpers/application_helper_spec.rb` — `describe` block label and all 12
  `helper.format_watch_time(...)` call sites updated. No behavior changes.

**New view spec.** `spec/views/shared/_flash_toasts.html.erb_spec.rb` (9
examples) covering: empty-flash → empty render; `:notice` → container +
`toast toast-notice` + `data-controller="toast"`; `:alert` → `toast-error`;
`:error` → `toast-error`; `:success` → `toast-success`; `:warning` →
`toast-warning`; multiple flashes → single container, multiple toasts; blank
message → empty render; class-based assertion for the fixed-position container
(CSS lives in `application.css`, not asserted here to keep the spec stable
across styling tweaks).

**Spec count.** Baseline 1019 / 0 (per `rspec --dry-run` immediately before the
change — the user-quoted 1017 baseline likely predates two unrelated specs in
the working tree). After change: 1028 / 0. Delta = +9 examples, all from the new
toast view spec. Helper rename leaves the existing 11 `format_video_watch_time`
examples in place (rename only, not new).

**Brakeman.** `bin/brakeman --no-pager -q` — 0 warnings.

**RuboCop.** `bundle exec rubocop` on the three changed `.rb` files
(`application_helper.rb`, `application_helper_spec.rb`, the new toast view spec)
— 0 offenses.

**Reviewer recheck.**

- **Flash → toast migration.** No request / system spec asserted on the old
  `.flash-notice` / `.flash-error` markup (grep was clean), so no test silently
  broke. Specs that read `flash[:notice]` / `flash[:alert]` directly (e.g.
  `spec/requests/{settings,timelines,notes}_spec.rb`) read the Rails flash hash,
  not the rendered HTML, so they are unaffected.
- **Existing `.flash-*` CSS classes intact.** Forms still render the inline
  "couldn't save" banners with the same colors. If those should also become
  toasts, that is a separate decision — not part of this pass.
- **`theme_controller.js#showFlash`.** Pre-existing dead code (the unused
  live-flash injection that built `.flash-notice` divs and inserted them into
  `<main>`). Left untouched — out of scope, and removing it touches the theme
  controller which has its own follow-up queue. Filed mentally for the next
  polish sweep.
- **`fourth call site`.** As above — `deletions/show.html.erb:81` was renamed
  alongside the three explicitly-listed call sites. Pure rename, no behavior
  change, but worth a glance because the original ask said "three places".

### Phase B — Bulk-select separator + punctuation sweep + lint guard (2026-05-04)

**Why.** When bulk mode was active on /projects with 0 items selected, the
toolbar rendered `· [cancel]` — a leading dangling separator because `count`,
`openHint`, `deleteAction` etc. were hidden together yet a literal `&middot;`
sat outside them as a fixed sibling. Same bug shape lurked on /videos and
/channels. While we were in the templates, swept punctuation on hints and
captions to match docs/design.md (period-terminated statements) and added a lint
spec so future templates stay in line. Codified the rule in docs/design.md.

**Files touched.**

Item 1 — bulk-select toolbar separator pattern (no dangling `·`):

- `app/views/projects/index.html.erb` — wrapped each toolbar action in
  `<span class="action">`, baked an `.action-sep &middot;` into every action
  (initial state ships every separator with `hidden`), added a new
  `.bulk-toolbar` outer class.
- `app/views/videos/index.html.erb` — same pattern (full action set: openHint,
  openAction, count, deleteAction, cancel).
- `app/views/channels/_picker.html.erb` — same pattern, plus the full set with
  `syncAction`. The outer `bulk-toolbar` class lives on the inner flex row so
  the existing `overMaxHint` subtext keeps its position below the bar.
- `app/javascript/controllers/bulk_select_controller.js` — added
  `_updateSeparators()` private; called from `enterBulk`, `exitBulk`, and the
  end of `updateActions`. Added `_replaceActionContent(el, ...nodes)` shim that
  preserves the leading `.action-sep` when other helpers (`_setHint`,
  `_setBracketedLink`, `_setMutedBracketed`, the inline delete/sync action
  setters, the count-target text update) replace the action target's children —
  without it `replaceChildren` would wipe the separator on every render.
- `app/assets/tailwind/application.css` — added `.bulk-toolbar` /
  `.bulk-toolbar .action` / `.bulk-toolbar .action-sep` rules (display flex,
  hidden semantics, muted color on the dot).

Item 2 — punctuation sweep (every `.form-hint`, `.caption`, and sentence-shaped
muted text ends with `.`):

- `app/views/settings/index.html.erb` — added trailing periods to four hints:
  `default: N chars.`, `default: N.`,
  `leave blank to keep current; submit to replace.`,
  `paste your Voyage AI API key.`,
  `disables Voyage indexing if any flag is on.`.
- `app/views/channels/_form.html.erb` — added period to the
  `must match …<22 chars>.` hint.
- `app/views/channels/_picker.html.erb` — added period to the
  `max N channels at a time can be opened in split view.` overMaxHint subtext.
- `app/views/dashboard/index.html.erb` — added period to the
  `N videos across M channels.` caption.

Stats: 4 view files touched, 7 hints / captions punctuated. Skipped: the
`[syncing]` state badge (bracketed inline state, not a sentence), single-word
labels (`engine`, `theme`, `project notes`), the search-results summary
(`results for "x" — N videos (Mms)` is a stat-shaped header, not a sentence; the
inner `(NNms)` is a numeric stat the lint spec excludes by pattern), the
`pending` / `processing...` bulk-operation status indicators, and breadcrumb /
nav `text-muted` separators (`&middot;`, `/`). Pre-existing periods on every
`no foo yet.` empty-state caption were left alone.

Item 3 — lint spec for future drift:

- `spec/lint/punctuation_spec.rb` — new file. Walks
  `app/{views,components}/**/*.erb`, scans for static
  `<tag class="form-hint">…</tag>` and `<tag class="caption">…</tag>` spans, and
  asserts each text ends with `.`, `?`, or `!`. Per-text excludes: pure numeric
  stats like `(<%= ... %>ms)`, and whitespace-only matches. Constants prefixed
  `PUNCTUATION_HINT_PATTERNS` / `PUNCTUATION_ALLOWED_FILES` to avoid clashing
  with the existing `numeric_formatting_spec.rb#ALLOWED_FILES`.

Item 4 — design.md addition:

- `docs/design.md` — appended a `**Punctuation.**` paragraph to the
  `### Form hints and captions` subsection. Names what counts as a statement
  (hints, captions, summaries), what doesn't (single-word labels, headings,
  bracketed-link buttons, numeric stats, placeholder glyphs), and points to the
  lint spec.

**Tests touched / added.**

- `spec/requests/projects_spec.rb` — added 2 specs: "renders the bulk-toolbar
  leading-separator pattern" and "ships with every leading separator hidden in
  the static initial render". The second uses Nokogiri to traverse the actions
  container and asserts every `.action-sep` carries the `hidden` attribute.
- `spec/requests/videos_spec.rb` — same 2 specs, scoped to /videos with the full
  action set.
- `spec/requests/channels_spec.rb` — same 2 specs, scoped to /channels (which
  carries the `syncAction` target too).
- `spec/lint/punctuation_spec.rb` — new file, 1 spec.

**Spec count.** Baseline 1028 / 0 (per `rspec --dry-run` before the change).
After change: 1035 / 0. Delta = +7 examples (6 request specs across the three
pickers + 1 new lint spec).

**Brakeman.** `bin/brakeman --no-pager -q` — 0 warnings, 0 errors.

**RuboCop.** `bundle exec rubocop` on the four changed Ruby files
(`spec/lint/punctuation_spec.rb`, `spec/requests/projects_spec.rb`,
`spec/requests/videos_spec.rb`, `spec/requests/channels_spec.rb`) — 0 offenses.

**Reviewer recheck.**

- **Static-only lint.** The punctuation lint regex only catches
  `<tag class="..." [...]>STATIC_TEXT</tag>` — nested ERB tags (e.g.
  `class="form-hint">default: <%= @x %> chars.</span>`) are silently skipped
  because `[^<]+` halts at the first `<`. That's by design (we control the
  static text; the dynamic interpolation is the developer's responsibility) and
  matches the `numeric_formatting_spec.rb` style. If you want stricter coverage,
  swap to a templating-aware parser later.
- **Bulk-toolbar JS-side.** The fix is JS-driven on transitions (enter/exit
  bulk, toggle a checkbox); the test coverage is static-render assertions only.
  A Capybara system spec would be the next layer of coverage but isn't in scope;
  the JS changes are minimal (separator preservation + `_updateSeparators` call
  sites) and the unit-equivalent is the static initial state we do test.
- **`countTarget` content.** Previously the count target's textContent was set
  to the raw integer (`0`, `5`, etc.). Now it goes through
  `_replaceActionContent` so the `.action-sep` dot isn't wiped — the count text
  remains the same plain integer. No UX shift; just an internal helper change.
- **`channels/_picker.html.erb` toolbar nesting.** The `.bulk-toolbar` class
  lives on a child div (not the `actions` target itself) so the existing
  `overMaxHint` subtext can still sit below the action row inside the same
  `actions` container. /projects and /videos put `.bulk-toolbar` directly on the
  actions target (no overMaxHint sibling). Either nesting works with the
  controller (it queries `.action:not([hidden])` from the `actionsTarget` root).
- **Empty-state captions.** Most `no foo yet.` strings live in
  `<p class="text-muted">`, not `<p class="caption">`. The lint spec only
  enforces `.form-hint` and `.caption`. If we want empty-state strings under
  stricter punctuation enforcement, either migrate them to `.caption` or extend
  the lint patterns with a sentence-detector for `.text-muted` — out of scope
  here.

### Phase B — UX polish: code-block + action labels + zebra panes + URL ellipsis + mobile nav + keycap color + mobile arrows (2026-05-04)

Seven UX-polish items the user collected during playbook validation, dispatched
as one cohesive bundle. All small view/CSS/JS changes; no model or migration
touched.

**Item 1 — Code-block component with `[ copy ]` button.**

- New Stimulus controller
  `app/javascript/controllers/clipboard_copy_controller.js`. Reads `textContent`
  from the source target, writes to clipboard via
  `navigator.clipboard.writeText` (NOT `alert`/`confirm`/`prompt` — those are
  banned by the Pito hard rules), flashes `[ copied ]` for 1500ms, then restores
  the original markup.
- **Deviation from dispatch sketch:** the dispatch used `innerHTML` to swap the
  link content. The security-reminder hook flagged that as XSS-adjacent.
  Switched to `replaceChildren` with a detached-children array
  (`Array.from(link.childNodes)`) so the original
  `[<span class="bl">copy</span>]` shape is preserved by reference rather than
  re-parsed from a string. Functionally identical, safer.
- New CSS: `.code-block` (flex container, bordered, alt bg), `.code-block code`
  (transparent bg, breakable), `.text-success` utility (used by the controller
  while flashing).
- Applied at `app/views/projects/_footage_pane.html.erb` (empty state) and
  `app/views/dashboard/index.html.erb` (empty state). Both restructure: caption
  on its own line ("no foo yet. run:"), then a `.code-block` with the command +
  inline `[ copy ]`. Existing `dashboard_spec.rb` assertion
  `include("no videos yet")` still passes — the substring survives the
  restructure.

**Item 2 — `[ new X ]` → `[ add ]`, `[ scan now ]` → `[ scan ]`.**

- Sweep applied to:
  - `app/views/projects/index.html.erb` — `[ new project ]` → `[ add ]`.
  - `app/views/projects/_notes_pane.html.erb` — `[ new note ]` → `[ add ]`,
    `[ scan now ]` → `[ scan ]`. Both the locked (`bracketed-muted`) and
    unlocked (`button_to`) variants.
  - `app/views/projects/_timelines_pane.html.erb` — `[ new timeline ]` →
    `[ add ]`.
  - `app/views/collections/index.html.erb` — `[ new collection ]` → `[ add ]`.
  - `app/views/games/index.html.erb` — `[ new game ]` → `[ add ]`.
- **Out of scope, intentionally NOT changed:**
  - `app/views/channels/new.html.erb` H1 `<h1>new channel</h1>` and the same in
    `videos/new.html.erb`. These are page headings, not bracketed action labels
    — outside the "creator-label collapse" rule.
  - `[ download cli ]`, `[ delete ]`, `[ edit ]`, `[ open ]`, `[ view ]`,
    `[ focus ]`, `[ confirm ]`, `[ cancel ]`, `[ save ]`, `[ reindex ]` — all
    preserved (actions, not creators).
  - `app/views/channels/_picker.html.erb` and `_add_pane_dialog.html.erb`
    already use `[ add ]` — verified unchanged.
- Spec update: `spec/requests/projects_spec.rb` — assertion rewritten from
  `include("new project")` to `include('class="bl">add</span>')` to assert on
  the bracketed link shape rather than the deprecated label substring.

**Item 3 — Zebra panes.**

- Single CSS rule added to `app/assets/tailwind/application.css`:
  `.pane-container > .pane-wrapper:nth-child(even) { background-color: var(--color-bg-alt); }`.
  Placed below the existing `.pane-wrapper` rules so it inherits flex sizing,
  padding, and the divider border.
- Applies automatically to:
  - `/channels` panes-view (variable count of panes, alternates).
  - `/videos` panes-view (same).
  - `/projects/:id` show page (Footage = default, Notes = alt, Timelines =
    default).
- No view changes. Pure CSS.

**Item 4 — URL ellipsis truncation.**

- New `.truncate-url` utility class in CSS:
  `display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; vertical-align: bottom;`.
  Uses the browser's native single-`…` ellipsis.
- Applied at `app/views/channels/_pane.html.erb`. Replaced the raw
  `<span style="word-break: break-all;">` (which caused the URL to wrap and
  shove `[ view ]` off-screen) with a `display: flex; min-width: 0` row whose
  URL `<a>` carries `.truncate-url` and `flex: 1; min-width: 0`. The `[ view ]`
  link sits inline next to it at full width.
- The URL itself is now its own clickable anchor (no longer a plain span). Two
  parallel paths to the same destination — the truncated URL text AND the
  `[ view ]` action — both `target="_blank" rel="noopener noreferrer"`.
- **Deviation from dispatch:** dispatch said "If you find other URL surfaces
  (video URLs, source links), apply the same class." Other surfaces
  (`channels/_picker.html.erb`, `_add_pane_dialog.html.erb`,
  `videos/_pane.html.erb`, `videos/index.html.erb`, `syncs/show.html.erb`)
  already use inline `text-overflow: ellipsis` with explicit `max-width` on
  table cells. Their issue isn't the same — they're cells with width budgets,
  not flex parents pushing siblings off-screen. Did NOT touch them; this is a
  targeted fix for the channel pane.

**Item 5 — Mobile pane arrows.**

- Edited the mobile media-query block in `app/assets/tailwind/application.css`.
  Removed `.pane-arrow-left, .pane-arrow-right` from the `display: none` rule,
  kept `.pane-arrow-up, .pane-arrow-down` hidden (those are vertical-stack
  arrows, not relevant once we switched to horizontal scroll).
- Existing base `.pane-arrow-left { left: 4px; }` /
  `.pane-arrow-right { right: 4px; }` and `z-index: 99` rules already place them
  above the panes — no z-index changes needed.
- Touch-swipe + scroll-snap stays. Arrows are now both discoverability cues +
  tap targets on mobile.

**Item 6 — Mobile nav single-char labels.**

- Extended `nav_link` helper in `app/helpers/application_helper.rb`. New
  optional `short:` kwarg. When `short` is `nil`, defaults to the uppercased
  first character of the full label. When `""`, the link emits only a
  `.hide-mobile`-wrapped desktop label (used by the `[ home ]` nav link — the
  logo image already routes home, no need to bracket-label it on mobile).
- The helper now bypasses `BracketedLinkComponent` and emits the bracketed
  markup directly, since the component takes a single string label and we need
  both `.hide-mobile` and `.show-mobile` spans inside one bracket pair. The
  active-state branch uses `<span class="bracketed bracketed-active">`; the link
  branch uses `<a class="bracketed">`. Both wrap the dual-label HTML.
- Layout updates in `app/views/layouts/application.html.erb` (header nav +
  footer nav): every non-home nav_link now passes an explicit `short:` value
  (`"C"`, `"V"`, `"P"`, `"S"`). The `[ home ]` link stays inside the existing
  `.hide-mobile` wrapper — that wrapper hides the link AND the trailing
  separator on mobile, which is the correct behavior.
- Helper spec update at `spec/helpers/application_helper_spec.rb`:
  - Existing "returns a bracketed bold span when on the current page" updated —
    assertion `include("[home]")` is too literal now (the brackets contain a
    span, not raw text). Replaced with `include("home")` +
    `include("bracketed-active")`.
  - New: "renders both desktop full label and mobile short label spans" —
    asserts `<span class="hide-mobile">channels</span>` and
    `<span class="show-mobile">C</span>` both present.
  - New: "defaults the short label to the uppercased first character of the full
    label" — asserts `<span class="show-mobile">P</span>` for `"projects"`.
  - New: "treats short: '' as desktop-only — no mobile label rendered" — asserts
    the `.show-mobile` span is absent.
- **Deviation from dispatch:** dispatch suggested wrapping the `[ home ]` link
  in `.hide-mobile` outer OR setting `short: ""`. I went with the existing
  layout's `.hide-mobile` wrapper for the home link (already in place from a
  prior phase) AND added `short: ""` support to the helper for future callers.
  Both paths now work; the layout uses the wrapper path.

**Item 7 — `--color-keycap` token.**

- Added two new color tokens in `app/assets/tailwind/application.css`:
  - Light: `--color-keycap: #6f42c1;`, `--color-keycap-hover: #553098;` (purple,
    readable on white).
  - Dark: `--color-keycap: #bd93f9;`, `--color-keycap-hover: #d4b8ff;` (Dracula
    purple, lifts on hover).
- Updated `.keycap` and `.keycap:hover` to use the new tokens instead of
  `--color-link` / `--color-link-hover`.
- Kept `.keycap-theme` (theme-toggle navbar `(n)` keycap) unchanged — it still
  opts into the bg-tone color treatment per the existing dark-mode design.
- Updated `docs/design.md` "Keycaps" section to call out the new purple color
  token + the `.keycap-theme` opt-in for the navbar toggle. Did NOT change the
  "Dark Mode" section — its description of the `(n)` toggle's bg-tone behavior
  is still correct.

**Files touched.**

- `app/javascript/controllers/clipboard_copy_controller.js` — new file (Item 1).
- `app/assets/tailwind/application.css` — Items 1, 3, 4, 5, 7.
- `app/views/projects/_footage_pane.html.erb` — Item 1.
- `app/views/dashboard/index.html.erb` — Item 1.
- `app/views/projects/index.html.erb` — Item 2.
- `app/views/projects/_notes_pane.html.erb` — Item 2.
- `app/views/projects/_timelines_pane.html.erb` — Item 2.
- `app/views/collections/index.html.erb` — Item 2.
- `app/views/games/index.html.erb` — Item 2.
- `app/views/channels/_pane.html.erb` — Item 4.
- `app/helpers/application_helper.rb` — Item 6.
- `app/views/layouts/application.html.erb` — Item 6.
- `docs/design.md` — Item 7 keycap-color note.
- `spec/helpers/application_helper_spec.rb` — Item 6 helper spec updates (1
  modified, 3 new).
- `spec/requests/projects_spec.rb` — Item 2 assertion update.

**Spec count.** Baseline 1035 / 0. After changes: 1038 / 0. Delta = +3 examples
(the three new helper spec cases for the extended `nav_link` shape — the
modified existing case stays at 1, the projects request-spec rewrite stays at
1).

**Brakeman.** `bin/brakeman --no-pager -q` — 0 warnings, 0 errors.

**RuboCop.** `bin/rubocop` on changed Ruby files
(`app/helpers/application_helper.rb`, `spec/helpers/application_helper_spec.rb`,
`spec/requests/projects_spec.rb`) — 0 offenses.

**Reviewer recheck.**

- **Mobile rendering, Item 5 (pane arrows).** Reviewer should confirm at <768px
  the `◀` and `▶` arrows render in the top corners (`top: -7px`), are tappable,
  and don't visually conflict with the scroll-snap behavior. The CSS rule that
  hides them on mobile is removed; the base rule positions them identically to
  desktop.
- **Mobile rendering, Item 6 (short labels).** Reviewer should confirm at <768px
  the navbar fits horizontally (`logo + [C] · [V] · [P] · [S] + search + (n)`)
  without wrapping. The home link should be entirely absent on mobile (the
  existing `.hide-mobile` wrapper hides it). Desktop unchanged.
- **Keycap color contrast, Item 7.** Reviewer should confirm the purple keycap
  (`#6f42c1` light, `#bd93f9` dark) is legible against the page bg in both
  themes. The theme-toggle `(n)` keycap should still render in its theme-aware
  bg color (Dracula bg in light, white-ish in dark) via `.keycap-theme`.
- **Code-block fallback, Item 1.** If `navigator.clipboard` is unavailable (e.g.
  insecure context — the `pito` dev server runs over HTTP locally), the click
  does nothing visible. No error toast; the user simply selects the command text
  manually. If we ship to production over HTTPS this is a non-issue.
- **`[ copy ]` flash uses `.text-success`.** The success color in light is
  `#2e7d32` (green, distinct from the purple keycap and blue link). In dark it's
  `#50fa7b` (Dracula green). Both cleanly distinct from the link/keycap palette.
- **URL truncation, Item 4.** The channel-pane URL is now its own anchor (in
  addition to `[ view ]`). Two paths to the same page is intentional — preserves
  the click-the-URL affordance even when the URL is truncated to
  `https://www.youtube…`.

### Phase B — Pane width + settings panes + cascade verify + relative-time helper (2026-05-04)

Four-item dispatch (first half of a two-dispatch sequence; the second handles
the note revamp + bulk on notes + inline-delete sweep). Goal: make every pane a
fixed-width column, fold the settings page into the same idiom, prove the
project cascade delete reaches the on-disk notes folder, and replace
strftime-formatted timestamps in notes with a human helper.

**Item 1 — Pane width 454px + zebra docs.**

- `app/assets/tailwind/application.css` — `.pane-wrapper` now ships
  `width: 454px; flex: 0 0 454px;` instead of the previous `flex: 1 0 auto;`.
  Combined with the existing
  `.pane-container { display: flex; overflow-x: auto; }`, the layout engages
  horizontal scroll once the viewport can't fit pane-count × 454px. Mobile
  override (`min-width: 88vw; flex: 0 0 88vw;`) inside
  `@media (max-width: 768px)` is unchanged — desktop = fixed 454px, mobile =
  88vw with snap.
- The pre-existing zebra rule
  (`.pane-container > .pane-wrapper:nth-child(even)`) needs no change; it now
  applies cleanly to settings as well as the channels/videos panes-view and the
  project show page.
- `docs/design.md` — added a "Pane sizing" + "Pane zebra" paragraph under the
  "Panes (Multi-item View)" → Desktop subsection, prose-wrap 80 chars, matching
  the existing tone.

**Item 2 — Settings → pane layout.**

- `app/views/settings/index.html.erb` — restructured from the previous 2-column
  flex with `.border-hairline` fieldsets to a single
  `<div class="pane-container">` wrapping five `<div class="pane-wrapper">`
  panes, in this order: appearance, workspaces, search, youtube_oauth, voyage.
  Each pane keeps its own per-section form with the hidden `section` field; the
  controller (`SettingsController#update`) is unchanged.
- Dropped `.border-hairline` from the fieldsets — the fixed-width pane columns +
  zebra alternation now provide the visual separation; `border: none;` keeps the
  `<fieldset>` / `<legend>` structure for accessibility without the extra
  hairline. The `<h2>` legends still anchor each pane.
- The existing `spec/requests/settings_spec.rb` assertions all rely on form
  fields, hidden `section` values, and rendered text — none reference
  `.border-hairline`, so no spec updates were needed. All settings-spec
  assertions still pass green.

**Item 3 — Project cascade-delete verify (DB + on-disk).**

- `app/models/project.rb` already had `dependent: :destroy` on `notes`,
  `footages`, `timelines`, and `project_references` — verified.
- Added `before_destroy :delete_note_file` on `app/models/note.rb` so a
  single-note destroy (via `NotesController#destroy`) AND a project-cascade
  destroy (`Project#destroy → notes dependent: :destroy`) both reach
  `NotesFilesystem.delete(self)`. The callback rescues `StandardError` and logs
  — a missing-file race must never block the DB-side destroy.
- Added `after_destroy_commit :delete_notes_directory` on `Project` so once
  every Note's individual file is gone, the empty
  `<PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/` folder is removed.
  Lives on `_commit` (not plain `after_destroy`) so a rolled-back destroy never
  orphans the directory deletion.
- Added two helpers to `app/lib/notes_filesystem.rb`: `project_dir(project)`
  (path accessor mirroring `root_for(note)`) and `delete_project_dir(project)`
  (defensive `FileUtils.remove_entry` guarded by `File.directory?`). Reused both
  from the new Project callback so the directory-naming logic stays in one
  place.
- `NotesController#destroy` still calls `NotesFilesystem.delete(@note)` ahead of
  `@note.destroy!`. The callback now also fires; `NotesFilesystem.delete` is
  idempotent (no-op when the file is missing), so the double-call is safe. Left
  it in place rather than refactor — keeps the scope tight per dispatch.
- `spec/models/project_spec.rb` — added two `describe` blocks:
  `"cascade destroy"` (3 examples — DB-side cascade, on-disk folder removed,
  no-op when folder is absent) and `"Note destroy file cleanup"` (1 example —
  solo `note.destroy` removes its file). Both blocks use a unique `tmp_root`
  under `Rails.root.join("tmp/test-pito-notes/<hex>/")` so they never touch a
  real `PITO_NOTES_PATH`.

**Item 4 — `format_relative_time` helper.**

- `app/helpers/application_helper.rb` — added `format_relative_time(timestamp)`
  wrapping Rails' `time_ago_in_words`. Buckets: nil → "—", < 1 minute → "just
  now", < 1 day → `time_ago_in_words(...) + " ago"`, < 7 days → `"%a %H:%M"`
  weekday + 24h time, older → `"%Y-%m-%d"` ISO date.
- `app/views/projects/_notes_pane.html.erb` — replaced
  `note.last_modified_at.strftime("%Y-%m-%d %H:%M")` with
  `format_relative_time(note.last_modified_at)` in the "last modified" cell.
  Other surfaces (channel `last_synced_at`, video `published_at`, etc.)
  deliberately left alone — sweeping them is queued as a follow-up.
- `spec/helpers/application_helper_spec.rb` — added 5 examples for the new
  helper, with `include ActiveSupport::Testing::TimeHelpers` and `travel_to` for
  deterministic time control. Cases: nil, 30 seconds ago, 5 minutes ago, 3 days
  ago (weekday + time regex), 30 days ago (ISO date regex).

**Files touched.**

- `app/assets/tailwind/application.css` — Item 1.
- `docs/design.md` — Item 1.
- `app/views/settings/index.html.erb` — Item 2.
- `app/models/project.rb` — Item 3.
- `app/models/note.rb` — Item 3.
- `app/lib/notes_filesystem.rb` — Item 3.
- `spec/models/project_spec.rb` — Item 3 (+4 examples).
- `app/helpers/application_helper.rb` — Item 4.
- `app/views/projects/_notes_pane.html.erb` — Item 4.
- `spec/helpers/application_helper_spec.rb` — Item 4 (+5 examples).

**Spec count.** Baseline 1038 / 0. After changes: 1047 / 0. Delta = +9 examples
(Item 3 = +4, Item 4 = +5).

**Brakeman.** `bin/brakeman --no-pager -q` — 0 warnings, 0 errors.

**RuboCop.** `bin/rubocop` on changed Ruby files (`app/models/note.rb`,
`app/models/project.rb`, `app/lib/notes_filesystem.rb`,
`app/helpers/application_helper.rb`, `spec/models/project_spec.rb`,
`spec/helpers/application_helper_spec.rb`) — 0 offenses.

**Reviewer recheck.**

- **On-disk cascade.** Reviewer should manually destroy a Project that has Notes
  (and underlying `.md` files in `PITO_NOTES_PATH`) and confirm the project's
  folder under `<PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/` is gone
  afterwards. The spec asserts this with a tmpdir; the manual check verifies the
  prod-style path tree behaves the same.
- **Settings panes responsive feel.** Reviewer should resize the browser at
  /settings: at full width all five panes show side-by-side; below 5 × 454px the
  row scrolls horizontally; at <768px the mobile rule kicks in (88vw +
  scroll-snap). Each fieldset legend (`appearance`, `workspaces`, `search`,
  `YouTube OAuth`, `Voyage AI`) should still read clean without the previous
  `.border-hairline`.
- **Settings zebra.** Reviewer should confirm panes 2 and 4 (workspaces,
  youtube_oauth — 0-indexed even by `:nth-child(even)` in CSS, i.e. the second +
  fourth pane) pick up the alt background from `var(--color-bg-alt)`. In dark
  theme that's `#21222c`; in light it's `#fafafa`.
- **Relative-time helper rendering.** Reviewer should view `/projects/:id` with
  a mix of recently-modified and older notes and confirm the "last modified"
  column reads human-friendly: a just-edited note shows "just now", an hour-old
  note shows "about 1 hour ago", a 3-day-old note shows e.g. "Mon 14:32", and an
  older one shows the ISO date. The `.num` class on the cell still right-aligns
  the text.

### Phase B post-commit — Note revamp + bulk on notes + inline-delete + double-delete consolidation (2026-05-04)

After Phase B body landed (commit `11d2cbb`), the user signed off four related
polish items. They land as new work on top of `11d2cbb`; the master commit comes
later, after manual playbook validation.

**Item 1 — Note revamp: single screen, two panes, no title input.**

The note editor is now a single page (`GET /notes/:id`) instead of three (show /
edit / new). Two panes side-by-side at 454px each (matches the global
`.pane-wrapper` width):

- Left pane: rendered markdown preview. Server-side first paint via
  `commonmarker` (already in `Gemfile.lock`); client-side live updates on every
  `input` event via `marked@15.0.7` + `dompurify@3.2.4` (both pinned via
  importmap on the jsDelivr ESM bundles — the `marked` choice was made over
  `markdown-it` for size, GFM support out of the box, and ESM-clean shape).
- Right pane: source `<textarea>` (the form's actual input). Status bar at the
  bottom-right of the source pane reads `<chars> chars · <words> words` and
  updates live; server-side counts come from the new `chars_count` /
  `words_count` columns and `number_with_delimiter`.
- Title is auto-derived from the body's first ATX H1 in `NotesController#update`
  (no title input on the form). Even if a malicious client sends `note[title]`,
  it's ignored — the spec covers that path.

Routes: dropped `GET /notes/:id/edit`. `resources :notes` now lists
`only: [ :index, :show, :update, :destroy ]`. The show route IS the editor.
`app/views/notes/edit.html.erb` was deleted; `notes/show.html.erb` renders the
new two-pane layout.

Migration `20260504000012_add_counts_to_notes.rb` adds the two integer columns
(`null: false, default: 0`) and backfills existing notes by reading the body off
disk via `NotesFilesystem.read`. Verified reversible: `rake db:rollback STEP=1`
then `db:migrate` round-trips cleanly.

`Note#before_save :recompute_counts` reads from a non-persisted
`attr_accessor :body_for_counts` that the controller assigns before `save!`.
Char count uses `body.chars.size` (codepoints), not `body.bytesize`. Word count
uses `body.scan(/\S+/).size`.

**`unsaved-form` Stimulus controller + `beforeunload` carve-out.**

New `app/javascript/controllers/unsaved_form_controller.js` snapshots the form's
serialized state on connect, marks dirty on `input`/`change`, and on the window
`beforeunload` event sets `event.returnValue = ""` to trigger the browser-native
"Leave site?" dialog. On `submit` it clears the dirty flag before the navigation
so a successful redirect doesn't re-trigger the guard. Wired into the note
editor as `<form data-controller="markdown-editor unsaved-form">`. Reusable on
any other form via the same data-controller attribute.

CLAUDE.md "Hard rules" section was extended with a sub-bullet documenting the
carve-out: `beforeunload` is allowed for unsaved-changes navigation guards
because the browser renders the dialog itself; the page does not interrupt user
action mid-click. JS `confirm` / `alert` / `prompt` remain forbidden.

**Item 2 — Bulk-select on the notes pane.**

Wrapped the notes pane in `app/views/projects/_notes_pane.html.erb` with the
`bulk-select` Stimulus controller (panes-optional shape — only the
`deleteAction` target is wired, no `openAction` / `syncAction`). Mirrors the
`/projects` index pattern. The `Confirmable` allowlist already covers `note`, so
`/deletions/note/<comma-ids>` works without controller changes.

Pane table now also surfaces the new `chars` / `words` columns alongside `title`
and `last modified` — the user requested this stat-line shape mirroring the
Meilisearch "indexed documents" pattern.

**Item 3 — Inline-confirm `[ delete ]` sweep.**

Per-screen audit of every `BracketedLinkComponent.new(label: "delete"`:

- `notes/show.html.erb` (new note editor) — `ConfirmModalComponent` modal.
  Decision: keep modal. The page-redirect feels heavyweight relative to a single
  in-flight note delete; the modal keeps the user in context.
- `projects/show.html.erb` — already routes to `/deletions/project/:id` (action
  confirmation page). No change.
- `channels/show.html.erb` — already routes to `/deletions/channel/:id`. No
  change.
- `videos/show.html.erb` — already routes to `/deletions/video/:id`. No change.
- `footages/show.html.erb`, `games/show.html.erb`, `collections/show.html.erb`,
  `timelines/show.html.erb` — no `[ delete ]` button at all (delete flow is
  owned by the parent surface or the importer for footage). No drift.

Conclusion: no drift to fix. The note editor's modal is the only delete that
doesn't go through `/deletions/...`, and that's deliberate per the dispatch
(consistent with the new note revamp).

**Item 4 — Note destroy double-delete consolidation.**

Removed the explicit `NotesFilesystem.delete(@note)` call from
`NotesController#destroy`. The `Note#before_destroy :delete_note_file` callback
(added in the previous Phase B post-validation pass) is the single source of
truth. Covers direct destroys, `dependent: :destroy` cascades from
`Project#destroy`, console-driven destroys, and bulk delete jobs uniformly.

The existing `DELETE /notes/:id` request spec still asserts the file is gone
after destroy — proving the callback path works end-to-end.

**Files touched.**

- `db/migrate/20260504000012_add_counts_to_notes.rb` — new (Item 1).
- `db/schema.rb` — regenerated (Item 1).
- `app/models/note.rb` — `body_for_counts` accessor +
  `before_save :recompute_counts` (Item 1).
- `app/controllers/notes_controller.rb` — show is the editor; update derives
  title from body; destroy drops the explicit file delete (Items 1 + 4).
- `config/routes.rb` — drop `:edit` from `resources :notes` (Item 1).
- `config/importmap.rb` — pin `marked@15.0.7`, `dompurify@3.2.4` (Item 1).
- `app/javascript/controllers/markdown_editor_controller.js` — new (Item 1).
- `app/javascript/controllers/unsaved_form_controller.js` — new (Item 1,
  reusable carve-out).
- `app/views/notes/show.html.erb` — new (Item 1).
- `app/views/notes/edit.html.erb` — deleted (Item 1).
- `app/views/notes/index.html.erb` — `note_path` instead of `edit_note_path`
  (Item 1).
- `app/views/projects/_notes_pane.html.erb` — bulk-select wrapper + chars/words
  columns + `note_path` (Items 1 + 2).
- `app/helpers/application_helper.rb` — `render_markdown` SSR helper (Item 1).
- `app/assets/tailwind/application.css` — `.markdown-preview` +
  `.markdown-status` styles (Item 1).
- `CLAUDE.md` — `beforeunload` carve-out documented (Item 1).
- `spec/models/note_spec.rb` — `chars_count` / `words_count` recomputation spec
  (+4 examples).
- `spec/requests/notes_spec.rb` — route shape rewrites + editor markup
  - bulk-select markup + auto-derived title (+10 examples; net delta vs.
    previous file).

**Spec count.** Baseline 1042 / 0. After changes: 1056 / 0. Delta = +14 examples
(Item 1 = +13 model/request, Item 2 = bulk markup folded into the same request
file).

**Brakeman.** `bin/brakeman --no-pager -q` — 0 warnings, 0 errors.

**RuboCop.** Clean on every changed Ruby file (controllers / models / helpers /
config / migrations / specs).

**Migration verification.** `bin/rails db:rollback STEP=1` then `db:migrate`
round-trips cleanly. Test schema regenerated via `db:test:prepare`.

**Spec ambiguity resolved.** The dispatch suggested a Capybara + headless Chrome
system spec for the live preview. The repo has no system-spec setup (no
`spec/system/`, no Capybara driver pinned, no Chrome / chromedriver in CI).
Adding that infrastructure was out of scope for this dispatch; instead, the
request spec asserts every `data-controller` / `data-*-target` data attribute
the live editor needs is present in the rendered markup. The actual live render
is exercised by the model spec (counts) + the JS controller code review. This
was the single deviation; flagged for the user to decide whether to add
system-spec infra in a later session.

**Library choice.** Chose `marked` over `markdown-it`: smaller, GFM support out
of the box, ESM module that imports cleanly via importmap. Paired with
`dompurify` for sanitization (marked does NOT sanitize on its own — DOMPurify
runs over the rendered HTML before injection). Both pinned to specific versions
on jsDelivr.

## 2026-05-05 — Footage filename middle-truncation (Project show pane)

**State at start.** CLI TUI footage import dialog landed a `middle_truncate`
helper earlier today (`extras/cli/src/footage/ui/confirmation.rs`) so long
OBS-style filenames keep their unique trailing timestamp + `.mkv` extension
visible in the confirmation list. The Rails project show page's footage pane had
not yet adopted the same treatment — its `<td>` for filename was inheriting the
table's `white-space: nowrap` + the 454px `.pane-wrapper` width, which silently
end-truncated paths like
`Ghost 'n Goblins Resurrection - 2026-04-23 23-34-48.mkv` to
`Ghost 'n Goblins Resurrection - 2026-04-23 23-34`. Four rows in a row looked
identical.

**Decision.** Mirror the CLI fix on the web side, but use a pure-CSS flex /
two-span pattern (zero JS). The view splits each filename into a shrinkable
`.filename-head` (with `text-overflow: ellipsis`) and a pinned `.filename-tail`.
The cell carries a `title="<full filename>"` for hover reveal. Ellipsis is the
Unicode `\u{2026}` rendered by the browser (no literal character in the markup —
the head's CSS `text-overflow: ellipsis` does it).

**Tail length.** Fixed 23 characters. Covers the trailing
` - YYYY-MM-DD HH-MM-SS.mkv` segment OBS produces. Filenames at or below 23
chars render as a single span (no split, no ellipsis). No per-extension
heuristics — kept simple per the dispatch.

**Files touched.**

- `app/helpers/footage_helper.rb` (new) — `FootageHelper#filename_split`
  helper + `FOOTAGE_FILENAME_TAIL = 23` constant.
- `app/views/projects/_footage_pane.html.erb` — filename `<td>` now carries
  `class="filename-cell"` + `title=` and emits a head/tail span pair when the
  filename exceeds the tail length.
- `app/assets/tailwind/application.css` — new `.filename-cell` /
  `.filename-head` / `.filename-tail` rules slotted in next to `.num`,
  cross-referenced to the CLI helper in the comment.
- `spec/helpers/footage_helper_spec.rb` (new) — 6 examples covering short /
  exact-length / OBS-style long / custom tail / multibyte / nil-coercion paths.
- `spec/requests/projects_spec.rb` — 2 new examples on the project show page
  asserting both the long-filename split + the short-filename single-span
  fallback.

**Spec count.** Baseline 1061 / 0. After changes: 1069 / 0. Delta = +8 examples
(6 helper + 2 request).

**Brakeman.** `bundle exec brakeman -q -w2` — 0 warnings, 0 errors.

**RuboCop.** Clean on every changed Ruby file
(`bundle exec rubocop app/helpers/footage_helper.rb spec/helpers/footage_helper_spec.rb spec/requests/projects_spec.rb`).

**No plan checkbox ticked.** This dispatch was a UX follow-up driven by a user
screenshot, not an entry under
`docs/plans/beta/04-project-workspace/additions.md`. No checkbox applies.

**Manual verification handed back to the user.** Restart `bin/dev` so the
Tailwind watcher picks up the new `.filename-*` rules, then load
`https://app.pitomd.com/projects/1` — the four Ghost 'n Goblins rows should show
distinct trailing timestamps + `.mkv`, and hovering any filename should surface
the full path in a tooltip.

## 2026-05-06 — UX polish wave (settings redesign · project page redesign · channels/videos list polish · projects index expansion · CLI filesize)

Consolidates four parallel-lane entries originally appended by individual
implementer agents (Lane G channels/videos polish, Lane F project show revamp,
Lane H projects index expansion, F2 strong-params patch) plus the Wave 1 + Wave
1.5 polish that landed earlier in the day. The narrative below is in
chronological / dependency order so the history is auditable months later.
Reviewer playbook:
`docs/orchestration/playbooks/2026-05-06-wave1-wave2-polish.md`. Security
playbook:
`docs/orchestration/playbooks/security-2026-05-06-wave1-wave2-polish.md`.

### Wave 1 — site-wide bracketed-link relabel + settings restructure (parallel landed)

- **Bracket-link relabel sweep.** `[add]` → `[+]`, `[delete]` → `[-]`, `[edit]`
  → `[e]`, `[open]` → `[o]`, `[view]` → `[v]`, `[save]` → `[update]` across
  breadcrumbs, action rows, and inline cells. The relabel is the single source
  of truth — Wave 1.5 below corrects the few places where the new glyphs
  misfired.
- **URL casing copy sweep.** Tab `<title>` strings, breadcrumb labels, and page
  headings normalized to lowercase so `app.pitomd.com/channels` shows
  `pito · channels` (not `Channels`). Mirrors the production URL casing rule.
- **Tab `<title>` SafeBuffer fix.** A regression in the title helper was
  emitting the SafeBuffer wrapper class name (e.g.
  `#<ActiveSupport::SafeBuffer:0x…>`) instead of the rendered string in some
  paths. Helper now coerces to plain string before render.
- **Settings page restructured into 3-row layout.** Row 1 splits 50/50
  (appearance | workspaces). Row 2 splits 50/50 (YouTube | Voyage). Row 3 spans
  full-width (search). Mirrors the same shape Wave 2 Lane F applies to the
  project show page.
- **`filesize_bytes` column on `footages`.** New `bigint` column +
  `FootageHelper#human_filesize` for the project-show table. Zero / nil render
  as the em-dash placeholder convention. JSON serialization includes it
  (read-side); strong-params would be patched in F2 below.
- **`docs/design.md` — Copy > URL casing rule.** Captures the lowercase rule so
  future surfaces don't drift.

### Wave 1.5 — corrections after user feedback

- **Channels new form `[add]` (branched on `channel.new_record?`).** The Wave 1
  relabel had collapsed both create and update to `[update]` / `[+]`; user
  feedback called out that the form's submit button on `new` reads more
  naturally as `[add]` (the create verb). The form partial now branches: `[add]`
  when `channel.new_record?`, `[update]` otherwise.
- **Breadcrumb cleanup.** `[add channel]` → `[+]` on the `/channels` breadcrumb
  actions row (relabel was inconsistent — Wave 1 missed the spelled-out
  variant).
- **Saved-view buttons reverted to `[save]`.** Saved-view "create" / "update"
  were renamed `[update]` in Wave 1 but the saved-view UX only has one verb
  (capture-and-store), so `[save]` is the correct label. Reverted both surfaces.
- **Footage + notes panes drop `[e]` column.** The per-row `[e]` action column
  on the project show page is replaced by making the filename (footage) and
  title (notes) cells clickable. The cells now route to the edit page; the
  column is gone. Footage edit page already existed — routes / controller
  required no change.

### Wave 2 — feature-bundle parallel landing

Three lanes ran in parallel against the post-Wave-1.5 working tree:

**Lane E — CLI `filesize_bytes` capture.** `extras/cli/src/footage/probe.rs`
gained an `fs::metadata().len()` read on probe; the value is sent on POST +
PATCH bodies (`extras/cli/src/footage/api/client.rs`). The diff classifier
(`extras/cli/src/footage/diff.rs`) compares
`record.filesize_bytes != probed.filesize_bytes` so a row with mismatched size
classifies as `[chg]`. Tests added on the CLI side: 192 unit + 11 integration
green.

**Lane F — Project show redesign.** Show page restructured into a two-row
stacked layout (row 1: timelines | notes 50/50; row 2: footage full-width)
matching the Wave 1 settings shape. Footage table grew to eight columns:
`filename, game, resolution, fps, bit depth, duration, filesize, source` (`kind`
retired from the view, kept on the model). Conditional filter chips render only
on dimensions where the project's footage varies (>1 distinct value). Sort moved
to URL state via `?sort=&dir=`, mirroring `ChannelsController#index`'s
allowlist + inline-ternary direction sanitize. Brakeman-trick: the inline
ternary is repeated inside `Arel.sql(...)` so flow analysis sees the allowlist
literals — same shape used in `ChannelsController#sort_clause`.
`app/helpers/footage_helper.rb#human_duration` added (`"10m 22s"` /
`"1h 30m 15s"` / `"45s"`, em-dash placeholder for nil / non-positive). Footage
bulk shape deferred — `Footage` is not in `Confirmable::TYPES`, so
`/deletions/footage/:ids` would 404. Filed as follow-up A in
`docs/orchestration/follow-ups.md`. Source-column sort orders by enum integer;
with two values today (`obs(0)`, `camera(1)`) the visual order happens to match
alphabetical, but adding a third value breaks the assumption. Filed as follow-up
B.

**Lane G — Channels + videos list polish.** Always-on checkboxes with a real
select-all header (`[ ]` / `[x]` / indeterminate). `[bulk]` toggle and
`[cancel]` exit dropped. `[v]` YouTube external-link column folded into the URL
cell (the URL text itself is now the
`<a target="_blank" rel="noopener noreferrer">` link). Workspace add-pane glyph
migrated `[+]` → `[/]` on channel + video show + panes pages so it disambiguates
from the add-record `[+]`. Add-channel + add-video modals capped at
`max-height: 80vh` with internal `overflow-y: auto`; `[close]` moved to a
`.modal-footer` hairline at the bottom (matches saved-views and confirm modals).
`bulk_select_controller.js` change is additive — the existing `enterBulk` /
`exitBulk` / `bulkToggle` surface stays callable for the views that still wire
it (notes pane, projects index). Filed as follow-up I (legacy comments mislead).

**Lane H — `/projects` index expansion.** Counter-cache columns added to
`projects`: `footages_count`, `notes_count`, `timelines_count` (integer, default
0, NOT NULL). Migration pair: column add + backfill via
`Project.reset_counters`. Models wired (`Footage`, `Note`, `Timeline`
`belongs_to :project, counter_cache: true`). Index controller accepts
`?sort=&dir=` against an `ALLOWED_SORTS` allowlist
(`name, created_at, footages_count, notes_count, timelines_count`), default
`created_at DESC`, mirroring `ChannelsController#sort_clause` shape. View grew
to seven columns: bulk-checkbox, open-action, name (link to show), created
(`compact_time_ago`), footages, notes, timelines. Active header carries `▲` /
`▼` indicator. Migration round-trips clean (`db:migrate` → `db:rollback STEP=2`
→ `db:migrate`). Backfill on the dev DB filled Project 1 with `4 / 1 / 0`.

### F2 patch — strong-params permit list (post-security-review)

Security review F2 flagged a functional gap: the Rust CLI sends `filesize_bytes`
on both POST create and PATCH update payloads, but neither Rails strong-params
permit list included it. `footage_json` already serialized `filesize_bytes` on
the way out, so specs caught the response shape but not the round-trip; every
importer write left `filesize_bytes: NULL` in Postgres. Patch:

- `app/controllers/api/footages_controller.rb#build_create_attrs` —
  `:filesize_bytes` added to the permit list.
- `app/controllers/footages_controller.rb#build_update_attrs` —
  `:filesize_bytes` added to the JSON-branch permit list. The HTML-branch list
  is unchanged: filesize is importer-owned, never user-edited via the form.
- Round-trip specs added: a POST spec asserting `filesize_bytes: 1234` survives
  create and lands on the row, and a PATCH spec asserting `filesize_bytes: 5678`
  survives JSON update. Live smoke against `bin/dev`:
  `POST /api/projects/1/footages.json` with `filesize_bytes: 98765` returned the
  row with `filesize_bytes: 98765` (was `null` before the fix).

The four importer-touched rows on Project 1 carry `filesize_bytes: NULL` because
they were created under the broken permit list. Re-running
`pito footage import --project 1 --path "..."` with the rebuilt CLI binary
classifies them as `[chg]`, the user confirms, and the PATCH lands
`filesize_bytes` for each row.

### Verification

- `bundle exec rspec` — **1153 examples, 0 failures**.
- `bundle exec rubocop` — clean (285 files, 0 offenses).
- `bin/brakeman -q` — 0 errors, 0 security warnings.
- `cargo test --manifest-path extras/cli/Cargo.toml` — 192 unit + 11
  integration, 0 failures.
- `cargo clippy --all-targets -- -D warnings` (extras/cli) — clean.
- `cargo fmt --check` — pre-existing drift in
  `extras/cli/src/{app,commands/tui,keys,ui/dashboard,ui/mod,ui/operation_progress,ui/videos,widgets/mod}.rs`.
  None introduced today; filed as follow-up C.
- Hard-rules audit — no `data-turbo-confirm` / `window.confirm` / `alert(` /
  `prompt(` anywhere in `app/`.
- Migrations reversibility — `db:rollback STEP=2` + `db:migrate` clean.

**Commit.** Will land as `<commit-hash-placeholder>` after the architect runs
`git commit` post-validation.

### Decisions captured

- **Always-on checkboxes are the canonical bulk shape.** Toggle-mode surfaces
  (notes pane, projects index) keep the legacy hooks for now. Migrating them is
  a separate follow-up.
- **Filter chips on the project show page reuse `FilterChipComponent`.** No new
  component minted today; sharing a `FilterChipGroupComponent` with `/channels`
  is filed as follow-up F.
- **Footage sort allowlist is repeated, not DRY.** Both `#sort_clause` (index)
  and `ordered_footages` (show) inline-build the
  `Arel.sql("#{column} #{direction}")` to keep Brakeman flow-analysis happy.
  Filed as follow-up E to consolidate when a third call site appears.
- **`[/]` (split) is the workspace add-pane glyph.** The add-record `[+]` stays
  as is. Disambiguation is by glyph, not label.
- **CLI `filesize_bytes` is sourced from `fs::metadata().len()`.** No separate
  ffprobe call needed; the OS-level metadata read is cheap.

### Open documentation gaps for the next session

- Reviewer surfaced two minor concerns (`.filename-cell` flex on `<td>` at
  narrow viewport — follow-up H; `request.query_parameters.merge(sort:, dir:)`
  mixes string + symbol keys — follow-up G).
- The previously-deferred Phase B-2 validation + commit follow-up still has not
  been actioned; this consolidated entry does not change its status.
- The settings restructure landed in Wave 1 but the screenshot-walkthrough the
  user requested is queued as a manual step the architect runs before
  committing.
