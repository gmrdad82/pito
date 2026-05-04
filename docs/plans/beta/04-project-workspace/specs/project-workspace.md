# Phase 4 — Project Workspace — Master Spec

> Single authoritative spec for Phase 4. Subagents do not invent scope. Locked
> decisions are pinned exactly — do not reinvent.

---

## 1. Goal

Introduce a Project Workspace so the user can plan a video the way they think
about it: gather game references, dump rough notes, import recorded footage,
assemble timelines that become Videos. Delivers six new models (Project,
Collection, Game, Footage, Note, Timeline), polymorphic project references, a
dedicated assets volume on Active Storage, a notes-on-disk filesystem with
periodic sync, a `pito footage` subcommand on the unified `pito` CLI binary
(ffprobe + API reconcile), and UI chrome — three-pane Project show, nav/footer
entry, design refresh, mobile horizontal-scroll panes.

## 1.1 Prerequisites — user-side setup before implementation

External account / token tasks the user can complete in parallel with the
implementing agents:

1. **Create a Voyage AI account** at https://www.voyageai.com/ (canonical login
   `gmrdad82@gmail.com`).
2. **Generate a Voyage API key** in the dashboard. Copy once — dashboard hides
   it after creation.
3. **Store the Voyage key** under `voyage.development.api_key` and
   `voyage.production.api_key` per §12.6 (same value in both for now).
4. **Repeat for production credentials** at the Hetzner cutover —
   `bin/rails credentials:edit --environment production`.
5. **Create a GitHub PAT** at https://github.com/settings/tokens — "Tokens
   (classic)", scope `repo` (`gmrdad82/pito` is private and the production
   download path reads release assets via the API).
6. **Store the PAT** under `github.development.token` and
   `github.production.token` per §12.6.

Items 1–4 unblock `Notes::EmbedJob` (§3.5 dual-write); items 5–6 unblock the
production download path (§8.3).

## 2. Scope deviations from beta.md and existing plans

- **Phase reuse.** Phase 4 was "Terminal App `pito-sh`" in `beta.md`; the
  terminal app shipped ahead of plan, so the slot now holds Project Workspace.
- **YouTube KB phase dropped.** Phase 9's "YouTube KB + Production Notes" is
  folded in: production notes become Project Notes — scoped per Project, on
  disk, synced into Postgres.
- **Terminal App (Lane 2a) paused.** No standalone TUI work this phase. The
  footage import flow lands as a `pito footage` subcommand of the unified `pito`
  CLI binary at `extras/cli/`, not as a separate crate.
- **MCP (Lane 2b) paused.** No `project:*` MCP tools.
- **ADR 0001 exception (image assets only).** ADR 0001 forbids server-side
  _video_ uploads. Phase 4 adds server-side _image_ uploads (game cover art) via
  Active Storage. Video bytes still never touch Pito; ffprobe runs client-side,
  only metadata travels over the wire. Record a one-line addendum on ADR 0001:
  "image assets excepted — see Phase 4 spec".
- **Polymorphic project references** replace the original "Project belongs to
  Game" idea. A Project can reference any combination of Games and Collections.
- **Notes are flat per project.** No subdirectories. No cross-project note
  browsing.
- **Default-create everywhere.** Project, Collection, Game, Note, Timeline all
  create instantly with "Untitled X" names; edits happen on show pages. No `new`
  forms.
- **Footage importer is Linux-x86_64 only this phase.** Mac and Windows out of
  scope.

The four follow-ups in `docs/orchestration/follow-ups.md` (Channel Revamp
post-commit cleanup, Rails-app keyboard shortcuts, `pito` CLI screen layout
parity, `pito` CLI Dependabot alert #1) all queue strictly AFTER this phase.

## 3. Models and schema

Six new tables plus three Active Storage tables. All tenant-scoped from day one.

### 3.1 `projects`

| Column     | Type   | Constraints                            |
| ---------- | ------ | -------------------------------------- |
| tenant_id  | bigint | not null, fk → tenants                 |
| name       | string | not null, default `"Untitled project"` |
| concept    | text   | nullable; free-form description        |
| timestamps |        |                                        |

Indexes: `(tenant_id)`, `(tenant_id, name)`.

Associations: `has_many :project_references, dependent: :destroy`,
`has_many :games, through:` and `has_many :collections, through:` (polymorphic —
see §4), `has_many :footages, :notes, :timelines` all `dependent: :destroy`.

### 3.2 `collections`

| Column     | Type   | Constraints                               |
| ---------- | ------ | ----------------------------------------- |
| tenant_id  | bigint | not null, fk                              |
| name       | string | not null, default `"Untitled collection"` |
| timestamps |        |                                           |

Indexes: `(tenant_id)`, `(tenant_id, name)`. `has_many :games`.

### 3.3 `games`

| Column        | Type   | Constraints                         |
| ------------- | ------ | ----------------------------------- |
| tenant_id     | bigint | not null, fk                        |
| collection_id | bigint | nullable, fk                        |
| title         | string | not null, default `"Untitled game"` |
| publisher     | string | nullable                            |
| platforms     | jsonb  | not null, default `[]`              |
| timestamps    |        |                                     |

Indexes: `(tenant_id)`, `(collection_id)`, `(tenant_id, title)`.

`platforms` jsonb shape:

```json
[{ "platform": "PS5", "owned": true, "recorded_on": true }]
```

Validation: `platform` must be one of
`["PS5","PS4","Xbox Series","Xbox One","Switch","PC","Mac","Mobile"]`. No
"Other", no free text.

Active Storage: `has_one_attached :cover_art`. Variants: `thumbnail (100x100)`,
`card (300x300)`, `full (resize_to_limit 4096)`. Driven by `image_processing` +
ImageMagick.

### 3.4 `footages`

| Column               | Type     | Notes                                            |
| -------------------- | -------- | ------------------------------------------------ |
| project_id           | bigint   | not null, fk                                     |
| game_id              | bigint   | nullable, fk                                     |
| tenant_id            | bigint   | nullable, fk (denormalized for scoping)          |
| kind                 | integer  | enum `{a_roll: 0, b_roll: 1}` not null           |
| source               | integer  | enum `{obs: 0, camera: 1}` not null              |
| platform             | string   | required when game_id present                    |
| local_path           | string   | not null; unique within tenant                   |
| nas_path             | string   | nullable                                         |
| filename             | string   | not null; derived from path                      |
| description          | text     | markdown source                                  |
| recorded_at          | datetime | defaults to file mtime                           |
| duration_seconds     | integer  | from ffprobe                                     |
| resolution           | string   | e.g. `"1920x1080"`                               |
| fps                  | decimal  | precision 6 scale 3                              |
| codec                | string   |                                                  |
| bit_depth            | integer  | not null, default 8; 8/10/12                     |
| color_profile        | string   | nullable; e.g. `"bt709"`, `"bt2020nc"`           |
| aspect_ratio         | string   | `"16:9"`, `"9:16"`, `"4:3"`, or computed         |
| orientation          | integer  | enum `{landscape:0, portrait:1}`                 |
| audio_track_count    | integer  |                                                  |
| has_commentary_track | boolean  | not null default false; `audio_track_count >= 2` |
| timestamps           |          |                                                  |

Indexes: `(project_id)`, `(game_id)`, `(tenant_id, local_path)` unique,
`(tenant_id)`.

Validations: presence on `kind`, `source`, `local_path`, `filename`;
`local_path` unique per tenant; if `game_id` set, `platform` required AND must
be one of the game's `platforms[].platform` values.

The `orientation` enum is declared without `validate: true` (unlike `kind` and
`source` which both validate). Rationale: the importer derives orientation from
ffprobe `width`/`height` and the column is nullable; an unrecognised file should
still import with `orientation = nil`, not raise. If a future surface lets the
user set orientation explicitly (e.g. an edit form), wrap the assignment in a
custom validation at that surface.

Lifecycle: importer creates / updates / deletes via JSON API. Web UI edits only
fields the importer can't fill — `kind`, `source`, `game_id`, `platform`,
`description`, `nas_path`, `recorded_at`.

**`bit_depth`** is derived inside the importer from ffprobe's `pix_fmt` (e.g.
`yuv420p` → 8, `yuv420p10le` → 10, `yuv420p12le` → 12). `pix_fmt` is not stored
— it's purely intermediate. Default 8 covers SDR + the rare unrecognized case.

**`color_profile`** captures ffprobe's `color_space` (fallback
`color_primaries`). Typical values: `bt709`, `bt2020nc`, `smpte170m`. Nullable:
if ffprobe returns nothing useful, the importer leaves it null and proceeds —
the file MUST still import. Color_profile is metadata-only and never blocks
ingestion. The earlier `pix_fmt` storage column and `dynamic_range` enum are
both DROPPED.

### 3.5 `notes`

| Column           | Type         | Notes                                          |
| ---------------- | ------------ | ---------------------------------------------- |
| tenant_id        | bigint       | not null, fk                                   |
| project_id       | bigint       | not null, fk                                   |
| path             | string       | not null; relative to project root             |
| title            | string       | not null, default `"Untitled note"`; ≤80 chars |
| last_modified_at | datetime     | not null; mirrors file mtime                   |
| embedding        | vector(1024) | nullable; pgvector; dual-write w/ Meilisearch  |
| timestamps       |              |                                                |

Indexes: `(project_id)`, `(tenant_id, path)` unique, `(tenant_id)`. A pgvector
ivfflat or hnsw index on `embedding` is added when the corpus warrants it
(small-N: linear scan is fine).

Disk path: `<NOTES_VOLUME>/<tenant_id>/projects/<project_id>/<path>`. Flat — no
subdirectories.

**Notes vectorization (this phase).** Notes are vectorized via Voyage AI; column
is `embedding` (conventional pgvector name) typed `vector(1024)` for `voyage-3`.
Verify the live model card and pin in `Notes::EmbedJob`.

**Dual-write.** A single `Notes::EmbedJob` (Sidekiq) on note create/update calls
Voyage once and writes the resulting vector to BOTH Meilisearch (hybrid index,
embedding payload alongside indexed text) AND `notes.embedding` in Postgres. One
API call → two stores.

**Routing.** Meilisearch is the entry point for keyword + hybrid queries (BM25 +
vector sim). pgvector handles `<=>` cosine similarity for "similar projects" /
future "similar notes" / "similar videos" features:
`Note.order(Arel.sql("embedding <=> ?", v)).limit(N)`.

**Voyage call gating (2026-05-03 amendment, 2026-05-04 pivoted to AppSetting,
2026-05-04 revamped to encrypted key + per-target flags).** Voyage credentials
live on the existing `app_settings` table as an encrypted column
`voyage_api_key` (Active Record Encryption, probabilistic). The key is
UI-editable via the Settings page (rotates without deploy). On fresh installs /
first seed, the key is bootstrapped from
`Rails.application.credentials.dig(:voyage, Rails.env.to_sym, :api_key)` if
present — credentials remain a fallback path until Hetzner ships (Phase 16), at
which point the AppSetting column becomes the sole authoritative source.

Per-target Boolean flags control what gets indexed. Phase 4 ships one flag —
`voyage_index_project_notes` — defaulting to `false` in all environments.
Production seeds flip it to `true` once a key is in place. Future index targets
add their own flags (e.g. `voyage_index_video_notes`,
`voyage_index_channel_metadata`); the surface scales by adding columns, not by
overloading the existing flag.

A model-level validation links the flags to the key: setting any
`voyage_index_*` flag to `true` requires `voyage_api_key` to be present;
clearing the key while any flag is `true` also fails. The two failure modes
share the same error: "Voyage API key required to enable &lt;target&gt;
indexing."

`Notes::EmbedJob` does a runtime dual-check —
`AppSetting.voyage_indexing_project_notes? && AppSetting.voyage_configured?` —
before any Voyage HTTP call. Either condition false → short-circuit: the note
record still saves, Meilisearch still indexes the text body (BM25 only — no
embedding payload), `notes.embedding` stays NULL, no tokens billed. The
dual-check is intentional belt-and-suspenders; the validation prevents the
broken state at the form boundary, and the job protects against migration drift
/ direct-SQL writes / future bypass paths.

Per project rule, the external boundary (form / JSON / MCP) uses `"yes"` /
`"no"` strings for the flag values; internal storage stays Boolean. The Voyage
API key is a string at the form boundary (sensitive input — password-style,
redacted on display); never serialized to JSON responses, never echoed back in
the HTML body.

A one-shot rake task `bin/rails voyage:smoke_test` (Phase B) performs a single
1-token embedding call, prints HTTP status + embedding dimension + tokens
billed, and exits. Lets the user re-verify the key without flipping the flag.

The previous `Rails.application.config.voyage_embeddings_enabled` /
`PITO_VOYAGE_ENABLED` env-var paths are SUPERSEDED — both have been removed. The
previous single `AppSetting.voyage_embeddings_enabled?` flag is also SUPERSEDED
— replaced by per-target `AppSetting.voyage_indexing_<target>?` accessors and
the `AppSetting.voyage_configured?` helper.

### 3.6 `timelines`

| Column           | Type    | Notes                                    |
| ---------------- | ------- | ---------------------------------------- |
| tenant_id        | bigint  | not null, fk                             |
| project_id       | bigint  | not null, fk                             |
| video_id         | bigint  | nullable, fk → videos; set on `uploaded` |
| title            | string  | not null, default `"Untitled timeline"`  |
| state            | integer | not null, default 0; aasm-managed        |
| duration_seconds | integer |                                          |
| resolution       | string  |                                          |
| fps              | decimal | precision 6 scale 3                      |
| export_filename  | string  |                                          |
| timestamps       |         |                                          |

Indexes: `(project_id)`, `(tenant_id)`, `(state)`. State enum:
`editing:0, exported:1, uploaded:2`. Machine in §11.

### 3.7 Tenant additions

| Column           | Type     | Notes                              |
| ---------------- | -------- | ---------------------------------- |
| notes_syncing_at | datetime | nullable; set when sync job starts |

### 3.8 Migration ordering

1. `enable_pgvector_extension` (`enable_extension "vector"` — required before
   `notes.embedding vector(1024)` migrates).
2. `add_notes_syncing_at_to_tenants`
3. `bin/rails active_storage:install`
4. `create_collections`
5. `create_games` (fk to collections)
6. `create_projects`
7. `create_project_references` (polymorphic — see §4)
8. `create_footages` (fk to projects, optional fk to games)
9. `create_notes` (fk to projects, includes `embedding vector(1024)`)
10. `create_timelines` (fk to projects, optional fk to videos)

## 4. Polymorphic Project references

A Project can reference any combination of Games and Collections (zero, one, or
many of each). Schema is extensible to a third type with only a model + an
allowlist update.

### 4.1 `project_references`

| Column             | Type   | Constraints         |
| ------------------ | ------ | ------------------- |
| tenant_id          | bigint | not null, fk        |
| project_id         | bigint | not null, fk        |
| referenceable_type | string | not null; allowlist |
| referenceable_id   | bigint | not null            |
| timestamps         |        |                     |

Indexes: `(project_id)`, `(referenceable_type, referenceable_id)`,
`(project_id, referenceable_type, referenceable_id)` unique.

### 4.2 Validation

- `referenceable_type` ∈ `["Game", "Collection"]` (strict; reject otherwise).
- The referenced record must share `tenant_id` with the project.

```ruby
class ProjectReference < ApplicationRecord
  belongs_to :project
  belongs_to :referenceable, polymorphic: true
end

class Project < ApplicationRecord
  has_many :project_references, dependent: :destroy
  has_many :games, through: :project_references,
           source: :referenceable, source_type: "Game"
  has_many :collections, through: :project_references,
           source: :referenceable, source_type: "Collection"
end
```

## 5. Active Storage + assets volume

- Install: `bin/rails active_storage:install && bin/rails db:migrate` — adds the
  three AS tables.
- `config/storage.yml` adds a `local` service:

  ```yaml
  local:
    service: Disk
    root: <%= ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets") %>
  ```

- `config.active_storage.service = :local` in all environments. Hetzner swaps
  the same key over to a managed volume.
- **Test environment carve-out (2026-05-04 amendment).**
  `config/environments/test.rb` retains the default
  `config.active_storage.service = :test` (which points at `tmp/storage` per
  Rails's bundled `storage.yml`) for spec isolation — attachment fixtures and
  variant generation in tests write to a per-test ephemeral folder, not to
  `PITO_ASSETS_PATH`. The `:local` directive applies to development and
  production. Hetzner swaps `:local`'s root over to the managed volume; `:test`
  stays untouched.
- Add `image_processing` to the Gemfile. **Use `ruby-vips` (libvips) as the
  variant processor — NOT `mini_magick`.** Local ImageMagick is v7.1.2; the
  `convert` alias is deprecated in IMv7, so `mini_magick` would emit warnings on
  every variant. `ruby-vips` is faster + lower-memory and sidesteps the issue.
  Configure `Rails.application.config.active_storage.variant_processor = :vips`.
- Active Storage current state in `pito` is clean: engine loaded,
  `service = :local` already set in env files, `storage.yml` has default
  services, but no `has_*_attached` declarations or AS tables exist yet.
  `bin/rails active_storage:install` runs cleanly with no conflicts.
- Game variants (`thumbnail`, `card`, `full`) declared on
  `has_one_attached :cover_art`.
- Forward-looking: same volume + AS will hold channel banners, channel avatars,
  video thumbnails when those phases land. Nothing in the storage config is
  cover-art-specific.

## 6. Notes file system + sync + lock

### 6.1 Volume + layout

- Docker named volume `pito_notes`, container mount `/var/lib/pito-notes/`.
- Env var `PITO_NOTES_PATH` (default `/var/lib/pito-notes`) is the only path the
  Rails app reads.
- Layout: `<PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/<file>.md`. Flat
  per project. Project notes pane shows ONLY that project's notes; no
  cross-project browsing.

### 6.2 Web UI lifecycle

- **Create:** `[ new note ]` writes `untitled-note-<unix_ts>.md` (empty file)
  and creates a Note record in one transaction; failure on either side rolls
  back the other.
- **Edit:** project notes pane opens CodeMirror 6 in markdown mode; Save writes
  to disk and updates `last_modified_at`.
- **Rename:** title field rename slugifies + renames the file and updates
  `path`.
- **Delete:** removes file + destroys record.

### 6.3 Sync job

`NoteSyncJob` runs on a Sidekiq cron schedule (default 5 min, configurable in
`sidekiq.yml`). Per tenant:

1. `Tenant#notes_syncing_at = Time.current; save!`.
2. Walk `<PITO_NOTES_PATH>/<tenant_id>/projects/*/*.md` (flat).
3. For each `.md`:
   - File + DB record + `mtime > last_modified_at` → re-parse title, update
     `title` and `last_modified_at`, enqueue `Notes::EmbedJob` to re-embed and
     dual-write to Meilisearch + pgvector (§3.5).
   - File + no DB record → create record (parse title, set `last_modified_at`
     from mtime).
4. DB record without a file → destroy record (hard delete).
5. `ensure { tenant.update!(notes_syncing_at: nil) }`.

### 6.4 Tenant-wide lock

While `Tenant#notes_syncing_at` is present AND within the last 5 minutes
(stale-lock shield): notes pane shows banner "notes are syncing — try again in a
moment"; save buttons disabled (server-side + view); mutating note APIs return
`423 Locked` with `{"error":"notes_syncing","retry_after":30}`. `[ scan now ]`
enqueues `NoteSyncJob.perform_async(tenant_id)` — still subject to the lock next
request.

### 6.5 Title parsing

ATX-style headings only — no other syntax is recognized.

- Read file. Strip leading blank lines.
- If the first non-blank line begins with `# ` (single hash + single space), the
  rest of that line is the title. Truncate to 80 characters for storage and
  display.
- Otherwise, title is `"Untitled note"`.

**Explicitly DROPPED (not parsed, treated as plain content):** Setext underline
headings (`Title\n=====`), Textile / RDoc / org-mode headings, YAML frontmatter
blocks, HTML `<h1>` tags. The single-rule simplicity is deliberate — branchless
parser, trivial user model.

## 7. Footage importer

> **Note (2026-05-04 amendment):** This spec originally specified a separate
> `footage-sync` Rust binary. Mid-implementation the architecture was
> simplified: footage import is now a subcommand (`pito footage`) of the unified
> `pito` CLI binary at `extras/cli/`. The behaviors below remain — only the
> binary name and invocation surface changed.

The footage import flow is a subcommand of the unified `pito` CLI binary at
`extras/cli/`, built with `cargo build --release`. Linux-x86_64 only. The binary
follows the `claude` style — `pito` (no args) launches the TUI client,
`pito help` / `pito version` print metadata, `pito footage <subcommand>` drives
the importer.

**Version output — short Git SHA (2026-05-03 amendment).** Currently
`extras/cli/src/commands/version.rs` prints `pito 0.1.0` from
`env!("CARGO_PKG_VERSION")`. That is replaced — the semver number goes away
entirely, NOT appended.

- `pito --version` and `pito version` print `pito <7-char-sha>`, e.g.
  `pito a2b3c4d`. Both invocations share one code path.
- Mechanism: a `build.rs` (or the `vergen` crate with the `git2` feature —
  cli-impl picks at implementation time and captures the choice as a
  non-blocking decision in the session report) captures the short SHA at compile
  time. Local dev: `git rev-parse --short HEAD`. CI: read `GITHUB_SHA` env var
  and slice to 7 chars. Either path exposes the value via
  `env!("PITO_BUILD_SHA")` (or equivalent constant), which `version.rs` prints.
- Edge cases — left to cli-impl during implementation, do not over-pin here:
  dirty working tree (uncommitted changes) might append a `-dirty` suffix;
  outside a git repo (e.g. someone unpacks the binary outside source control)
  might print `pito unknown`. cli-impl picks the resolution and records it.
- Served binary filename is unaffected: the build artifact and the file the user
  downloads are both literally `pito` — no `-<sha>` suffix on the filename. The
  SHA appears ONLY in version output and in the GitHub Release tag
  (`pito-<sha>`). See §8.1 for the served-filename rule.

### 7.1 CLI

```
pito footage import --project <id> --path <local_dir>
  [--game <id>] [--platform <name>]
  [--kind a_roll|b_roll] [--source obs|camera]
  [--description "..."] [--nas-path <path>] [--dry-run]
```

- Reads `PITO_API_URL` (default `https://app.pitomd.com`) and `PITO_API_TOKEN`.
  Loads `.env` via `dotenvy` (same convention as the rest of the `pito` CLI).
- Flat scan; configurable extensions (default `.mp4 .mov .mkv .avi .webm`).

### 7.2 ffprobe

Per file:
`ffprobe -v quiet -print_format json -show_format -show_streams <file>`.

Toolchain: `ffprobe` at `/usr/bin/ffprobe` (FFmpeg n8.1); importer resolves via
the `which` crate so the "not installed" branch fires cleanly.

**Parsing rules (ffprobe JSON quirks):**

- `r_frame_rate` / `avg_frame_rate` arrive as `"30000/1001"` strings. Parse as
  rationals, round to 3 decimals for `decimal(6,3)`.
- `duration`, `bit_rate` arrive as strings — parse to numeric.
- `width`, `height` are integers. Aspect ratio: compute, reduce by GCD, emit
  canonical `16:9`/`9:16`/`4:3` within ±0.01 tolerance else reduced `W:H`.
  Orientation: landscape when `width >= height`.
- `bit_depth` from `pix_fmt` (never stored): `yuv*p` / `nv12` / `rgb24` → 8;
  `yuv*p10le` / `p010le` → 10; `yuv*p12le` → 12; else default 8. Doc the mapping
  in `probe/ffprobe.rs`.
- `color_profile`: prefer `color_space`; fall back to `color_primaries`; if both
  missing/`unknown`/`reserved`, send `null`. Never invent a value. Rails stores
  the string verbatim (or null). Common values: `bt709`, `bt2020nc`,
  `smpte170m`, `bt470bg`.
- Audio: count `streams[]` where `codec_type == "audio"`.
  `has_commentary_track = (count >= 2)`.
- `recorded_at`: prefer `format.tags.creation_time` when parseable; else file
  mtime.

Extract: duration (rounded seconds); resolution `"WxH"`; fps decimal; video
codec; `bit_depth` (8/10/12 derived from `pix_fmt`, default 8); `color_profile`
(string from `color_space`/`color_primaries`, null when unknown — never blocks
import); aspect ratio (`16:9`, `9:16`, `4:3`, otherwise reduced `W:H`);
orientation (landscape if `width >= height`, else portrait); audio stream count
→ `has_commentary_track = (count >= 2)`; `recorded_at` from format-level
metadata when probable, else file mtime.

If ffprobe is missing (ENOENT) or returns non-zero, print:

```
ffmpeg / ffprobe not found.
Install:
  Debian/Ubuntu: sudo apt install ffmpeg
  macOS (brew):  brew install ffmpeg
  Arch:          sudo pacman -S ffmpeg
```

…and exit non-zero before any HTTP traffic.

### 7.3 Diff classification

1. `GET /api/projects/<id>/footages.json` for existing rows.
2. Identity = `local_path`.
3. Classify per file:
   - **Add:** file on disk, no DB record with that path.
   - **Change:** file + DB record + at least one probed metadata field differs.
   - **Delete:** DB record exists, file missing on disk.

`--dry-run` prints classifications and exits without prompting.

### 7.4 TUI overlays

Mirror `extras/cli/src/ui/confirmation.rs` — three sections (Additions / Changes
/ Deletions), each with count and per-row label. Footer:
`[y] confirm   [any other key] cancel`. `y` confirms; anything else cancels.

Mirror `extras/cli/src/ui/operation_progress.rs` — 4-frame loader top-left,
per-row indicators (`[done]`/`[fail]`/`[skip]`), top-level gauge, final summary
`N added, M changed, K deleted, F failed`.

### 7.5 API

Sequential, one item at a time; on error, mark item failed and continue.

- Add: `POST /api/projects/<id>/footages.json`.
- Change: `PATCH /footages/<id>.json` (unchanged — top-level).
- Delete: `DELETE /footages/<id>.json` (unchanged — top-level).

Booleans serialize as `"yes"`/`"no"` per the project-wide rule (reuse the shared
`yes_no` helper from the `pito` CLI's API layer — see §19).

**(2026-05-04 amendment.)** The collection actions (`POST` index → create, `GET`
index) are namespaced under `/api/` and route to
`app/controllers/api/footages_controller.rb`. The member actions (`PATCH`,
`DELETE`) live at the top level and route to
`app/controllers/footages_controller.rb` because they share the URL surface with
the HTML edit/destroy flow. The asymmetry is intentional but worth revisiting —
see follow-ups.

### 7.6 Tests

`wiremock` (or `httpmock`) integration tests covering: happy path; each diff
branch; ffprobe-missing handling (stub on `PATH`); `--dry-run` no-traffic;
partial failure reflected in exit code.

## 8. CLI build + download — unified Dev/Prod flow

A single controller endpoint serves the unified `pito` CLI binary in both
environments; internal branching on `Rails.env` decides whether to stream a
locally-built artifact or fetch the latest GitHub Release asset. The user runs
`pito footage import <project-slug>` after downloading.

### 8.1 Single controller endpoint

`GET /footage/importer/download` → `FootageImporter::DownloadsController#show`
branches on `Rails.env`: production → §8.3, otherwise → §8.2. Both paths stream
with `Content-Disposition: attachment; filename="pito"` and
`application/octet-stream`. The `[ download cli ]` link on the project footage
pane points at this single action — no view-side env branching.

**Served filename is `pito` (2026-05-03 amendment, restating).** The download
filename stays `pito` regardless of what `pito version` prints. The short SHA
(see §7) lives in version output and in the GitHub Release tag (`pito-<sha>`)
ONLY. `Content-Disposition: attachment; filename="pito"` is the contract on both
the dev and prod download paths.

### 8.2 Development path

`bin/dev` runs the cargo release build as a parallel long-lived process
alongside Rails, Sidekiq, the Tailwind watcher, and the Cloudflared tunnel. A
`Procfile.dev` entry takes care of it:

```procfile
web:        bin/rails server
sidekiq:    bundle exec sidekiq
tailwind:   bin/rails tailwindcss:watch
tunnel:     cloudflared tunnel run pito-dev
cli:        cargo build --release --manifest-path extras/cli/Cargo.toml --message-format short
```

Output binary lives at:

```
extras/cli/target/release/pito
```

In any non-production environment, the controller reads that file directly and
streams it via `send_file` (or `send_data` when the file path is preferred
buffered). If the file does not exist yet (cargo still building on first boot),
respond `503` with
`{"error":"pito_cli_unbuilt","message":"cargo build hasn't finished yet — try again in a moment"}`.
Zero GitHub involvement in dev.

### 8.3 Production path

A GitHub Actions workflow on every push to `main` builds the `pito` CLI for
`linux-x86_64` and publishes a Release tagged `pito-<short-sha>` (7-char commit
SHA prefix) with the binary attached as `pito`. See §12.1.

The controller in `Rails.env.production?`:

1. `GET https://api.github.com/repos/gmrdad82/pito/releases` with
   `Authorization: Bearer <PAT>` + `Accept: application/vnd.github+json`.
2. Filter `tag_name =~ ^pito-`; pick most recent `created_at`.
3. Read the matching asset's API URL (`assets[i].url`, NOT
   `browser_download_url` — the API URL accepts PAT auth for private repos).
4. `GET <asset.url>` with `Accept: application/octet-stream` + PAT; follow any
   302 to a signed URL.
5. Stream bytes back with the same `Content-Disposition`.

PAT auth is required because `gmrdad82/pito` is private. PAT lives in Rails
credentials (§12.6).

### 8.4 Release retention

Keep the latest 5 `pito-*` releases (a request in flight during a deploy must
not 404). Two options: inline `gh release list` +
`gh release delete --cleanup-tag` past 5 at the end of the build workflow, OR
the separate cleanup workflow in §12.5
(`dev-drprasad/delete-older-releases@v0.3.4` or current best-practice).

### 8.5 Forward note — Cloudflare Pages CDN

When `pito-website` launches on Cloudflare Pages, binary distribution may move
there for CDN benefits (cheaper egress, faster TTFB, no PAT in the request
path). Capture in the Phase 16 checklist; no work this phase.

## 9. UI / view changes

### Why no SavedView extension for projects

SavedView bookmarks multi-resource panes URLs (`/channels/panes?ids=...`).
Project's show page has three FIXED panes — Footage, Notes, Timelines — no
URL-driven `?ids=` pattern, nothing to bookmark across projects. The `SavedView`
enum stays `{ channels: 0, videos: 1 }`. No migration. The shared
`.pane-container` / `.pane-wrapper` CSS is reused for the three-pane layout, but
no panes-controller infrastructure is reused.

### 9.1 Three-pane Project show

Same horizontal-pane shell as `/channels/panes` and `/videos/panes`, but the
three panes (Footage / Notes / Timelines) are **fixed**, not URL-driven via
`?ids=`. Project's show page emits three `<div class="pane-wrapper">` blocks
directly, each rendering a dedicated partial:

- `app/views/projects/_footage_pane.html.erb`
- `app/views/projects/_notes_pane.html.erb`
- `app/views/projects/_timelines_pane.html.erb`

No new collection action is needed on `ProjectsController` — the panes belong to
the show page. Reuse the resource-agnostic CSS shell (`.pane-container`,
`.pane-wrapper`, `.pane-arrow*`) as-is. Each pane scrolls independently. Mobile
uses **horizontal scroll** (NOT vertical stack — see §9.2).

**Panes infrastructure cleanup (recommendation, not blocking):** the existing
`ChannelsController#panes` and `VideosController#panes` are near-clones; extract
a `Paneable` concern (id parsing, `@max_panes`, `@pane_title_length`) and a
`shared/_panes.html.erb` partial. Project's show does NOT use the shared panes
partial (Project panes are fixed, not URL-driven).

### 9.2 Drop vertical-stack mobile from existing panes

`/channels/panes` and `/videos/panes` switch to horizontal scroll on mobile with
snap points (one pane per viewport, swipe). Reorder arrows hide on mobile.
Update design.md "Panes (Multi-item View)".

CSS edits in the mobile media query of `application.css`:

- Delete the `.pane-container { flex-direction: column; }` rule and the
  `.pane-wrapper + .pane-wrapper` border-top rule.
- Delete the left/right→up/down arrow visibility swap.
- ADD `.pane-wrapper { min-width: 88vw; flex: 0 0 88vw; }`.
- ADD scroll-snap: `.pane-container { scroll-snap-type: x mandatory; }`,
  `.pane-wrapper { scroll-snap-align: start; }`.

The desktop `.pane-container { display: flex; overflow-x: auto; }` is unchanged
— the mobile override is the only delta.

### 9.3 Saved views horizontal scroll (global rule)

Saved-views chip lists (channels, videos, projects, future) scroll horizontally
on desktop and mobile. No wrapping. Document in design.md as a global rule.

Edits in `SavedViewsSectionComponent` + CSS:

- ADD `.saved-views-list`
  (`display: flex; flex-wrap: nowrap; gap: 16px; overflow-x: auto; max-width: 100%`)
  and `.saved-views-row`
  (`display: flex; align-items: baseline; gap: 6px; white-space: nowrap; flex: 0 0 auto`).
- In the partial, wrap the `each` loop in `<div class="saved-views-list">` and
  swap each row's inline `style=` for `class="saved-views-row"`.
- Drop the dialog's `min-width` to ~320px (keep `max-width: 90vw`).

Use `flex-wrap: nowrap` deliberately — the existing mobile rule that forces 100%
width on flex-wrap children would defeat horizontal scroll if `wrap` crept in.
Existing dialog open/close JS, delete + ConfirmModalComponent per row, label
rendering, save-inverse on `/panes` all preserved.

### 9.4 Nav additions

Header and footer get `[projects]` AFTER `[videos]`. Final order:
`[home] · [channels] · [videos] · [projects] · [settings]`. Both nav rows are
inline in `layouts/application.html.erb`; the existing `nav_link` helper
auto-highlights on `/projects/...`. Insert
`<%= nav_link "projects", projects_path %>` between the videos and settings
links in both the header and footer rows.

**Prerequisite:** `resources :projects` must land in `config/routes.rb` before
the nav edit, otherwise `projects_path` raises (§14 step ordering).

### 9.5 CodeMirror 6

Used in two places: Footage description (DB markdown) and Note contents (file
markdown). Plain markdown mode only — no language extensions, no preview pane.
Stimulus controller `codemirror_controller.js` mounts on a textarea and syncs on
submit. Styling honours design.md (monospace, theme CSS vars).

### 9.6 Markdown rendering for notes

Use `commonmarker` (GitHub-flavored markdown — pick this one and document the
choice in the Gemfile comment). Render server-side; sanitize via Rails
`sanitize` with the default allow-list extended for code blocks.

## 10. Design refresh — 7 rules

Update `pito/docs/design.md` (docs-keeper writes it). Baseline: color tokens in
`application.css:4-82`, single monospace stack, body 13px/1.4, two weights
(400 + 700). Drift status per rule below.

1. **Links + buttons → bold (current blue).** Compliant. Snippet:
   `a, .bracketed, button[type="submit"] { font-weight: 700; }`.
2. **Destructive (red) → bold.** Compliant.
3. **UI text muted: 2 weights (bold + normal); muted is a color, not a weight.**
   Partial. ADD `.text-muted-bold` utility. Snippets:
   `.text-muted { color: var(--color-muted); font-weight: 400; }` /
   `.text-muted-bold { color: var(--color-muted); font-weight: 700; }`.
4. **Hints, captions, form helper text → muted + italic.** Drift — helper text
   is muted but not italic. Introduce `.form-hint` / `.caption` with italic.
   Update hint sites in `channels/_form`, `layouts/application` (search hint),
   `search/show`, `channels/_picker`, `dashboard/index`, `channels/_pane`,
   `channels/_add_pane_dialog`. Per-field errors in `form_field_component` stay
   danger-colored (errors are not hints). Snippet:
   `.form-hint, .caption { color: var(--color-muted); font-style: italic; }`.
5. **Flash notice and errors** stay as currently styled. Compliant.
6. **User content NEVER muted, NEVER italic.** Latent risk: global `h4` is
   italic. Remove `font-style: italic` from global `h4` (or restrict to
   `.h4-emphasis`); audit `<h4>` use for user content and reroute. Add a
   "Content Rules" subsection in design.md.
7. **Table headers muted, row values normal.** Drift — `th` currently uses
   `--color-text-bold` + 600. Switch `th` to muted + 700. Snippets:
   `thead th { color: var(--color-muted); font-weight: 700; }` /
   `tbody td { color: var(--color-text); font-weight: 400; }`.

**Adjacent cleanup folded into the refresh:**

- Dashboard chart hex colors → CSS chart vars.
- `bracketed_link_component` inline-style active state → `.bracketed-active`.
- `form_field_component` + `settings/index` inline label styles → `.form-label`.

## 11. State machines (aasm gem)

Add `aasm` to the Gemfile.

### 11.1 Timeline — `editing → exported → uploaded` (linear, no skipping)

```ruby
class Timeline < ApplicationRecord
  include AASM
  aasm column: :state, enum: true do
    state :editing, initial: true
    state :exported
    state :uploaded
    event(:export)  { transitions from: :editing,  to: :exported  }
    event(:upload)  { transitions from: :exported, to: :uploaded  }
  end
end
```

When `upload` fires, the caller passes a YouTube URL; the transition creates or
links a `Video` record and stores its id in `timelines.video_id`.

### 11.2 Video

`scheduled → published → unpublished` on `videos.privacy_status` (existing
integer). Standard aasm shape: `:scheduled` initial, `:publish` from
`:scheduled` to `:published`, `:unpublish` from `:published` to `:unpublished`.
Confirm enum mapping before adding aasm.

## 12. CI per repo

### 12.1 `pito` — `.github/workflows/ci.yml`

On every push: Postgres 17 service container; `ruby/setup-ruby@v1` with
`bundler-cache: true`; install `ffmpeg` + `imagemagick` via apt;
`bin/rails db:create db:migrate db:seed`; `bundle exec rspec`;
`bundle exec brakeman --quiet`; `bundle exec bundler-audit check --update`;
`bundle exec rubocop || true` (skip if not configured); then
`dtolnay/rust-toolchain@stable`,
`cargo build --release --manifest-path extras/cli/Cargo.toml`,
`cargo test --manifest-path extras/cli/Cargo.toml`.

On every push to `main` (separate workflow, runs in parallel with the test job):
`dtolnay/rust-toolchain@stable`, then
`cargo build --release --manifest-path extras/cli/Cargo.toml`, copy
`target/release/pito` to `dist/pito`, and publish with
`softprops/action-gh-release@v2` using a tag of `pito-${GITHUB_SHA:0:7}` (the
7-char short SHA), name `pito ${GITHUB_SHA:0:7}`, and `files: dist/pito`. After
publish, the cleanup workflow (§12.5) prunes older releases.

### 12.2 (reserved)

The terminal-app CI block previously documented under `pito-sh` is folded into
§12.1. The unified `pito` CLI at `extras/cli/` is built and tested in the single
Rails-side workflow alongside the Rails test matrix. No separate repo, no
separate workflow.

### 12.3 `pito-website` — `.github/workflows/ci.yml`

On every push: `actions/setup-node@v4`; `npx --yes prettier --check '**/*.md'`.
Future: build pipeline when actual code lands.

### 12.4 `pito-dev-kb` — `.github/workflows/ci.yml`

Same as 12.3. Optional follow-up: `markdownlint` if installable and not too
noisy.

### 12.5 `pito` — `.github/workflows/pito-cli-cleanup.yml`

A separate workflow trims the `pito-*` release backlog to the latest 5 entries:

```yaml
# .github/workflows/pito-cli-cleanup.yml
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
jobs:
  prune:
    runs-on: ubuntu-latest
    steps:
      - uses: dev-drprasad/delete-older-releases@v0.3.4
        with:
          keep_latest: 5
          delete_tag_pattern: ^pito-
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Implementer note: pin to whatever version is current and well-maintained at
build time — `dev-drprasad/delete-older-releases` is one option; a small inline
`gh release list` + `gh release delete` script is another. Either way the
contract is the same: keep the newest 5 `pito-*` releases and tags, delete the
rest.

## 12.6 Credentials structure — per-environment nested

All Phase 4 secrets live in Rails encrypted credentials, NOT `.env`. Mirrors the
existing `:postgres` per-environment nesting pattern.

### Layout

```yaml
# bin/rails credentials:edit --environment development
github:
  development:
    token: ghp_xxxxxxxxxx
  production:
    token: ghp_xxxxxxxxxx

voyage:
  development:
    api_key: pa-xxxxxxxxxx
  production:
    api_key: pa-xxxxxxxxxx
```

Both blocks (`github`, `voyage`) live in BOTH
`config/credentials/development.yml.enc` AND
`config/credentials/production.yml.enc`. For Phase 4 — single user, both envs
hit the same external services — the sub-keys can hold the same value. Keeping
both branches in both files preserves the structure for the day a rotation
diverges.

### Code access

Always `Rails.application.credentials.dig` with `Rails.env.to_sym`:

```ruby
Rails.application.credentials.dig(:github, Rails.env.to_sym, :token)
Rails.application.credentials.dig(:voyage, Rails.env.to_sym, :api_key)
```

A small `PitoCredentials` helper module that centralises the dig calls and
raises clearly on missing keys is acceptable.

### Implementation steps (credentials)

1. `bin/rails credentials:edit --environment development` → add both blocks with
   both sub-keys.
2. `bin/rails credentials:edit --environment production` → same shape, same
   values for now.
3. Commit the `*.yml.enc` files; master keys stay out of git.
4. Confirm `.gitignore` covers `config/master.key` and
   `config/credentials/{development,production}.key`.
5. Document `RAILS_MASTER_KEY` handoff for Hetzner in `docs/setup.md`.

`.env` continues to hold non-secrets only (`PITO_ASSETS_PATH`,
`PITO_NOTES_PATH`, optional `PITO_API_URL`). Any earlier draft references to
`GITHUB_TOKEN` / `VOYAGE_API_KEY` as env vars are superseded.

## 13. Files touched

### `pito` repo

- **Migrations** (§3.8 order): `enable_pgvector_extension`,
  `add_notes_syncing_at_to_tenants`, AS install, `create_collections`,
  `create_games`, `create_projects`, `create_project_references`,
  `create_footages`, `create_notes`, `create_timelines`.
- **Models:** `project.rb`, `collection.rb`, `game.rb`, `footage.rb`, `note.rb`,
  `timeline.rb`, `project_reference.rb`; update `tenant.rb`.
- **Controllers:** `projects_controller`, `collections_controller`,
  `games_controller`, `footages_controller`, `notes_controller` (HTML + JSON),
  `timelines_controller`, `footage_importer/downloads_controller`,
  `api/projects/footages_controller` (importer endpoint).
- **Views (ERB):** per-resource folders for the six new resources;
  `shared/_header` + `_footer` add `[projects]`; `channels/panes` and
  `videos/panes` drop vertical stack + add horizontal scroll.
- **Jobs:** `note_sync_job.rb`; `notes/embed_job.rb` (Voyage call + Meilisearch
  upsert + pgvector update); `config/sidekiq.yml` cron 5 min.
- **Stimulus:** `codemirror_controller`, `horizontal_panes_controller`.
- **Routes:** `resources :projects do member { get :panes } end`; the other five
  resources; importer download route; nested API `api/projects/:id/footages`.
- **Config:** `storage.yml` `local` + `PITO_ASSETS_PATH`; AS service config;
  Gemfile adds `image_processing`, `aasm`, `commonmarker`, `neighbor` (pgvector
  AR bridge); `.env.example` adds `PITO_ASSETS_PATH`, `PITO_NOTES_PATH`. Secrets
  per §12.6.
- **Procfile.dev:** add `cli:` entry (cargo release build of the unified `pito`
  binary) alongside `web`, `sidekiq`, `tailwind`, `tunnel` (§8.2).
- **Specs (RSpec):** model specs (six new + `ProjectReference`); request specs
  per controller; job spec for `NoteSyncJob` and `Notes::EmbedJob`; system spec
  for the three-pane Project show.
- **Unified CLI crate (`extras/cli/`):** new `pito footage` subcommand module —
  `src/footage/mod.rs`, `src/footage/api/*`, `src/footage/probe/*`,
  `src/footage/diff.rs`, `src/footage/ui/*`, `tests/footage_integration.rs`.
  Subcommand wiring lands in the existing `src/main.rs` clap dispatch alongside
  `pito help` / `pito version` and the default TUI entry.
- **Docs (docs-keeper):** `docs/design.md` (refresh + panes + saved views),
  `docs/architecture.md` (Project Workspace, AS, notes, `pito footage`
  subcommand), `docs/setup.md` (env vars, volumes, ffmpeg, master keys); phase
  log.

### Other surfaces

- **`extras/cli/` (unified `pito` CLI):** the only Rust crate touched. The Phase
  4 work adds the `pito footage` subcommand; the default TUI entry and
  `pito help` / `pito version` surfaces are unchanged.
- **`extras/website/`:** `.github/workflows/ci.yml` — prettier check (when the
  website surface lands).
- **dev-kb material under `docs/`:** `.github/workflows/ci.yml` — prettier
  check; `docs/decisions/0001-no-server-side-uploads.md` — one-line addendum;
  this spec; `docs/plans/beta/04-project-workspace/log.md` (on completion).

## 14. Implementation steps

### Step 0 — MCP Dev KB surface (precedes Phase A)

Three MCP tools (`list_docs`, `read_doc`, `save_note`) expose the `docs/` tree
to Claude Mobile and capture on-the-road notes into `docs/notes/`. Lands BEFORE
Phase A so the conversation flow between Desktop and Mobile is open by the time
Phase A's foundation work begins. Owner: `mcp-impl` (single-agent dispatch).
Sibling spec: `specs/mcp-dev-kb-surface.md`. Recorded in `additions.md` as a
2026-05-04 scope addition.

### Phase A — foundation (sequential, pito-rails)

1. `add_notes_syncing_at_to_tenants` migration → tenant holds sync lock state.
   Rollback: drop column.
2. `bin/rails active_storage:install` + migrate → AS tables exist. Rollback:
   drop AS migration.
3. Create migrations for the new models in §3.8 order → schema ready. Rollback:
   drop in reverse.
4. Implement models (associations, validations, enums) → model layer compiles,
   model specs green. Rollback: revert model files.
5. Add `image_processing`, `aasm`, `commonmarker` gems → bundler clean.
   Configure `Rails.application.config.active_storage.variant_processor = :vips`
   (NOT `:mini_magick` — see §5). Rollback: revert Gemfile.lock.
6. Configure `storage.yml` + `PITO_ASSETS_PATH` → AS reads from assets volume.
7. Mount `pito_notes` and assets volumes (Docker compose); document
   `PITO_NOTES_PATH` / `PITO_ASSETS_PATH` defaults.
8. Add `resources :projects` (and the rest of the new resources, plus the
   importer download route) to `config/routes.rb`. **This must land BEFORE the
   header/footer nav edit in Phase B**, otherwise `projects_path` raises
   `NoMethodError` at request time. Verify with
   `bin/rails routes | grep projects`.
9. Factories + seeds (Project, Game w/ cover, Note, Timeline) →
   `bin/rails db:seed` produces a working sample.

### Phase B — parallel (after Phase A on `main`)

| Workstream                            | Owner agent | Scope                                                                                                                                                                                                                                                            |
| ------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Controllers, views, Stimulus          | pito-rails  | Controllers, ERB, panes, CodeMirror, nav update                                                                                                                                                                                                                  |
| `NoteSyncJob` + cron + lock UX        | pito-rails  | Job + sidekiq.yml + view-side disabled state                                                                                                                                                                                                                     |
| `pito footage` subcommand (Rust)      | cli-impl    | `extras/cli/src/footage/**` + tests                                                                                                                                                                                                                              |
| GitHub Actions (single workflow)      | pito-rails  | `.github/workflows/ci.yml` + cleanup workflow                                                                                                                                                                                                                    |
| Design refresh (design.md)            | docs-keeper | 7 rules + panes + saved views                                                                                                                                                                                                                                    |
| ADR 0001 addendum                     | docs-keeper | One-line carve-out                                                                                                                                                                                                                                               |
| Phase log                             | docs-keeper | `04-project-workspace/log.md`                                                                                                                                                                                                                                    |
| `parallel_tests` test parallelization | pito-rails  | Add `parallel_tests` gem to `:development, :test`. Per-process Postgres DBs (`pito_test_<N>`). `bundle exec parallel_rspec spec/`. CI `rails` job uses parallel runner. Combined with the GitHub Actions workstream since both touch `.github/workflows/ci.yml`. |

The `parallel_tests` workstream lands alongside the GitHub Actions workstream
because both edit `.github/workflows/ci.yml` (the `rails` job invocation changes
from `bundle exec rspec` to `bundle exec parallel_rspec`). Local setup creates
per-process Postgres DBs via `parallel_tests:setup`. Spec distribution defaults
to alphabetical-by-filename; `--group-by runtime` can be evaluated later if
balance becomes an issue. Sequential Phase A baseline: 855 examples in ~27s;
target post-parallelization: ~7-10s on a 4-core host. The previous follow-up
entry on this topic has been promoted into this Phase B workstream —
`follow-ups.md` no longer contains it.

Reviewer agent runs after Phase B converges. Manual test playbook lands in
`docs/orchestration/playbooks/<date>-project-workspace.md`.

## 15. Acceptance criteria

- [ ] Migrations apply on fresh DB; `bin/rails db:setup` produces §3 schema.
- [ ] Default-create works for Project, Collection, Game, Note, Timeline (no
      forms; instant `"Untitled X"`).
- [ ] Project show page renders three panes (Footage / Notes / Timelines)
      horizontally on desktop and on mobile.
- [ ] `[projects]` appears in header and footer AFTER `[videos]`.
- [ ] `/channels/panes` and `/videos/panes` mobile layouts use horizontal scroll
      (no vertical stack).
- [ ] Saved-views chip lists scroll horizontally everywhere.
- [ ] Polymorphic project references: 0+ Games and 0+ Collections per Project;
      non-allow-listed types and cross-tenant records are rejected.
- [ ] Game cover art uploads via Active Storage; three variants render.
- [ ] Footage rows carry §3.4 fields, including audio + `bit_depth` + optional
      `color_profile` (null when ffprobe returns nothing useful).
- [ ] Note titles parse from first `# ` heading; fallback `"Untitled note"`.
- [ ] `NoteSyncJob` reconciles disk ↔ DB with add/change/delete branches
      exercised by spec.
- [ ] Tenant-wide lock disables note edits while `notes_syncing_at` is recent (≤
      5 min). `[ scan now ]` enqueues immediately.
- [ ] `pito footage import` runs `ffprobe`, classifies add/change/delete,
      prompts, shows progress, posts to API. Booleans serialize as
      `"yes"`/`"no"`.
- [ ] `pito footage import` prints clear ffmpeg-install hint on missing binary.
- [ ] `GET /footage/importer/download` streams the local cargo-built binary in
      development and the latest `pito-<sha>` release asset (PAT auth) in
      production. Both paths return `Content-Disposition` with
      `filename="pito"`.
- [ ] `Notes::EmbedJob` dual-writes the Voyage embedding to BOTH Meilisearch and
      the `notes.embedding` pgvector column on note create/update.
- [ ] `Notes::EmbedJob` no-ops when AppSetting Voyage gating (key + per-target
      flag) is not satisfied — specifically, when
      `AppSetting.voyage_indexing_project_notes?` is false OR
      `AppSetting.voyage_configured?` is false (default in development and
      test): note save and Meilisearch text-only indexing still complete
      cleanly, no Voyage HTTP call fires, `notes.embedding` stays NULL. The flag
      and key are runtime-mutable via Settings UI / direct AppSetting update in
      any environment.
- [ ] `bin/rails voyage:smoke_test` (Phase B) runs a single 1-token embedding
      call, prints HTTP status + embedding dimension + tokens billed, and exits.
- [ ] Validation rejects enabling any `voyage_index_*` flag without a key, AND
      rejects clearing the key while any flag is true. Settings UI surfaces the
      validation error in flash.
- [ ] `voyage_api_key` is encrypted at rest (Active Record Encryption); raw DB
      blob is ciphertext, not the plaintext key. Settings page response body
      never carries the plaintext.
- [ ] `pito version` and `pito --version` print `pito <7-char-sha>` for both dev
      and CI builds. Served binary filename remains `pito` in all paths (dev
      `send_file`, prod GitHub Release asset stream).
- [ ] `aasm` machines on Timeline (editing → exported → uploaded) and Video
      (scheduled → published → unpublished) reject invalid transitions.
- [ ] design.md captures the 7 rules with code snippets.
- [ ] CI workflow passes (Rails matrix + `extras/cli` Rust matrix in the single
      workflow).
- [ ] RSpec, Brakeman, bundler-audit clean on `pito`.
- [ ] ADR 0001 has the one-line "image assets excepted" addendum.

## 16. Manual test recipe

1. **Fresh schema.** `bin/rails db:drop db:create db:migrate db:seed`. Seed
   produces one Project (`"Untitled project"`) attached to a Game with cover art
   and a Collection.
2. **Default-create.** From `/projects`, `[ new project ]` → instant new
   `"Untitled project"`, no form. Repeat for Collection, Game, Note, Timeline.
3. **Three panes.** Open seeded project → Footage / Notes / Timelines panes
   side-by-side on desktop; resize to mobile → horizontal scroll with snap.
4. **Nav.** Header + footer show `[projects]` after `[videos]`; routing works.
5. **Existing panes mobile fix.** `/channels/panes` and `/videos/panes` at
   mobile width: horizontal scroll, no vertical stack.
6. **Saved views.** Chip lists scroll horizontally on desktop and mobile.
7. **Game cover art.** Edit a game; upload a JPEG → variants render at the right
   sizes; data under `$PITO_ASSETS_PATH`.
8. **Notes lifecycle.** Create a note → file at
   `$PITO_NOTES_PATH/<tenant>/projects/<pid>/<file>.md`. Edit in CodeMirror;
   save → mtime + `last_modified_at` update.
9. **First-H1 title.** Add `# Hello world`; next sync updates title. Remove
   heading; falls back to `"Untitled note"`.
10. **Sync job.** `touch $PITO_NOTES_PATH/<tenant>/projects/<pid>/foo.md`, then
    `[ scan now ]` → Note record appears.
11. **Sync lock.** Set `Tenant.update(notes_syncing_at: Time.current)`; open
    notes pane → banner shows, save buttons disabled, POST returns 423.
12. **Footage importer.** Place 3 mp4s in a dir; run
    `pito footage import --project <id> --path <dir>` → ffprobe runs; TUI
    confirmation lists 3 additions; `y` confirms; progress shows `[done]`; rows
    appear.
13. **Importer change/delete.** Re-encode one mp4 (res change), delete another,
    re-run → Change + Delete sections appear.
14. **Importer ffmpeg-missing.** Rename `ffprobe` on PATH; re-run → install
    hint, non-zero exit.
15. **CLI download link.** Dev: `bin/dev` running, cargo build done,
    `[ download cli ]` streams from `extras/cli/target/release/pito` (no GitHub
    call). Prod: same link pulls the latest `pito-<sha>` release asset via the
    GitHub API with PAT auth.
16. **Timeline state machine.** Create a timeline; `upload!` rejected (must
    `export!` first). Export, then upload with a YouTube URL → Video created and
    linked.
17. **Design refresh.** Any page: links bold, destructive bold, table headers
    muted, row values normal, hints italic, user content untouched.

## 17. Risks and open questions

- **pgvector dimension** for `notes.embedding` — pinned to `vector(1024)` for
  `voyage-3`. If the implementer picks a different Voyage model, update the
  migration AND `Notes::EmbedJob` in the same commit; dim mismatch is a hard
  insert error.
- **CodeMirror 6 packaging** with importmap/propshaft may need a small esbuild
  bridge. Worst case: vendor a precompiled bundle.
- **Sync lock granularity.** 5-min window can race long syncs on slow volumes;
  watch in dev, tune if needed.
- **GitHub release tag shape.** Controller filters `^pito-` from
  `gmrdad82/pito`; if the repo moves, update the controller constant.
- **`commonmarker` vs `redcarpet`.** Spec picks `commonmarker` for GFM parity;
  pivot if install pain.
- **AS variant generation cost.** Cover-art uploads are small enough for
  synchronous variant generation; revisit only if game lists feel slow.

## 18. Out of scope

- User auth / sessions / login UI (Phase 12).
- YouTube API integration of any kind (Phase 7+).
- Video upload flow — still browser-side per ADR 0001.
- Channel notes (replaced by project notes; not reintroduced).
- Standalone TUI changes (paused — no Lane 2a). Phase 4 only adds the
  `pito footage` subcommand; the default TUI entry of the unified `pito` CLI is
  untouched.
- MCP changes (paused — no Lane 2b).
- Multi-platform builds for the unified `pito` CLI (linux-x86_64 only).
- Hybrid search UX surface (the embedding column populates this phase via
  dual-write to Meilisearch + pgvector; the search/similarity views ship with
  Phases 9–10).
- Soft-delete semantics on notes (hard delete only).
- Cross-project note browsing UI.
- Note attachments / inline images.
- In-Pito timeline editing UI (state machine + metadata only; editing happens in
  DaVinci Resolve / equivalent).

## 19. Shared modules inside `extras/cli/`

The `pito footage` subcommand reuses — by direct import, not copy-paste — the
existing TUI client modules already present in `extras/cli/`:
`src/api/yes_no.rs` (verbatim helper), `src/api/http_client.rs`, portions of
`src/api/models.rs` (types the footage flow needs), `src/ui/confirmation.rs`
(re-skinned for 3-section diff), and `src/ui/operation_progress.rs` (same
animation, footage labels). Because everything lives in one crate, "drift" is no
longer a concern — shared code is shared by `use crate::…` rather than parallel
files.

**`pito footage` module dependencies (incremental over the existing TUI
crate):** `which` (PATH fallback for ffprobe), `std::process::Command`, plus
whatever footage-specific structs land under `extras/cli/src/footage/`. The
existing crate-level deps (`serde`, `serde_json`, `dotenvy`, `reqwest`,
`anyhow`/`thiserror`, `clap`, `crossterm`/`ratatui`) cover everything else.
Toolchain: `rustc 1.95.0`, `cargo 1.95.0`.

## 20. Forward-looking

- **Hetzner volumes.** `pito_notes` and `pito_assets` translate to Hetzner
  managed volumes in Phase 16. Storage and notes paths are env-driven so the
  cutover is config, not code.
- **Shared Rust modules.** Now that everything lives in one crate
  (`extras/cli/`), shared modules (`yes_no`, `http_client`, parts of `models`,
  `confirmation`, `operation_progress`) are imported directly via
  `use crate::…`. The earlier "extract a shared crate when a third copy appears"
  follow-up is moot — there are no copies to begin with.
- **CI cross-platform.** Linux-x86_64 is enough today. Mac (Apple Silicon) and
  Windows builds get added in the Theta era or sooner if a contributor needs
  them.
- **Notes hybrid search UX.** `notes.embedding` is populated this phase via
  `Notes::EmbedJob` (dual-writing to Meilisearch + pgvector). Phase 9 wires the
  search query surface (hybrid keyword + vector via Meilisearch) and Phase 10
  wires "similar X" pgvector cosine queries into the UI.
- **Project search.** Hybrid search across notes + footage descriptions lands
  with Phase 10.
- **Queued follow-ups.** The four open items in
  `docs/orchestration/follow-ups.md` (Channel Revamp post-commit cleanup,
  Rails-app keyboard shortcuts, `pito` CLI screen layout parity, `pito` CLI
  Dependabot alert #1) all queue strictly AFTER this phase closes.
