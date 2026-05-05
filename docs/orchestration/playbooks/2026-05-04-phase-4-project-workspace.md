# Manual test playbook — Phase 4 Project Workspace (Phase B)

**Repo:** `pito` (monolith) at `/home/catalin/Dev/pito` **Spec:**
`docs/plans/beta/04-project-workspace/specs/project-workspace.md` **Log:**
`docs/plans/beta/04-project-workspace/log.md` (entries
`2026-05-04 — Phase B — pito footage subcommand` through
`2026-05-04 — Phase B — Closing summary`) **Reviewer run:** 2026-05-04 04:55
local

This is the user's chance to validate Phase B before the architect commits.
Phase B shipped four parallel implementation lanes plus a documentation pass:
the `pito footage` Rust subcommand, the Rails app surface (controllers + views

- Stimulus + jobs + lock UX), the §10 design refresh CSS, and the GitHub Actions
  / `parallel_tests` work — on top of the Phase A foundation that's already on
  `main` (`0079999`).

**Read this first.** One blocker surfaced — a wire-shape mismatch between the
Rust importer client and the Rails API routes. The fix is a 1-line URL change in
the Rust client (and the corresponding integration-test path strings). Details
in the Blockers section below; the user does NOT validate the importer
end-to-end until that is resolved.

## Pipeline summary

| Gate                                                             | Status      | Notes                                                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 `/code-review` on the diff (`0079999..HEAD`)                   | **PARTIAL** | One blocker (wire-shape mismatch between `pito footage` Rust client and Rails API routes — see Blockers). Six non-blocking observations in Concerns.                                                                                                                                       |
| 2 `/simplify` on the diff                                        | PASS\*      | Three small candidates — none warrant a fix-up dispatch. See concern 7.                                                                                                                                                                                                                    |
| 3 `bundle exec rspec` (full suite, single-process)               | **PASS**    | 945 examples, 0 failures, 29.3s. Matches Phase B `#app` and `#styling` reports; +83 vs Phase A's 862 / 0.                                                                                                                                                                                  |
| 4 `bundle exec parallel_rspec spec/`                             | **PASS**    | 945 / 0 in 11s wall (vs 29.3s single-process) — ~2.7× speedup on this 20-core host. Matches log's reported delta.                                                                                                                                                                          |
| 5 `bin/brakeman --no-pager -q`                                   | **PASS**    | 0 errors, 0 security warnings. 18 controllers, 22 models, 58 templates scanned. The Notes path-handling code (`app/lib/notes_filesystem.rb`) — typically a Brakeman magnet — is clean.                                                                                                     |
| 6 `bundle exec bundler-audit check --update`                     | **PASS**    | Advisory DB updated (1078 advisories, last 2026-03-30). New gem this phase: `parallel_tests 5.7.0`. No vulnerabilities in any of the new gems.                                                                                                                                             |
| 7 `bundle exec rubocop`                                          | **PASS**    | 274 files inspected, 0 offenses.                                                                                                                                                                                                                                                           |
| 8 `cargo test` (in `extras/cli/`)                                | **PASS**    | 287 / 0 / 0 (102 lib + 174 binary + 11 integration). Matches Phase B `#footage` report.                                                                                                                                                                                                    |
| 9 `cargo clippy --all-targets -- -D warnings` (in `extras/cli/`) | **PASS**    | 0 warnings on the new `extras/cli/src/footage/**` code.                                                                                                                                                                                                                                    |
| 10 `cargo build --release` (in `extras/cli/`)                    | **PASS**    | Binary at `target/release/pito` (workspace target, NOT `extras/cli/target/release`), 7,057,536 bytes (~6.7 MB). `pito version` and `pito --version` both print `pito 0.1.0` (short-SHA tweak deferred — see concerns 4).                                                                   |
| 11 `cargo fmt --check` (in `extras/cli/`)                        | NOTE        | Drift exists in 15 pre-existing files (`src/app.rs`, `src/commands/tui.rs`, `src/keys.rs`, `src/ui/{channel_detail,channels,confirmation,dashboard,mod,operation_progress,saved_views,search,settings,video_detail,videos}.rs`, `src/widgets/mod.rs`). NEW `src/footage/**` files — clean. |
| 12 GitHub Actions YAML parse                                     | **PASS**    | All three workflow YAML files (`ci.yml`, `pito-cli-publish.yml`, `pito-cli-cleanup.yml`) parse cleanly. Permissions blocks present and minimum-scoped. Action versions all pinned (no `@main`).                                                                                            |
| 13 System packages on dev host                                   | **PASS**    | `/usr/bin/ffprobe` (FFmpeg n8.1), `/usr/bin/vips` (libvips 8.18.2), `/usr/bin/convert` (ImageMagick) all present.                                                                                                                                                                          |
| 14 Static-deviation audit                                        | NOTE        | Three implementer choices deviate from a literal reading of the spec — concerns 1, 2, 3 below. Concern 1 IS the blocker; concerns 2 and 3 are non-blocking deferrals already noted in the log.                                                                                             |

`*` Simplify produced findings but no blockers — see concern 7.

## Blockers

### Blocker 1 — `pito footage` API URL mismatch (1-file fix)

The Rust footage client and its mocked integration tests target URLs that Rails
does not route. End-to-end the importer will 404 against the live API. The error
surfaced because the spec contradicts itself between §7.5 and §13:

- **§7.5** says: `GET /projects/<id>/footage.json`,
  `POST /projects/<id>/footage.json`, `PATCH /footages/<id>.json`,
  `DELETE /footages/<id>.json` (singular `footage`, no `/api/` prefix).
- **§13** says: nested API `api/projects/:id/footages` (plural, `/api/` prefix).

Phase A landed routes per §13. Phase B's Rust client landed paths per §7.5. The
two halves never met until this review.

Live Rails routes (verified via `bin/rails routes | grep footage`):

```
api_project_footages   GET    /api/projects/:project_id/footages(.:format)   api/footages#index
                       POST   /api/projects/:project_id/footages(.:format)   api/footages#create
footage                GET    /footages/:id(.:format)                        footages#show
                       PATCH  /footages/:id(.:format)                        footages#update
                       PUT    /footages/:id(.:format)                        footages#update
                       DELETE /footages/:id(.:format)                        footages#destroy
```

Rust client paths (verified in
`extras/cli/src/footage/api/client.rs:74,97,110,134`):

```
GET    /projects/<id>/footage.json     ❌ should be /api/projects/<id>/footages.json
POST   /projects/<id>/footage.json     ❌ should be /api/projects/<id>/footages.json
PATCH  /footages/<id>.json             ✓ matches
DELETE /footages/<id>.json             ✓ matches
```

The integration tests pass because BOTH the mock server (`wiremock`) and the
client agree on the wrong URL — the contract is internally consistent on the
Rust side but doesn't match the Rails surface.

**Fix scope (small, well-bounded — implementer dispatch only, no Rails edits):**

- `extras/cli/src/footage/api/client.rs` — change the two `format!` strings in
  `list_footage` (line ~74) and `create_footage` (line ~97) from
  `"/projects/{}/footage.json"` to `"/api/projects/{}/footages.json"`. Update
  the doc comments at lines 7-8 and 72/88.
- `extras/cli/src/footage/api/client.rs` — update the two `url_composition` unit
  tests (lines ~302-322) to match.
- `extras/cli/src/footage/api/models.rs` — update the doc comment at line 9.
- `extras/cli/tests/footage_integration.rs` — change the seven `path(...)`
  matchers (lines ~138, 155, 180, 205, 283, 291, 299, 430) to the new path.
  Update the prose comment at line ~199 ("The Add branch posts to ...").

**Spec also needs amending** (docs-keeper one-liner):

- §7.3 line 1 and §7.5 (Add / Change / Delete bullet list) — change the URL
  example to match the Rails routes (with `/api/` prefix and plural `footages`).

**Recommendation.** Dispatch `cli-impl` for the Rust + tests change; dispatch
`docs-keeper` to amend the spec to match. After both land, re-run gates 8 and 9
(cargo test + clippy) to confirm green, then validation can resume from step 18
(footage importer) below.

The rest of the playbook can be validated NOW — none of the other surfaces
depend on the importer's HTTP path.

## Concerns / suggestions (non-blocking)

These do not stop the user from validating the rest of Phase B. Surfaced so the
architect / docs-keeper can decide whether to backfill specs, queue follow-ups,
or roll into the blocker-fix dispatch.

### 1. log.md unstaged-revert incident (provenance note)

During Phase B's `#ci` dispatch,
`git checkout docs/plans/beta/04-project-workspace/log.md` was invoked to revert
prettier's auto-formatting. The checkout reset the file to the committed (Phase
A close) HEAD version — but the working tree had ~1156 lines because prior
`#footage`, `#app`, and `#styling` dispatches had appended their session entries
without staging. ~720 lines of original prose were destroyed (`log.md` Phase B
section).

**What is intact.** The actual code from those three dispatches — the entire
`extras/cli/src/footage/**` tree, the eight new controllers, the ~17 view
templates, the §9.2 / §9.3 / §10 CSS work, the new specs — is all still in the
working tree.

**What was reconstructed.** The wrap dispatch (`docs-keeper #wrap`) re-authored
the three lost log entries from the architect's conversation context and the
implementer report summaries. The
`Incident — log.md unstaged-revert (2026-05-04)` section in `log.md` is the
apologetic record. Reading the reconstructed entries against the actual code on
disk: line counts, module names, gem versions, decisions captured all match —
the prose narrative is faithful. The user is not seeing original primary-source
prose for the three earlier Phase B dispatches; they are seeing a faithful but
synthesized account.

**Process lesson recorded** in the incident section: treat `git checkout <file>`
as destructive on any file with unstaged content. Future agents running prettier
on shared markdown files should `git diff` first to confirm scope, or word-wrap
inline rather than invoke prettier.

### 2. Video aasm machine deferred (§11.2 — partially fulfilled)

Spec §11.2 specifies a Video state machine
(`scheduled → published → unpublished`). Phase B's `#app` lane recorded this as
deferred at `app/models/video.rb:10-22` with a comment block citing the
column-conflict rationale: an existing `privacy_status` AR enum on the same
column would clash with AASM declarations on it.

**Recommended follow-up** (already captured in `log.md` Phase B closing summary
and in `docs/orchestration/follow-ups.md`): introduce a separate
`videos.lifecycle_state` integer column for the aasm machine; leave
`privacy_status` as an enum for the YouTube-side privacy mirror. Pairs with a
future Phase 11 (Video Workflow) dispatch.

Acceptance criterion §15 ("aasm machines on Timeline AND Video reject invalid
transitions") is partially fulfilled — Timeline is done, Video deferred.
Captured in the closing summary, not a spec violation that blocks Phase B
commit.

### 3. `pito version` short-SHA tweak deferred (§7 amendment)

Phase 4 spec §7 amendment specifies `pito version` and `pito --version` should
print `pito <7-char-sha>` (e.g. `pito a2b3c4d`). Today the binary prints
`pito 0.1.0`:

```
$ /home/catalin/Dev/pito/target/release/pito version
pito 0.1.0
$ /home/catalin/Dev/pito/target/release/pito --version
pito 0.1.0
```

The `#footage` dispatch deferred this (build.rs vs vergen decision pending,
pairs naturally with future `extras/cli/` work). Captured in `log.md` and
`follow-ups.md`.

Acceptance criterion §15 ("`pito version` prints `pito <7-char-sha>`") is NOT
fulfilled this phase. The binary download flow (§8) is unaffected — the served
filename is always `pito` regardless of what `pito version` prints.

### 4. Pre-existing `cargo fmt` drift in `extras/cli/`

`cargo fmt --check` reports drift in 15 pre-existing files (verified):
`src/app.rs`, `src/commands/tui.rs`, `src/keys.rs`,
`src/ui/{channel_detail,channels,confirmation,dashboard,mod,operation_progress,saved_views,search,settings,video_detail,videos}.rs`,
`src/widgets/mod.rs`. NONE of the new `src/footage/**` files drift.

This is captured in `follow-ups.md` (one-shot `cargo fmt` cleanup) and
acknowledged in the `#footage` log entry. Don't re-flag in the blocker fix
dispatch.

### 5. CodeMirror 6 importmap pinning (small follow-up)

The `app/javascript/controllers/codemirror_controller.js` uses dynamic-import

- textarea fallback. Pinning the CM6 packages in `config/importmap.rb` is
  captured as a Phase B follow-up — when CM6 modules aren't pinned, the editor
  gracefully degrades to a plain textarea. Functional today; cosmetic
  improvement deferred.

Captured in log.md Phase B App entry (`Decisions captured`). Not in
`follow-ups.md` yet — recommend docs-keeper add it.

### 6. `pito-cli-publish` workflow runs for the FIRST time on this commit

The new `.github/workflows/pito-cli-publish.yml` workflow triggers on push to
`main`. The user should expect:

1. After commit + push, the publish workflow runs in parallel with `CI`.
2. A fresh GitHub release lands tagged `pito-<short-sha>` with the binary
   attached as `pito`.
3. The `pito-cli-cleanup` workflow then fires (triggered by the publish
   workflow's `workflow_run` event with `conclusion == 'success'`) and is a
   no-op on this first run (only one release exists; threshold is 5).

The cleanup-vs-CI trigger choice is captured in `pito-cli-cleanup.yml`'s leading
comment and in `log.md` Phase B CI entry. Subsequent commits will grow the
release backlog past 5, at which point the cleanup workflow trims to the latest
5 on each successful publish.

### 7. Dependabot permissions fix verifiable on next Dependabot PR

The workflow-level `permissions:` block at `ci.yml:15-17`:

```yaml
permissions:
  contents: read
  pull-requests: read
```

is the minimum surface to let `dorny/paths-filter@v3` call `listFiles` on
Dependabot PRs. Verifiable only on the next Dependabot PR run — close-and-
reopen any open Dependabot PR, or wait for the next bump. The current open
follow-up "pito CLI Dependabot alert #1" is the natural trigger if the bot opens
it imminently.

### 8. `/simplify` candidates (cosmetic)

- `app/lib/notes_filesystem.rb:78-83` — `sanitize_relative` does string cleaning
  then `File.basename`. The earlier `tr("\\", "/")` and the `start_with?("/")`
  and `..` rejection are belt-and-braces because `File.basename` strips
  directory components anyway. Documenting the layered defense makes sense; the
  redundancy is intentional.
- `app/jobs/notes/embed_job.rb:72-91` — `upsert_search` swallows all
  StandardError silently. Reasonable for the BM25-only / hybrid switch path
  (Meilisearch may not be running locally), but a structured log line ("note N
  upserted to Meilisearch with[/without] vector") would aid future
  observability. Cosmetic.
- `app/controllers/footages_controller.rb:76-104` and
  `app/controllers/api/footages_controller.rb:41-61` — `build_create_attrs` /
  `build_update_attrs` duplicate the `has_commentary_track` yes/no coercion
  logic. Extract to a `FootagesYesNoCoerce` helper or a shared concern when the
  third copy appears. Today it's two; not worth a dispatch.

### 9. `notes_filesystem.rb` symlink-escape note

`ensure_within_project!` uses `File.expand_path`, NOT `File.realpath`.
`expand_path` does only lexical resolution (collapsing `.`, `..`, leading `~`);
it does NOT follow symlinks. If a symlink existed inside the project directory
pointing at `/etc/passwd`, `expand_path` would still report the path as inside
the project root.

Practical risk is near-zero today: the app itself only ever creates flat `.md`
files via `File.write`, never `File.symlink`. `sanitize_relative` strips all
directory separators via `File.basename`, so the only attack vector requires a
pre-existing symlink in the project dir — which no Pito code path creates. The
phase context describes the helpers as "rejecting realpath escapes"; the
implementation actually rejects `expand_path` escapes (a weaker guarantee).
Recommend either:

- Switch to `File.realpath` in `ensure_within_project!` (handles the symlink
  case at the cost of a `realpath` syscall per write), or
- Document the assumption explicitly: "the project directory is a flat
  Pito-owned tree; symlink resolution is intentionally not performed".

Brakeman scan is clean — the lexical guard is enough to satisfy the static
analyzer. Worth a one-line follow-up.

## Manual test steps

### Pre-flight

1. **Action:** From the repo root, `git status`. **Expected:**
   - 35 modified tracked files (workflow + Cargo + Gemfile + view + CSS + spec +
     log + decision + design + spec + Rust files).
   - 58 untracked files (8 controllers, 12 view trees, 4 helpers, 2 jobs, specs
     for each, the two new workflows, `bin/parallel_setup`, `lib.rs`
     - `tests/footage_integration.rs` + `src/footage/**` Rust tree).
   - Branch `main`, working tree dirty (Phase B has not been committed yet).
   - The Phase A foundation `0079999` is the most recent on-`main` commit for
     this Phase 4 line of work; `4b6e680` (puma bump) and `9117c82` (bootsnap
     bump) sit on top.

2. **Action:** `which ffprobe && which vips && (which convert || which magick)`.
   **Expected:** All three resolve. ffprobe runs the `pito footage` integration;
   vips drives Active Storage variants; convert / magick is the historical AS
   path. On this host:
   - `/usr/bin/ffprobe`, `/usr/bin/vips` (libvips 8.18.2), `/usr/bin/convert`
     (ImageMagick).

3. **Action:**
   ```sh
   bin/rails runner '
     puts "github dev token: #{Rails.application.credentials.dig(:github, :development, :token).present? ? "PRESENT" : "MISSING"}"
     puts "voyage dev key: #{Rails.application.credentials.dig(:voyage, :development, :api_key).present? ? "PRESENT" : "MISSING"}"
   '
   ```
   **Expected:** Both PRESENT (verified during Phase 4 Step 0).

### Schema (Phase A re-validation)

4. **Action:** `bin/rails db:drop db:create db:migrate db:seed`. **Expected:**
   - All 10 Phase A migrations apply cleanly (the original 9 + the post-Phase-A
     `add_voyage_embeddings_enabled_to_app_settings`). `db/schema.rb` version is
     `2026_05_04_000010`.
   - Seed runs to completion. Slow on first run (~5–7 min for 100 channels + 250
     videos with stats); the Phase 4 sample at the end of seeds.rb completes in
     <1s.
   - Sample data after seed: 1 Tenant, 1 User, 100 Channels, 200 Videos + stats,
     1 Collection, 1 Game with cover_art, 1 Project with 2 ProjectReferences, 1
     Note (DB only), 1 Timeline (state `editing`).

5. **Action:** From psql:
   ```sql
   \dx vector
   SELECT format_type(atttypid, atttypmod) FROM pg_attribute
     WHERE attrelid = 'notes'::regclass AND attname = 'embedding';
   SELECT voyage_embeddings_enabled FROM app_settings;
   ```
   **Expected:**
   - `vector` extension installed.
   - `notes.embedding` is `vector(1024)`.
   - `voyage_embeddings_enabled` is `false` in development (default).

### App boot + nav

6. **Action:** `bin/dev`. **Expected:** Boots clean — Puma + Sidekiq + Tailwind
   watcher + Cloudflared tunnel + the cargo release-build child process (which
   lands the binary at `target/release/pito`). The VIPS-WARNING about
   `libopenslide.so.1` is harmless — see Phase A playbook concern 2.

7. **Action:** Open `https://app.pitomd.com/` (or `localhost:3000`).
   **Expected:** Header reads
   `[home] · [channels] · [videos] · [projects] · [settings]` (footer same
   order). Click `[projects]` — index renders without exception.

### Default-create everywhere

8. **Action:** From `/projects`, click `[ new project ]`. **Expected:**
   Instantly creates a new Project named `Untitled project` and redirects to its
   show page. No form, no confirmation.

9. **Action:** From `/collections`, `/games`: click `[ new collection ]`,
   `[ new game ]`. **Expected:** Same behavior — instant create with the default
   name.

10. **Action:** From a project show page, click `[ new note ]` in the Notes
    pane. **Expected:** A new note row appears in the table; a file lands at
    `$PITO_NOTES_PATH/<tenant_id>/projects/<project_id>/untitled-note-*.md`
    (path under `tmp/pito-notes/...` per Phase A's local default).

11. **Action:** From the project show page, click `[ new timeline ]` in the
    Timelines pane. **Expected:** New row in the timelines table with title
    `Untitled timeline`, state `editing`.

### Three-pane Project show

12. **Action:** Open the seeded project (or one created in step 8).
    **Expected:** Three panes side-by-side: Footage / Notes / Timelines. Each
    scrolls independently in its own column. Header `[projects]` is highlighted
    (`nav_link` auto-highlight).

13. **Action:** Resize the browser to mobile width (≤640px) or use device
    emulation. **Expected:** Horizontal scroll with snap — one pane fills the
    viewport, swiping reveals the next. NO vertical stack.

### Existing panes mobile fix (§9.2)

14. **Action:** At mobile width, visit `/channels/panes?ids=<comma-sep ids>` and
    `/videos/panes?ids=<comma-sep ids>`. **Expected:** Same horizontal scroll +
    snap behavior. Reorder arrows hidden on mobile.

### Saved views horizontal scroll (§9.3)

15. **Action:** At desktop AND mobile widths, visit `/channels`, `/videos`, or
    any page that renders the saved-views chip list. **Expected:** Chips flow
    horizontally, no wrapping. Long lists scroll the row, not the page. Verified
    via:
    ```sh
    grep -A2 saved-views-list app/assets/tailwind/application.css
    ```
    showing `flex-wrap: nowrap; overflow-x: auto`.

### Game cover art (libvips path)

16. **Action:** Edit a Game (`/games/:id/edit`); upload
    `spec/fixtures/files/cover_art.jpg` (or any small JPEG/PNG) via the
    cover-art form field; submit. **Expected:**
    - Variant generation runs without warning beyond the harmless
      `libopenslide.so.1` boot-time VIPS-WARNING.
    - Three variants render at thumbnail / card / full sizes when their URLs are
      first requested.
    - Files land under `$PITO_ASSETS_PATH/...` (default `tmp/pito-assets/...`
      per Phase A `.env.development`).

### Notes lifecycle

17. **Action:** From the Notes pane, `[ new note ]` (already covered in step
    10); click `[ edit ]` on the new row. **Expected:** Editor renders. If
    CodeMirror 6 modules are pinned in importmap, CM6 markdown mode shows;
    otherwise a plain textarea (graceful fallback per concern 5).

18. **Action:** Type `# Hello world` followed by a body; save. Open the note's
    file on disk
    (`cat $PITO_NOTES_PATH/<tenant>/projects/<pid>/untitled-note-*.md`); re-open
    the editor. **Expected:** File contains the typed content. `mtime` and
    `last_modified_at` are updated. Re-open the note's row — the `title` column
    now reads `Hello world` (after the next sync — see step 20).

19. **Action:** Edit the note again, remove the leading `# Hello world` line;
    save. Trigger sync via `[ scan now ]` button (next step). **Expected:**
    Title falls back to `Untitled note`.

20. **Action:**
    ```sh
    touch $PITO_NOTES_PATH/<tenant_id>/projects/<project_id>/foo.md
    ```
    Then click `[ scan now ]` in the Notes pane. **Expected:** A new Note record
    appears in the table — the sync job picked up the on-disk file and
    reconciled it into the DB.

### Notes lock UX

21. **Action:** From the Rails console:

    ```ruby
    Tenant.first.update!(notes_syncing_at: Time.current)
    ```

    Reload the project show page. **Expected:**
    - Banner appears in the Notes pane: "notes are syncing — try again in a
      moment."
    - `[ new note ]`, `[ scan now ]`, `[ edit ]` chips swap to `bracketed-muted`
      static spans (no longer clickable buttons).
    - From a separate terminal:
      ```sh
      curl -i -X POST https://app.pitomd.com/projects/<id>/notes -H 'Content-Type: application/json'
      ```
      Response is `423 Locked` with body
      `{"error":"notes_syncing","retry_after":30}`.

22. **Action:** Clear the lock:

    ```ruby
    Tenant.first.update!(notes_syncing_at: nil)
    ```

    Reload. **Expected:** Banner gone. Action chips clickable again. The same
    curl request now succeeds (`201 Created`).

23. **Action:** Verify the stale-lock shield. Set the timestamp to 6 minutes
    ago:
    ```ruby
    Tenant.first.update!(notes_syncing_at: 6.minutes.ago)
    ```
    Reload. **Expected:** Banner does NOT show (>5 min stale). Saves succeed.
    The shield prevents a job that died mid-sync from locking the UI forever.

### Voyage gate verification

24. **Action:** Set the flag explicitly off and create a note:

    ```ruby
    AppSetting.first.update!(voyage_embeddings_enabled: false)
    Note.create!(project: Project.first, tenant: Tenant.first, path: "voyage-off.md", last_modified_at: Time.current)
    ```

    Run the EmbedJob:

    ```ruby
    Notes::EmbedJob.new.perform(Note.last.id)
    ```

    **Expected:**
    - `Note.last.embedding` is nil (verified via `Note.last.embedding.nil?
      # => true`).
    - No HTTP request fires to `api.voyageai.com`. Confirm via
      `tail -f log/development.log` — no `Voyage embed` line. (The embed-job
      spec asserts `WebMock.not_to have_requested(:post, /api\.voyageai\.com/)`
      — the production code path matches the test.)
    - Meilisearch indexes the text body BM25-only (the `notes_test/documents`
      POST, or its dev equivalent). Don't worry if Meilisearch isn't running
      locally; the upsert is `rescue StandardError` and silently logs and
      continues.

25. **Action:** Flip the flag on:

    ```ruby
    AppSetting.first.update!(voyage_embeddings_enabled: true)
    Note.create!(project: Project.first, tenant: Tenant.first, path: "voyage-on.md", last_modified_at: Time.current)
    Notes::EmbedJob.new.perform(Note.last.id)
    ```

    **Expected:**
    - Voyage IS called once (`api.voyageai.com/v1/embeddings`).
    - `Note.last.embedding` is non-nil. Length:
      ```ruby
      Note.last.embedding.to_s.scan(/[\d.\-]+/).size  # => 1024
      ```

26. **Action:** Reset for hygiene:
    ```ruby
    AppSetting.first.update!(voyage_embeddings_enabled: false)
    ```

### Footage importer

> **Note.** Steps 27-32 require Blocker 1 to be resolved first. Until the Rust
> client uses the corrected URL (`/api/projects/<id>/footages.json`),
> `pito footage import` will 404 against the live Rails API. The wiremock-backed
> integration tests pass because both sides agree on the wrong URL.

27. **Action:** Place 3 mp4 files in a temp dir:

    ```sh
    mkdir -p /tmp/pito-footage-test
    cp ~/Videos/sample-{1,2,3}.mp4 /tmp/pito-footage-test/
    ```

    Or use any 3 small mp4s — ffprobe will report metadata for whatever the host
    has. Note the `Project.first.id`.

28. **Action:**

    ```sh
    /home/catalin/Dev/pito/target/release/pito footage import \
      --project <project_id> \
      --path /tmp/pito-footage-test/
    ```

    **Expected:**
    - ffprobe runs against each file (no install hint).
    - TUI overlay opens with three sections: Additions (3), Changes (0),
      Deletions (0). Footer: `[y] confirm   [any other key] cancel`.
    - Press `y`. Per-row indicator advances `[done]` × 3. Final summary
      `3 added, 0 changed, 0 deleted, 0 failed`.
    - Open the project's Footage pane in the browser — three rows now visible
      with their probed metadata.

29. **Action:** Re-encode one file (any resolution change) and delete another:

    ```sh
    ffmpeg -i /tmp/pito-footage-test/sample-1.mp4 -s 640x360 \
      /tmp/pito-footage-test/sample-1.mp4.tmp && \
      mv /tmp/pito-footage-test/sample-1.mp4.tmp \
         /tmp/pito-footage-test/sample-1.mp4
    rm /tmp/pito-footage-test/sample-2.mp4
    ```

    Re-run the same import command. **Expected:** Confirmation overlay shows:
    Additions (0), Changes (1), Deletions (1). Press `y`; progress shows
    `[done]` for both.

30. **Action:** Test the ffmpeg-missing branch:

    ```sh
    PATH= /home/catalin/Dev/pito/target/release/pito footage import \
      --project <project_id> \
      --path /tmp/pito-footage-test/
    ```

    **Expected:** Print:

    ```
    ffmpeg / ffprobe not found.
    Install:
      Debian/Ubuntu: sudo apt install ffmpeg
      macOS (brew):  brew install ffmpeg
      Arch:          sudo pacman -S ffmpeg
    ```

    Exit non-zero. **No HTTP traffic** (verified via mitmproxy / no log entries
    in `log/development.log`).

31. **Action:** Dry-run with all 3 files in place:

    ```sh
    /home/catalin/Dev/pito/target/release/pito footage import \
      --project <project_id> \
      --path /tmp/pito-footage-test/ \
      --dry-run
    ```

    **Expected:** Classifications print to stdout (3 Adds when --dry-run treats
    `existing` as empty, per spec ambiguity #6 in the `#footage` log entry). No
    prompt, no HTTP, instant exit.

32. **Action (yes/no boundary check):** Inspect the POST body the importer sent
    in step 28 (or a wiremock log if you're paranoid). **Expected:**
    `has_commentary_track` is the string `"yes"` or `"no"`, NOT a native
    boolean. Same for any future Boolean fields.

### CLI download link

33. **Action:** With `bin/dev` running and cargo build complete (the binary at
    `target/release/pito` exists), open the project Footage pane and click
    `[ download cli ]`. **Expected:**
    - File download starts.
    - Saved file is named `pito` (NOT `pito-<sha>` — the served filename is
      always `pito` per §8.1, regardless of what `pito version` prints).
    - `chmod +x pito && ./pito version` prints `pito 0.1.0` for now (NOT
      `pito <sha>` — short-SHA tweak deferred per concern 3).

### Timeline state machine

34. **Action:** From the Rails console:
    ```ruby
    p = Project.first
    t = p.timelines.create!(tenant: p.tenant)
    t.state              # => "editing"
    t.upload!            # => raises AASM::InvalidTransition
    t.export!
    t.state              # => "exported"
    t.upload!(youtube_url: "https://youtu.be/abc123")
    # NOTE: the upload! callable signature varies — check
    # spec/models/timeline_spec.rb for the exact arity.
    t.state              # => "uploaded"
    t.video.present?     # => true
    ```
    **Expected:** Linear transitions only; both invalid-transition raises fire
    (no skipping editing→uploaded; no rewind from uploaded).

### Design refresh visual checks

35. **Action:** Browse a few pages (e.g. `/projects/:id`, `/channels/:id`,
    `/dashboard`, `/settings`). **Expected — verify each rule fires:**
    - **Rule 1** Links + buttons: bold blue
      (`a, .bracketed, button[type="submit"] { font-weight: 700 }`).
    - **Rule 2** Destructive elements: bold red (e.g. `[ delete ]` chips).
    - **Rule 3** Muted text comes in two weights: normal (`.text-muted`) and
      bold (`.text-muted-bold`).
    - **Rule 4** Hints + captions: muted + italic (`.form-hint`, `.caption`).
      Visible at the channel form, settings page, search page, and dashboard
      subtitle.
    - **Rule 5** Flash bars unchanged from prior phases.
    - **Rule 6** User content (note titles, channel names, descriptions) NOT
      muted, NOT italic.
    - **Rule 7** Table headers muted + bold (`thead th`); table values normal
      weight + default text color (`tbody td`).
    - **Bonus** Dashboard chart colors come from
      `ApplicationHelper#chart_palette` (no inline hex literals).

36. **Action:** Verify no `<h4>` element renders italic anywhere (the
    `font-style: italic` was removed from the global `h4` rule, replaced with an
    opt-in `.h4-emphasis` class). **Expected:**
    `grep -rn '<h4' app/views/ app/components/` returns ZERO matches — confirmed
    during the styling dispatch.

### MCP Dev KB regression

37. **Action:** From Claude Mobile (via the existing MCP server at
    `mcp.pitomd.com`):
    `list_docs(name_pattern: "log.md", sort: "mtime_desc", limit: 1)`.
    **Expected:** Result includes `docs/plans/beta/04-project-workspace/log.md`
    at the top, with `last_modified_at` reflecting the Phase B append.

38. **Action:** `read_doc(path: "docs/plans/beta/04-project-workspace/log.md")`.
    **Expected:** Surfaces Step 0 + Phase A + the four reconstructed Phase B
    entries (Pito footage, App, Design refresh CSS, CI workflows) + the Incident
    note + the Phase B closing summary.

39. **Action:**
    `read_doc(path: "docs/decisions/0001-no-server-side-uploads.md")`.
    **Expected:** Surfaces the original ADR plus the new Addendum (2026-05-04)
    with the image-asset carve-out citing Phase 4 §5 + §7.

### Test suite

40. **Action:** `bundle exec rspec`. **Expected:** 945 examples, 0 failures,
    ~30s wall.

41. **Action:** `bundle exec parallel_rspec spec/`. **Expected:** 945 / 0 in
    ~10–12s wall. Same green; ~3× speedup on a 20-core host.

### CI workflows (verifiable AFTER commit + push)

These can be checked only after the user authorizes the architect's commit. They
are not preconditions for the commit itself.

42. **Action:** `gh run list --limit 4 --branch main` after push. **Expected:**
    Three workflow runs in flight or completed:
    1. `CI` — completes faster than Phase A's 1m10s thanks to `parallel_rspec`.
       ~30–35s on a 2-core ubuntu-latest runner → ~18–22s with parallelization.
    2. `Publish pito CLI` — runs in parallel with `CI`, builds the Rust binary,
       creates a release tagged `pito-<short-sha>` (7-char prefix) with `pito`
       attached.
    3. `Cleanup pito CLI releases` — fires on the publish workflow's success
       completion, runs the `dev-drprasad/delete-older-releases@v0.3.4` action,
       no-op on first run (only one release exists; `keep_latest: 5`).

43. **Action:** Verify the new release at
    `https://github.com/gmrdad82/pito/releases`. **Expected:** A release tagged
    `pito-<short-sha>` with the `pito` binary attached as a release asset.

44. **Action:** Wait for the next Dependabot bump (or close-and-reopen any open
    Dependabot PR). **Expected:** The `changes` job no longer fails with
    "Resource not accessible by integration" — the workflow-level `permissions:`
    block fixed it.

## Cleanup (between retries)

If the user wants to re-test from a clean slate:

```sh
bin/rails db:drop db:create db:migrate db:seed   # ~5–7 min
rm -rf tmp/pito-assets tmp/pito-notes              # AS + notes scratch
rm -rf /tmp/pito-footage-test                      # importer test files
```

Stopping `bin/dev` and re-running rebuilds the cargo binary in the background;
the controller's `503 pito_cli_unbuilt` short-circuit covers the brief window
before the new binary lands at `target/release/pito`.

If the user wants to fully unwind Phase B back to Phase A (`0079999`):

```sh
git stash push -u -m "phase-b-WIP"  # save EVERYTHING uncommitted
git clean -fd                        # nuke untracked files
git checkout -- .                    # revert tracked-file edits
bin/rails db:drop db:create db:migrate db:seed
```

Then `git stash pop` to bring it all back. **Confirm with the user before
running** — destructive, but Phase B has zero commits to recover from.

## Sign-off checklist

Before the architect commits Phase B:

- [ ] **Blocker 1 resolved.** `pito footage` Rust client URLs corrected to
      `/api/projects/<id>/footages.json`; integration tests updated; spec §7.3 /
      §7.5 amended (docs-keeper one-liner). Re-run gates 8 and 9 to confirm
      green.
- [ ] Pre-flight (steps 1–3): working tree state matches expectation; system
      packages present; credentials present.
- [ ] Schema (steps 4–5): migrations apply clean; `notes.embedding` is
      `vector(1024)`; AppSetting row carries
      `voyage_embeddings_enabled     false` in dev.
- [ ] App boot + nav (steps 6–7): `bin/dev` boots clean; nav shows `[projects]`
      after `[videos]`.
- [ ] Default-create (steps 8–11): all five resources create instantly with
      "Untitled X" names.
- [ ] Three-pane Project show (steps 12–13): desktop side-by-side; mobile
      horizontal scroll with snap.
- [ ] Existing panes mobile fix (step 14): `/channels/panes`, `/videos/panes`
      use horizontal scroll on mobile.
- [ ] Saved views (step 15): chip lists scroll horizontally desktop AND mobile.
- [ ] Game cover art (step 16): variants render via libvips without warning.
- [ ] Notes lifecycle (steps 17–20): create / edit / save / sync; H1 → title;
      no-H1 → "Untitled note"; touch + scan picks up.
- [ ] Notes lock UX (steps 21–23): banner + disabled chips + 423 + stale-lock
      shield all behave correctly.
- [ ] Voyage gate (steps 24–26): flag-off path fires NO Voyage HTTP and leaves
      embedding NULL; flag-on path fires exactly one Voyage call and writes a
      1024-dim vector. Reset to off.
- [ ] **Footage importer (steps 27–32) — gated on Blocker 1.** Add / Change /
      Delete branches; ffmpeg-missing hint; --dry-run; yes/no wire form.
- [ ] CLI download link (step 33): file streams; named `pito`; runs; version
      output reflects current state (0.1.0 today; SHA after concern 3 is
      addressed).
- [ ] Timeline state machine (step 34): linear, no skipping, no rewind; Video
      record linked on `upload!`.
- [ ] Design refresh (steps 35–36): all 7 rules visible; no italic `<h4>`.
- [ ] MCP regression (steps 37–39): `log.md`, ADR addendum reachable from
      Mobile.
- [ ] Suite green (steps 40–41): 945 / 0 single-process AND parallel.
- [ ] Concerns 1–9 reviewed. User decides which (if any) to dispatch: - Concern
      1 (log.md incident): no action — provenance noted, code intact. - Concern
      2 (Video aasm): leave as `lifecycle_state` follow-up. - Concern 3
      (`pito version` SHA): leave as `extras/cli/` follow-up. - Concern 4 (cargo
      fmt drift): leave as one-shot follow-up; already captured. - Concern 5
      (CodeMirror importmap pinning): recommend docs-keeper add to
      `follow-ups.md`. - Concern 6 (publish workflow first run): user watches
      the run land. - Concern 7 (Dependabot fix): verifiable on next bump. -
      Concern 8 (simplify candidates): cosmetic; skip. - Concern 9
      (notes_filesystem realpath): recommend a one-line documentation fix OR a
      `realpath` upgrade in `ensure_within_project!`. Either is a follow-up.
- [ ] **Blocker 1 fix landed**, gates 8 + 9 re-run green, integration tests now
      actually exercise the production URL.
- [ ] User has explicitly authorized the commit.

## Forward note for the architect

After the user signs off and Blocker 1 is resolved, the architect commits the
Phase B body in a single commit (consistent with the `# Workflow rules` section
of `CLAUDE.md`'s "commit directly to `main`"). Suggested commit message:

```
Add Phase 4 — Project Workspace (Phase B body)

App code: 8 controllers, ~17 view templates, 2 jobs, 4 helper libs,
notes-syncing 5-min lock + 423 boundary, CodeMirror w/ textarea fallback,
sidekiq-cron 5-min note sync. +83 RSpec examples (945 / 0).

pito footage subcommand: ffprobe walker, diff classification, TUI
overlays (confirmation + per-row progress), wiremock integration tests.
287 cargo tests, 0 clippy warnings.

Design refresh: §10 7 rules applied; 7 view files + 3 components
migrated to class-based markup; <h4> audit (zero live sites);
chart_palette helper; saved-views horizontal-scroll global rule;
panes mobile horizontal-scroll rule.

CI workflows: workflow-level permissions block fixes Dependabot
paths-filter "Resource not accessible by integration"; ffmpeg/imagemagick/
libvips42 install + db:seed step; switch to parallel_rspec.
parallel_tests gem with per-process Postgres DBs (3× speedup on this
host); pito-cli-publish.yml (push-to-main → release pito-<sha>);
pito-cli-cleanup.yml (workflow_run on publish success → prune past 5).

ADR 0001 image-asset addendum; design.md content rules + panes mobile
+ saved-views global + chart palette additions.

Phase B follow-ups (in follow-ups.md): Video aasm via lifecycle_state
column; pito version short-SHA build embed; cargo fmt one-shot cleanup;
CodeMirror 6 importmap pin.
```

After commit + push, watch:

- `Publish pito CLI` workflow create `pito-<short-sha>` release with the binary
  attached.
- `Cleanup pito CLI releases` workflow fire and no-op (1 release < 5 threshold).
- The next Dependabot PR's `changes` job pass cleanly (permissions block
  verification).

## User Validation

Walk through these in the browser only — no shell, no spec runs. Pre-flight
(`bin/dev`, seeded DB, libvips installed, credentials present, the one-off
`Tenant.first.notes_syncing_at = Time.current` console toggle for step 12) is
covered in the Manual test steps above; assume that's done.

[x] 1. **Dashboard number formatting.** Visit `/dashboard` and read the subtitle
line near the top → it reads `"X videos across Y channels"` with comma-separated
thousands once either count crosses 1,000 (e.g.
`"1,250 videos across 100 channels"`), not `1250` or `1.25k`.

[x] 2. **Header nav spacing.** Look at the top header bar on any page → the
search input sits snug to `[ settings ]` on the right with no oversized gap
between them; the nav reads
`[home] · [channels] · [videos] · [projects] · [settings]` followed immediately
by the search field.

[x] 3. **Settings page layout.** Visit `/settings` → the theme selector is the
FIRST form field at top-left of the page; the right column leads with YouTube
OAuth, then Voyage AI underneath; the indexes block uses the `Index` heading
style with one row per target (channels, videos, notes), each row showing its
document count.

[x] 4. **Voyage fieldset shows seeded key.** Inside the Voyage AI fieldset on
`/settings` → the API key field reads `key configured (•••••••)` instead of an
empty input, because the seed bootstrapped the dev credential.

[x] 5. **Voyage validation guard — clear blocked when flag on.** With the Voyage
embeddings flag set to yes and a key present, clear the API key field and submit
the form → a flash alert appears at the top explaining the key cannot be removed
while embeddings are enabled, and the key value is unchanged on re-render.

[x] 6. **Voyage validation guard — clear allowed when flag off.** Toggle the
Voyage embeddings flag to no, submit, then clear the API key field and submit
again → both submissions succeed; the field re-renders empty and no flash alert
is shown.

[x] 7. **Theme switcher style + behavior.** On `/settings`, look at the theme
selector → the options render as text-style radios
`( ) light  ( ) dark  (x) auto` (parentheses + `x`, not native browser radio
circles); click `( ) light` → the page repaints in light theme and the marker
moves to `(x) light`; click `( ) dark` → repaints to dark theme.

[x] 8. **Meilisearch reindex confirmation modal.** On `/settings`, click
`[ reindex ]` next to one of the indexes → a confirmation modal opens asking the
user to confirm the reindex; click cancel → modal closes, no reindex happens;
click `[ reindex ]` again then confirm → the submit lands and the page returns
with a flash that the reindex was queued.

[x] 9. **Indexed documents list.** On `/settings`, scan the indexes block → each
row shows `channels: N`, `videos: N`, `notes: N` with N rendered in
human-formatted numbers (commas at thousands); no row name ends in `_test` or
`_development`.

[x] 10. **Project create.** Visit `/projects` and click `[ new project ]` → a
new project named `Untitled project` appears at the top of the list and the
browser is redirected to its show page.

[x] 11. **Project show — three panes, no row hover highlight.** On the new
project's show page → three panes render side-by-side (Footage / Notes /
Timelines). NOTE: post-Phase-B-2 the detail table at the top of show is gone
(project show is now `<h1>` + 3 panes; concept column has been dropped); the
`tr:hover` exclusion from `detail-table` rows is moot for projects but still
applies to other detail tables (channel show etc.) — confirmed visually.

[x] 12. **Notes pane — create + edit + lock UX.** Note editor revamp landed
in Phase B-2: `GET /notes/:id` opens a single-screen two-pane editor (rendered
markdown preview | source textarea) with live preview via marked + DOMPurify,
`unsaved-form` Stimulus controller for navigation guard, and char/word counts
in the status bar below the source pane. Lock UX (banner + disabled chips +
423 + stale-lock shield) verified earlier in Phase B; revamp did not regress
that path.

[x] 13. **Project delete confirmation page.** From the project show page, the
breadcrumb action area now reads `[ edit ] · [ delete ]`; clicking `[ delete ]`
routes to the confirmation page (not a JS dialog), confirm + cancel pair, and
cancel returns to project show unchanged. `[ edit ]` separately routes to
`/projects/:id/edit` which renders a name-only form.

[x] 14. **Bulk select on /projects.** Verified — `[ bulk ]` toggle reveals
checkboxes on the projects list, two selections route the bulk delete action to
`/deletions/project/<id1>,<id2>` and the bulk confirmation page renders both.

If every step renders as expected, ship it via the next step in the playbook
(commit + push).
