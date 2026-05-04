# Manual test playbook — Phase 4 Foundation (Project Workspace, Phase A)

**Repo:** `pito` (monolith) at `/home/catalin/Dev/pito` **Spec:**
`docs/plans/beta/04-project-workspace/specs/project-workspace.md` (§14 Phase A)
**Log:** `docs/plans/beta/04-project-workspace/log.md` (entry
`2026-05-04 — Phase A — Foundation`) **Reviewer run:** 2026-05-04 02:57 local

This is the user's chance to validate Phase A before the architect commits.
Phase A is the sequential Rails foundation for Phase 4 (9 migrations, 7 new
models, gems, AS variant processor, Voyage gating flag, route shells,
factories + seeds). Phase B (controllers, views, jobs, design refresh, GitHub
Actions, the `pito footage` subcommand) is queued and dispatches AFTER this
commit lands.

## Pipeline summary

| Gate                                           | Status   | Notes                                                                                                                                                               |
| ---------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 `/code-review` on the diff                   | PASS\*   | No blockers. Six non-blocking observations — see "Concerns / suggestions" below.                                                                                    |
| 2 `/simplify` on the diff                      | PASS\*   | Three small candidates — none warrant a fix-up dispatch. See concerns 5 and 6.                                                                                      |
| 3 `bundle exec rspec` (full suite, test env)   | **PASS** | 855 examples, 0 failures, 27.4s. +109 examples vs Step 0 (746 / 0). Matches pito-rails report.                                                                      |
| 4 `bin/brakeman --no-pager -q`                 | **PASS** | 0 errors, 0 security warnings. 10 controllers, 22 models, 42 templates scanned.                                                                                     |
| 5 `bundle exec bundler-audit check --update`   | **PASS** | Advisory DB updated (1078 advisories, last 2026-03-30). No vulnerabilities in any of the new gems.                                                                  |
| 6 `bin/rubocop` over the changed Ruby files    | **PASS** | 37 Ruby files inspected, 0 offenses. (`config/storage.yml` excluded from this run — rubocop parses YAML as Ruby and chokes on the ERB tags; not Phase A's problem.) |
| 7 `bin/rails db:rollback STEP=9 && db:migrate` | **PASS** | All 9 migrations reverse cleanly and replay clean (verified live in test env).                                                                                      |
| 8 Static-deviation audit                       | NOTE     | Three implementer choices deviate from a literal reading of the spec — concerns 1, 2, 3 below. None are blockers.                                                   |

`*` Code review and simplify produced findings but no blockers — see the next
two sections.

## Blockers

None. The architect can hand the playbook to the user for validation.

## Concerns / suggestions (non-blocking)

These do not stop the user from validating Phase A. They are surfaced so the
architect / docs-keeper can decide whether to backfill the spec, queue
follow-ups, or flag for Phase B.

### 1. `Project#games <<` and `Project#collections <<` raise `Tenant must exist`

The `has_many :through` polymorphic associations (`Project#games`,
`Project#collections`) do not auto-fill `ProjectReference#tenant_id` on insert,
so the ergonomic shovel API is broken:

```
project.games << game
# => ActiveRecord::RecordInvalid: Validation failed: Tenant must exist
```

`ProjectReference` has `belongs_to :tenant` and the schema declares
`tenant_id NOT NULL`, but unlike `Footage` (which uses
`before_validation :denormalize_tenant_from_project`), `ProjectReference` has no
callback to copy the project's tenant onto the join row.

`db/seeds.rb` works around this by using explicit
`ProjectReference.find_or_create_by!(project: ..., tenant: ..., referenceable_type: ..., referenceable_id: ...)`
calls. Phase B's controllers will do the same.

Two ways to resolve, neither blocks Phase A:

- (a) **Add a `before_validation` to `ProjectReference`** mirroring `Footage`'s
  pattern: `self.tenant_id ||= project&.tenant_id`. Restores the ergonomic `<<`
  API and keeps Phase B's controllers terser.
- (b) **Lock the spec / docs** to "always create `ProjectReference` records
  explicitly with tenant_id" and treat `<<` as off-limits.

Recommend (a) — one-line change, mirrors the existing pattern, no spec rewrite
needed. Could be a Phase B early task or a refinement-backlog item.

### 2. libvips IS installed on the dev host (contradicts pito-rails report)

The pito-rails Phase A report said libvips 8.18 was not installed and
`require: false` on `ruby-vips` was needed to keep the Rails boot working.
Reality on this host:

```
$ pacman -Q libvips
libvips 8.18.2-1
$ vips --version
vips-8.18.2
```

libvips IS installed (Arch `extra/libvips`), library at
`/usr/lib/libvips.so.42 -> libvips.so.42.20.2`. A boot-time warning fires:

```
VIPS-WARNING: unable to load "/usr/lib/vips-modules-8.18/vips-openslide.so" --
libopenslide.so.1: cannot open shared object file: No such file or directory
```

That warning is harmless — OpenSlide is an optional VIPS module for medical-
imaging slide formats; image_processing's variant pipeline never loads it. The
`require: false` pin is still defensible (Hetzner servers may not have libvips
at first boot, and the lazy require in `image_processing/vips.rb` keeps the gem
ergonomically optional), but the rationale captured in the log (host doesn't
have libvips) is incorrect on this machine.

Action: either pito-rails was reading state from a prior session when libvips
was indeed missing, or libvips was pulled in by an unrelated package between now
and the agent run. Practical impact: Phase B's cover-art tests **will not need**
`sudo pacman -S libvips` on this host. Worth verifying once on a clean checkout
before Phase B kicks off; the guidance to install libvips is still valid as the
Phase B prereq for any reviewer running on a different machine.

### 3. Spec deviation — Active Storage `:test` service kept intact

Spec §5 says `config.active_storage.service = :local` "in all environments."
Phase A leaves the `:test` Disk service intact (`tmp/storage`) in
`config/environments/test.rb` (the env file already had
`config.active_storage.service = :test` from Step 0 era; the diff doesn't touch
it). Reading log.md: "Step 6 — `storage.yml`. The
`config.active_storage.service = :local` line was already in `development.rb`
and `production.rb`; verified no duplication."

Practical impact: zero. Test env using a separate disk service prevents specs
from polluting `PITO_ASSETS_PATH`. The literal "all environments" reading in the
spec would produce a worse outcome (test artefacts crossing into the dev assets
folder). Recommend amending §5 to "in `development` and `production` (`:test`
keeps its dedicated disk service)" — docs-keeper one-liner.

### 4. Five spec ambiguities resolved by the implementation

The implementation made sensible defaults where the spec did not pin behavior.
Capture in a docs-keeper amendment so future readers see the contract clearly:

1. **`resources :projects` lacks the `:panes` member action.** Spec §13 (Files
   touched, "Routes" line) says
   `resources :projects do member { get :panes } end`. Spec §9.1 explicitly
   drops the panes member ("the panes belong to the show page, not a collection
   action"). Phase A landed plain `resources :projects` — matches §9.1,
   contradicts §13. §13 is the stale reference; recommend §13 be amended to drop
   the `:panes` member.
2. **Test-env storage service preserved (covered above as concern 3).**
3. **Footage `tenant_id` left nullable at the schema layer.** Spec §3.4 marks it
   nullable and says "denormalized for scoping". The model fills it via
   `before_validation`, so in practice every saved row carries a tenant_id.
   Phase B can tighten the column to NOT NULL once the importer's exact write
   path is in code; until then the nullable column lets the importer land
   partial rows during diff resolution.
4. **`voyage:smoke_test` rake task deferred to Phase B.** Spec §15 mentions the
   task in acceptance criteria; pito-rails grouped it with Phase B's
   `Notes::EmbedJob` (same Voyage code path, same credentials wiring). Phase A
   only ships the gating flag + factory of dependent services. Reasonable —
   Phase A is models + schema, the task is a runtime utility.
5. **Video aasm machine deferred to Phase B.** Spec §11.2 (Video
   `scheduled → published → unpublished`) is not in Phase A's §14 list. Phase B
   owns it. Confirm in the Phase B reviewer pass.

### 5. Simplify candidates (cosmetic, not worth a dispatch)

- `app/models/game.rb:8-14` — `ALLOWED_PLATFORMS` uses
  `%w[Xbox\ Series Xbox\ One]` with backslash-escaped spaces. Reads cleanly, but
  two of eight entries contain the escape — a plain frozen array
  (`["PS5","PS4","Xbox Series","Xbox One","Switch","PC","Mac","Mobile"].freeze`)
  matches the spec text byte-for-byte and is easier to skim. Cosmetic.
- `app/models/game.rb:58-63` — the
  `value = entry[key].nil? ? entry[key.to_sym] : entry[key]` expression scans
  the hash twice. `entry[key] || entry[key.to_sym]` is shorter and equivalent
  given the `.nil?` guard right after. (False would defeat `||`, but `false` is
  a valid value here, so the original ternary IS correct — actually a real
  reason to keep the verbose form. Skip this suggestion.)
- `app/models/footage.rb:32-38` — `Array(game.platforms).filter_map` works but
  `game.platforms` is already validated to be an Array of Hashes by the
  Game-side validation, so `Array(...)` is belt-and-braces. Drop it for clarity.
  Cosmetic.

### 6. Footage `orientation` enum lacks `validate: true`

```
enum :kind, { a_roll: 0, b_roll: 1 }, validate: true
enum :source, { obs: 0, camera: 1 }, validate: true
enum :orientation, { landscape: 0, portrait: 1 }   # no validate: true
```

Inconsistent with the other two enums, but probably intentional — `kind` and
`source` are required at the API boundary (importer must pass them);
`orientation` is derived from ffprobe and the column is nullable by spec.
Without `validate: true`, an integer outside `{0, 1}` would round-trip through
Rails as `nil` after a refresh (Rails returns `nil` for unknown enum integers).
Practical impact: zero, since the importer is the only writer. Document the
intent — spec §3.4 doesn't actually say "must be one of {landscape, portrait}",
just lists the enum mapping.

## Manual test steps

### Pre-flight

1. **Action:** From the repo root, `git status`. **Expected:**
   - 12 modified tracked files (`.env.example`, `Gemfile`, `Gemfile.lock`,
     `app/models/tenant.rb`, `config/application.rb`, `config/routes.rb`,
     `config/storage.yml`, `db/schema.rb`, `db/seeds.rb`, `docker-compose.yml`,
     `docs/plans/beta/04-project-workspace/log.md`,
     `spec/models/tenant_spec.rb`).
   - ~30 untracked files (7 new models, 7 new factories, 7 new specs, 9
     migrations, voyage flag spec, routing spec, fixture file, this playbook).
   - Branch `main`, working tree dirty (Phase A has not been committed yet).

2. **Action:** `bundle install`. **Expected:** Bundler reports 5 new gems
   resolved cleanly: `aasm 5.5.x`, `image_processing 1.14.x`, `ruby-vips 2.2.x`,
   `commonmarker 2.4.x`, `neighbor 0.6.x`. No native-extension build failures.

3. **Action:**
   `bundle exec ruby -e "require 'rails/all'; puts 'rails loaded ok'"`.
   **Expected:** Prints `rails loaded ok`. **No** `LoadError` for libvips. The
   `require: false` pin on `ruby-vips` ensures Rails boots cleanly even on a
   host without libvips. (On THIS host, libvips IS installed — see concern 2 —
   but the pin is still load-bearing for other hosts.)

4. **Action:** `bin/rails db:drop db:create db:migrate RAILS_ENV=test`.
   **Expected:** Drops and recreates the test DB; runs all migrations including
   the 9 new ones in §3.8 order. `db/schema.rb` is at version
   `2026_05_04_000009`.

5. **Action:**
   `bin/rails db:rollback STEP=9 RAILS_ENV=test && bin/rails db:migrate RAILS_ENV=test`.
   **Expected:** All 9 Phase A migrations roll back cleanly (drops the new
   tables and the `notes_syncing_at` column on `tenants`), then re-apply
   cleanly. **Reviewer ran this live during the pipeline pass — works clean.**

6. **Action:** `bin/rails db:drop db:create db:migrate db:seed`. **Expected:**
   Full seed runs to completion. Heads up: seed is **slow on first run** —
   typically 5–7 minutes because of 100 channels + 250 videos with 90 days of
   stats each. The Phase 4 sample at the end
   (`puts "seeding project workspace sample..."`) takes < 1 second. Re-running
   `bin/rails db:seed` is idempotent and fast (find_or_create_by! everywhere).
   - Sample data after seed: 1 Tenant, 1 User, 100 Channels, 200 Videos with
     stats, 1 Collection ("Demo Collection"), 1 Game ("Demo Game" with cover art
     attached), 1 Project ("Demo Project") with 2 ProjectReferences, 1 Note
     ("Demo note"), 1 Timeline (state `editing`).

### Schema verification

7. **Action:** `bin/rails dbconsole` (or `psql` directly via the docker-compose
   pg). Run, in turn:

   ```sql
   \dx
   \d projects
   \d collections
   \d games
   \d footages
   \d notes
   \d timelines
   \d project_references
   \d active_storage_blobs
   \d active_storage_attachments
   \d active_storage_variant_records
   \d tenants
   ```

   **Expected:**
   - `\dx` lists `citext`, `pgcrypto`, `plpgsql`, `vector` extensions.
   - `\d projects` shows `id`, `tenant_id (NOT NULL)`,
     `name (default 'Untitled project', NOT NULL)`, `concept`, `created_at`,
     `updated_at`; indexes on `tenant_id` and `(tenant_id, name)`; FK to
     `tenants`.
   - `\d games` shows `platforms jsonb DEFAULT '[]'::jsonb NOT NULL` and FKs to
     `tenants` and `collections`.
   - `\d footages` shows `bit_depth integer DEFAULT 8 NOT NULL`,
     `has_commentary_track boolean DEFAULT false NOT NULL`, integer enums for
     `kind`, `source`, `orientation`, and the unique `(tenant_id, local_path)`
     index.
   - `\d notes` shows `embedding vector(1024)` (the limit-1024 pgvector type)
     and the unique `(tenant_id, path)` index.
   - `\d timelines` shows `state integer DEFAULT 0 NOT NULL` and an index on
     `state`.
   - `\d project_references` shows `referenceable_type varchar NOT NULL`,
     `referenceable_id bigint NOT NULL`, the unique
     `(project_id, referenceable_type, referenceable_id)` index, and the
     `(referenceable_type, referenceable_id)` lookup index.
   - `\d tenants` shows `notes_syncing_at timestamp(6) without time zone`
     (nullable).
   - All three `active_storage_*` tables present.

8. **Action:** From psql, query
   `SELECT format_type(atttypid, atttypmod) FROM pg_attribute WHERE attrelid = 'notes'::regclass AND attname = 'embedding';`
   **Expected:** Single row, `vector(1024)`. (Reviewer ran this — verified.)

### Model layer (from `bin/rails console`)

9. **Action:** `bin/rails console`, then:

   ```ruby
   tenant = Tenant.find_or_create_by!(name: "ManualReview")
   project = Project.create!(tenant: tenant)
   project.name           # => "Untitled project"
   project.concept        # => nil
   ```

   **Expected:** Creates without explicit name. Default-create works.

10. **Action:**

    ```ruby
    collection = Collection.create!(tenant: tenant)
    collection.name        # => "Untitled collection"
    game = Game.create!(tenant: tenant, collection: collection,
                        platforms: [{ "platform" => "PS5", "owned" => true, "recorded_on" => true }])
    game.title             # => "Untitled game"
    ```

    **Expected:** Creates without explicit title.

11. **Action:** Validate the platforms allowlist:

    ```ruby
    bad = Game.new(tenant: tenant, platforms: [{ "platform" => "Steam Deck", "owned" => true }])
    bad.valid?             # => false
    bad.errors[:platforms] # => ["[0].platform must be one of PS5, PS4, Xbox Series, ..."]

    nonarray = Game.new(tenant: tenant, platforms: "PS5")
    nonarray.valid?        # => false
    nonarray.errors[:platforms] # => ["must be an array"]
    ```

12. **Action:** Cover-art attach (does NOT generate a variant — that needs
    libvips invoked, which only fires when a variant URL is requested):

    ```ruby
    game.cover_art.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/cover_art.jpg")),
      filename: "cover.jpg",
      content_type: "image/jpeg"
    )
    game.cover_art.attached?   # => true
    File.exist?(ActiveStorage::Blob.service.path_for(game.cover_art.blob.key))
    # => true (file landed under PITO_ASSETS_PATH)
    ```

    Note: actual variant generation (`game.cover_art_thumbnail.processed`) is
    NOT exercised here — that's a Phase B test. Phase A only confirms the attach
    round-trip works.

13. **Action:** Polymorphic project references — explicit construction (the
    spec-correct path):

    ```ruby
    ProjectReference.create!(project: project, tenant: tenant, referenceable: game)
    ProjectReference.create!(project: project, tenant: tenant, referenceable: collection)
    project.games.to_a         # => [game]
    project.collections.to_a   # => [collection]
    ```

14. **Action:** Cross-tenant rejection:

    ```ruby
    other_tenant = Tenant.create!(name: "OtherTenant")
    other_game = Game.create!(tenant: other_tenant,
                              platforms: [{ "platform" => "PC", "owned" => true, "recorded_on" => true }])
    bad = ProjectReference.new(project: project, tenant: tenant, referenceable: other_game)
    bad.valid?                 # => false
    bad.errors[:referenceable] # => ["must belong to the same tenant as the project"]
    ```

15. **Action:** Allowlist rejection:

    ```ruby
    bad = ProjectReference.new(project: project, tenant: tenant,
                               referenceable_type: "Channel", referenceable_id: 1)
    bad.valid?                       # => false
    bad.errors[:referenceable_type]  # => ["is not included in the list"]
    ```

16. **Action (concern 1 verification — known to raise):**

    ```ruby
    project.games << game
    # => ActiveRecord::RecordInvalid: Validation failed: Tenant must exist
    ```

    This is the `ProjectReference#tenant_id` denormalization gap surfaced in
    concern 1 above. Expected to fail today; phase B / refinement decides
    whether to add `before_validation`.

17. **Action:** Footage tenant denormalization:

    ```ruby
    footage = Footage.new(project: project, kind: :a_roll, source: :obs,
                          local_path: "/tmp/x.mp4", filename: "x.mp4")
    footage.valid?         # => true
    footage.tenant_id      # => tenant.id  (filled by before_validation)
    footage.save!
    ```

    The `before_validation :denormalize_tenant_from_project` callback hydrates
    `tenant_id` from the project. Idempotent — passing an explicit
    `tenant: tenant` upfront does not get overridden:

    ```ruby
    explicit = Footage.new(project: project, tenant: tenant, kind: :b_roll, source: :camera,
                           local_path: "/tmp/y.mp4", filename: "y.mp4")
    explicit.valid?
    explicit.tenant_id     # => tenant.id  (the original)
    ```

18. **Action:** Note creation + neighbor wire-up:

    ```ruby
    note = Note.create!(tenant: tenant, project: project, path: "test.md",
                        last_modified_at: Time.current)
    note.title             # => "Untitled note"
    note.embedding         # => nil  (Voyage gating off in dev by default)
    Note.respond_to?(:nearest_neighbors)   # => true (neighbor gem hooked)
    ```

19. **Action:** Timeline aasm machine — linear, no skipping:

    ```ruby
    t = Timeline.create!(tenant: tenant, project: project)
    t.state                          # => "editing"
    t.editing?                       # => true
    t.upload!                        # => raises AASM::InvalidTransition
    t.export!
    t.exported?                      # => true
    t.export!                        # => raises AASM::InvalidTransition (no double-export)
    t.upload!
    t.uploaded?                      # => true
    t.export!                        # => raises AASM::InvalidTransition (no rewind)
    ```

20. **Action:** Cleanup the manual records before exiting the console (or just
    `\q` and `db:drop`/`db:setup` when ready to retry):
    ```ruby
    project.destroy
    game.destroy
    collection.destroy
    other_game.destroy
    other_tenant.destroy
    Tenant.where(name: "ManualReview").destroy_all
    ```

### Voyage flag

21. **Action:** From the shell:

    ```sh
    bin/rails runner 'puts Rails.application.config.voyage_embeddings_enabled'
    ```

    **Expected:** `false` (default in development).

22. **Action:**

    ```sh
    PITO_VOYAGE_ENABLED=true bin/rails runner 'puts Rails.application.config.voyage_embeddings_enabled'
    ```

    **Expected:** `true` (env var overrides the development default).

23. **Action:**
    ```sh
    bundle exec rspec spec/lib/voyage_embeddings_flag_spec.rb
    ```
    **Expected:** 2 examples, 0 failures, < 2s. Confirms the flag defaults to
    false in the test env and the config attribute is exposed.

Note: the test for `PITO_VOYAGE_ENABLED=false RAILS_ENV=production`
override-beats-prod-default is not in the spec suite (production env vars
require a master key handoff). Reviewer skipped it; safe to skip in manual too —
the dev override path covers the same code branch.

### Routes shell

24. **Action:**
    `bin/rails routes | grep -E 'projects|collections|games|footages|notes|timelines|footage_importer|api_project_footages'`.
    **Expected:** RESTful CRUD for `projects`, `collections`, `games`,
    `footages`, `notes`, `timelines`.
    `footage_importer_download GET /footage/importer/download` route shell.
    Nested `api_project_footages GET|POST /api/projects/:project_id/footages`.
    The `:panes` member route on `projects` is NOT present (matches §9.1 — see
    concern 4.1).

25. **Action:**
    ```sh
    bin/rails runner 'puts Rails.application.routes.url_helpers.projects_path'
    ```
    **Expected:** `/projects`. Confirms the named helper resolves before the
    Phase B nav edit fires.

### Active Storage + assets volume

26. **Action:**

    ```sh
    ls $PITO_ASSETS_PATH/ 2>/dev/null || echo 'volume not yet created'
    ```

    **Expected:** Either the directory exists with Active Storage-style
    sub-folders (after step 12 attach) or "volume not yet created" if you
    skipped step 12. Active Storage auto-creates `$PITO_ASSETS_PATH` on first
    attach.

27. **Action:**
    ```sh
    cat .env.development | grep PITO
    ```
    **Expected:**
    ```
    PITO_ASSETS_PATH=tmp/pito-assets
    PITO_NOTES_PATH=tmp/pito-notes
    ```
    Both default to `tmp/` paths inside the repo so `bin/dev` runs without sudo.
    Production (Hetzner) ignores `.env` and falls back to
    `/var/lib/pito-{assets,notes}` via `ENV.fetch` defaults.

### Notes volume layout

28. **Action:**
    ```sh
    ls $PITO_NOTES_PATH/ 2>/dev/null || echo 'notes volume not yet created'
    ```
    **Expected:** Likely "not yet created" — Phase A only adds the env var and
    the docker-compose volume declaration. The actual on-disk layout
    (`<NOTES>/<tenant_id>/projects/<project_id>/<file>.md`) is materialized by
    Phase B's `NoteSyncJob`. The `pito_notes` named volume in
    `docker-compose.yml` is **declared but unmounted** in this phase (Hetzner
    cutover binds it, Phase 16).

### Docker compose volumes

29. **Action:** `docker compose config --services 2>/dev/null` then
    `grep -A 20 '^volumes:' docker-compose.yml`. **Expected:** `volumes:` block
    lists `postgres_data`, `redis_data`, `meilisearch_data`, `pito_notes`,
    `pito_assets`. The two new ones are declared but unmounted in this phase (no
    service `volumes:` entries reference them yet — Hetzner work).

30. **Action (optional, only if you're paranoid):**
    `docker volume ls --filter name=pito | head`. **Expected:** May or may not
    list `pito_notes` / `pito_assets` depending on whether `docker compose up`
    has been re-run since this change. Volumes are lazily created by
    docker-compose; named declarations alone don't materialize them. Not
    blocking.

### MCP regression check (Step 0 + Phase A interop)

31. **Action:** From Claude Mobile (via the existing MCP server at
    `mcp.pitomd.com`), prompt: _"What was I working on last session?"_
    **Expected:** Mobile invokes
    `list_docs(name_pattern: "log.md", sort: "mtime_desc", limit: 1)`. Result
    includes the Phase 4 log (`docs/plans/beta/04-project-workspace/log.md`) at
    the top, with `last_modified_at` reflecting the Phase A append.
    `first_heading` previews the H1.

32. **Action:** Mobile prompt: _"Read the Phase 4 log."_ **Expected:**
    `read_doc(path: "docs/plans/beta/04-project-workspace/log.md")` returns the
    full content, which **includes both** the Step 0 entry (top of file) AND the
    new Phase A entry (bottom). Confirms the append-from-newest-on-the-bottom
    convention is working end-to-end.

### Test suite

33. **Action:** `bundle exec rspec` (full suite). **Expected:** 855 examples, 0
    failures, ~30s. Reviewer ran live and confirmed.

### Cleanup (between retries)

If the user wants to re-test from a clean slate:

```sh
bin/rails db:drop db:create db:migrate db:seed   # ~5–7 min
rm -rf tmp/pito-assets tmp/pito-notes              # Active Storage + notes scratch
```

The unstaged Phase A diff (12 modified + ~30 untracked files) is the architect's
commit candidate — `git status` shows the full picture, and nothing should
disappear until the architect commits.

If the user wants to fully unwind Phase A back to Step 0:

```sh
git restore --source HEAD --staged --worktree -- \
  .env.example Gemfile Gemfile.lock app/models/tenant.rb config/application.rb \
  config/routes.rb config/storage.yml db/schema.rb db/seeds.rb docker-compose.yml \
  docs/plans/beta/04-project-workspace/log.md spec/models/tenant_spec.rb
rm -rf app/models/{project,collection,game,footage,note,timeline,project_reference}.rb \
       db/migrate/2026050400000*.rb \
       spec/{factories,models}/{project,collection,game,footage,note,timeline,project_reference}*.rb \
       spec/factories/{projects,collections,games,footages,notes,timelines,project_references}.rb \
       spec/lib/voyage_embeddings_flag_spec.rb \
       spec/routing/project_workspace_routing_spec.rb \
       spec/fixtures/files/cover_art.jpg
bin/rails db:drop db:create db:migrate db:seed
```

**Confirm with the user before running** — destructive, no git history to
recover from since Phase A has not been committed yet.

## Sign-off checklist

Before the architect commits Phase A:

- [ ] Pre-flight (steps 1–6) green: bundler clean; `db:drop`/`migrate`/`seed`
      runs through; `db:rollback STEP=9` + `migrate` clean both directions.
- [ ] Schema verification (steps 7–8): all 7 new tables + 3 AS tables + the
      `tenants.notes_syncing_at` column shape match §3 of the spec, indexes and
      FKs included; `notes.embedding` is `vector(1024)`.
- [ ] Model layer (steps 9–20): default-create works for Project / Collection /
      Game / Note / Timeline; cover-art attach round-trips; cross-tenant and
      bad-allowlist project_references rejected; Footage tenant denormalization
      fires once and is idempotent; Timeline aasm rejects every invalid
      transition.
- [ ] Voyage flag (steps 21–23): default false in dev/test, env override flips
      to true, spec passes.
- [ ] Routes (steps 24–25): all six new resources + importer download stub +
      nested API helper resolve; no `:panes` member on projects.
- [ ] AS / notes / docker volumes (steps 26–30): env paths default into `tmp/`,
      named docker volumes declared, AS attach lands a file under
      `$PITO_ASSETS_PATH`.
- [ ] MCP regression (steps 31–32): Mobile can `list_docs` the Phase 4 log and
      `read_doc` it to see both Step 0 and Phase A entries.
- [ ] Suite green (step 33): 855 / 0 holds locally.
- [ ] Concerns 1–6 reviewed. User decides which (if any) to dispatch docs-keeper
      or pito-rails to address before commit: - Concern 1: add
      `before_validation` to `ProjectReference` for ergonomic `<<` (recommend
      yes — one-liner). - Concern 2: libvips already installed on this host;
      nothing to do. - Concern 3 + 4.2: spec amendment for `:test` Active
      Storage service carve-out (recommend yes — docs-keeper one-liner). -
      Concern 4.1: spec §13 amendment to drop the `:panes` member on projects
      (recommend yes — docs-keeper one-liner). - Concern 4.3, 4.4, 4.5: Phase B
      work; nothing to do for Phase A. - Concerns 5 and 6: cosmetic, skip.
- [ ] User has explicitly authorized the commit.

## Forward note for Phase B reviewer

Phase B's six parallel workstreams (controllers / views / panes; NoteSyncJob

- cron + lock; `pito footage` subcommand; GitHub Actions; design refresh; ADR
  addendum) all build on this foundation. The Phase B reviewer playbook should:

1. Verify libvips is installed before kicking off cover-art tests
   (`pacman -Q libvips` on Arch / `dpkg -l libvips42` on Debian). On this host
   it's already present (concern 2).
2. Confirm `Notes::EmbedJob` short-circuits when `voyage_embeddings_enabled` is
   false — the flag is wired, the consumer isn't yet.
3. If concern 1 wasn't addressed in Phase A, expect Phase B's controllers to
   construct `ProjectReference` records with explicit `tenant:` parameters
   everywhere `<<` would have been ergonomic.
4. The `voyage:smoke_test` rake task lands in Phase B per concern 4.4.
5. The Video aasm machine (§11.2) lands in Phase B per concern 4.5.
