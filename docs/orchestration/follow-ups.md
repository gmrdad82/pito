# Follow-ups — deferred items tracked across phases

This file lists work items the architect or user has explicitly deferred — items
that should be picked up at a specified trigger condition, not now. Each item
names the trigger so it doesn't get lost.

When the trigger condition fires, a small dedicated agent should be dispatched
to handle the cleanup, run gates, and report. Once the item ships and commits,
mark it Done with the commit reference.

## Conventions

### CI commit-message guard — `[skipci]`

Every GitHub Actions workflow under `.github/workflows/` (except the
`workflow_run`-triggered `pito-cli-cleanup.yml`, which is a pure maintenance job
tied to the publish workflow) carries a top-level per-job `if:` guard that skips
the run when the commit message OR pull-request title contains the literal token
`[skipci]`.

- Token is **lowercase, no space** — `[skipci]`. Distinct from GitHub's built-in
  `[skip ci]` (with a space) so the two never collide.
- Push events check `github.event.head_commit.message`.
- Pull-request events also check `github.event.pull_request.title`.
- `workflow_dispatch` and `workflow_run` triggers expose no `head_commit`;
  `contains()` on the missing field returns false and the run proceeds.
- Affected workflows: `ci.yml`, `deploy-website.yml`, `pito-cli-publish.yml`,
  `website-ci.yml`. Each carries a top-of-file comment naming the guard.
- Skipped: `pito-cli-cleanup.yml`. It triggers off `workflow_run` of
  `pito-cli-publish.yml` and only runs when that publish succeeded; a `[skipci]`
  commit already short-circuits publish, which transitively skips cleanup.
  Adding a guard there would be redundant and confusing for the maintenance-job
  purpose.

Use sparingly: docs-only / formatting-only / agent-config / orchestration
commits where neither RSpec nor cargo nor prettier coverage adds signal.

## Open

> These items are the working backlog for **Phase 5.5 — Polish window**, which
> runs after Phase 5 (Auth Foundation) lands and before Phase 6 (Auth UI)
> begins. As items resolve during 5.5, they move to "## Done" with the resolving
> commit hash. New entries continue to be added throughout Phase 5.

### Phase 11 sub-spec 01b–01f implementation queue

**Trigger:** in flight. 01a (video edit page polish) shipped on 2026-05-11; the
remaining five sub-specs queue for `pito-rails-impl` dispatch in sequence as the
open questions resolve.

**Source:** Phase 11 architect spec landed on 2026-05-11 (`86ef06e` — 1687
lines, 7 open questions). 01a was dispatched first; the remaining five sub-files
are ready for sequential dispatch.

**Summary:**

Phase 11 covers the post-Phase-22 video workflow surface. The architect carved
the spec into six sub-files; 01a is done.

- **01a** — video edit page polish (thumbnail + tags + chapters + end-screens).
  Shipped via `e4da516`.
- **01b** — pre-publish checklist expansion. Composes a checklist over chapters
  count + end-screens count + thumbnail presence; surfaces `[skip]` rationale
  per item.
- **01c** — post-publish workflow. Stamping, action-after-publish hooks.
- **01d** — series / sequel tracking. Lightweight related-video pointer between
  videos.
- **01e** — video links section polish.
- **01f** — MCP / CLI parity. Wires the new edit surface into the MCP tool layer
  and the `pito-rust` TUI.

**Action:** dispatch the sub-specs in order as the parent open questions resolve
(thumbnail YouTube push-back gating, end-screen target lookup, chapter
description writeback, etc.). 01b–01e are Rails-only; 01f bundles the MCP + CLI
legs.

**Verification:** per-sub-spec checkbox tick in
`docs/plans/beta/11-video-workflow-features/plan.md`; per-sub-spec log entry
under `docs/plans/beta/11-video-workflow-features/log.md`.

### Phase 28 sub-spec 01b — CLI multi-version game grouping

**Trigger:** queued for the next `pito-rust` dispatch. Rails + MCP halves of 01a
shipped on 2026-05-11.

**Source:** Phase 28 spec
`docs/plans/beta/28-multi-version-game-grouping/specs/01b-cli-multi-version-game-grouping.md`,
referenced from the 01a session log (open items §"CLI half (Rust)").

**Summary:**

The Rails surface for multi-version Game grouping (`version_parent_id`,
`version_title`, parent / edition pointers, rollup helpers, IGDB import walk,
MCP tools, rake backfill) shipped end-to-end in 01a. The CLI half is the
deferred remainder: primaries-only render in the games list, drill-down into an
edition list under a primary, `?include_editions=yes/no` flat-mode toggle, and
wire-format parity with the MCP tools shipped in 01a.

**Action:** dispatch `pito-rust` against the 01b spec when the broader CLI
parity work resumes. Wire format is already stable via the MCP tool layer.

**Verification:** `cargo test --manifest-path extras/cli/Cargo.toml` green; the
games TUI screen renders primaries with an editions count badge; toggling flat
mode expands editions inline.

### Phase 6 deviation acknowledgment — DB-backed sessions vs. cookie_store (decision 6.1)

**Trigger:** N/A — informational. Captured here so future readers don't
re-litigate the locked decision when they notice the discrepancy between
decision 6.1 and the running code.

**Source:** Phase 6 implementation pass; the deviation was accepted in flow
because pure `cookie_store` is incompatible with the `/settings/sessions`
per-session revocation requirement.

**Summary:**

Phase 6 (Auth UI) decision 6.1 locks `cookie_store` as the session backend.
Implementation actually shipped DB-backed sessions following the Rails 8
generated-auth pattern (a `sessions` table with `user_id`, IP, user agent,
created/updated timestamps; the cookie carries a session token that resolves to
a row).

The deviation is **accepted**, not a bug to fix:

- Pure `cookie_store` is stateless on the server. Revoking a single active
  session from `/settings/sessions` ("sign out other devices") is not possible
  without a server-side record to delete.
- DB-backed sessions are the Rails 8 generated-auth default for exactly this
  reason; per-session revocation is the headline UX of `/settings/sessions`.
- Cookie integrity / signing still applies (the session token is signed); the
  only change is where the source of truth lives.

**Action:** none. This entry exists so a future reader who diffs decision 6.1
against the running code can read this paragraph and move on, instead of
"fixing" the divergence and breaking `/settings/sessions`. If the locked
decision needs formal amendment, that is the architect's call (likely a
follow-up commit to the Phase 6 spec or an ADR under `docs/decisions/`).

### CI cli job working-directory

**Trigger:** any future CI sweep, OR the next time `.github/workflows/ci.yml` is
touched. Queued for the post-Phase-4 follow-up sweep.

**Source:** reviewer playbook
`docs/orchestration/playbooks/2026-05-04-monolith-pivot.md` concern #4.

**Summary:**

`.github/workflows/ci.yml` sets `working-directory: extras/cli` for the cli job.
That works for `cargo build` / `cargo test` / `cargo clippy` / `cargo audit`,
but it means workspace-root clippy is never exercised in CI. Workspace-wide
changes (e.g. a workspace `Cargo.toml` at the repo root) won't be linted.

**Action:**

- Consider running `cargo clippy --workspace -- -D warnings` from the repo root
  in CI, in addition to the existing per-crate run under `extras/cli`.
- Decide whether to keep both (per-crate AND workspace) or replace the per-crate
  invocation with the workspace one.

**Verification before implementation:**

- Confirm the workspace topology at the time of implementation — if `extras/cli`
  is still the only Rust crate, the workspace clippy run is equivalent and the
  per-crate one can be dropped.
- Run the proposed CI command locally first to ensure it passes on a clean
  checkout.

### Procfile.dev / bin/dev / Rails controller wiring for the `pito` binary

**Trigger:** during Phase 4 (Project Workspace), OR the next time the Rails app
needs to serve / rebuild the `pito` CLI binary for download.

**Source:** reviewer playbook
`docs/orchestration/playbooks/2026-05-04-monolith-pivot.md` concern #6, plus a
deeper check on 2026-05-03.

**Summary:**

The migration spec
(`docs/plans/beta/04-project-workspace/specs/monolith-migration.md` lines 58–59)
said `Procfile.dev`, `bin/dev`, and "the Rails controller path that builds /
serves the binary" should reference `extras/cli/target/release/pito`.

Current state as of 2026-05-03:

- `Procfile.dev` lists web / mcp / worker / css / tunnel only.
- `bin/dev` does Docker + foreman only.
- A repo-wide grep for `extras/cli/target` returns zero hits in Rails / config /
  bin / Procfile / yml.

Nothing references the new binary location.

**Action:**

- Decide whether the Rails app needs a route to serve / rebuild the `pito`
  binary for download.
- If yes: wire `Procfile.dev`, `bin/dev`, and the responsible Rails controller
  to the new path (`extras/cli/target/release/pito`).
- If no: drop the spec line — it was overstated. Note the resolution in the
  Phase 4 log.

**Verification before implementation:**

- Re-read the migration spec section to confirm intent.
- Confirm with the user / architect which direction (wire it, or drop the spec
  line) is correct before coding.

### Stale `pito-sh` comments in Rails app

**Trigger:** post-Phase-4 follow-up sweep, OR any time one of the listed
controllers / config files is touched substantively.

**Source:** spotted on 2026-05-03 while investigating the Procfile/bin/dev
wiring follow-up above.

**Summary:**

14+ files still reference `pito-sh` (the old terminal-app name, now `pito` /
`extras/cli/`). Confirmed hits as of 2026-05-03:

- `app/controllers/saved_views_controller.rb:10,57`
- `app/controllers/channels_controller.rb:114`
- `app/controllers/videos_controller.rb:71,116`
- `app/controllers/deletions_controller.rb:54`
- `app/controllers/settings_controller.rb:62`
- `app/controllers/bulk_operations_controller.rb:9`
- `app/controllers/application_controller.rb:9`
- `app/controllers/dashboard_controller.rb:69`
- `app/controllers/search_controller.rb:24`
- `app/controllers/syncs_controller.rb:77`
- `config/routes.rb:16,26,36`
- `config/environments/development.rb:86`

All are comments — no behavior change.

**Action:**

- Sweep `pito-sh` → `pito` (or "pito CLI" where the noun form is needed) across
  these files.
- Audit the rest of the repo (`app/`, `lib/`, `spec/`, `config/`) for any other
  `pito-sh` stragglers and update them in the same pass.
- Keep historical references intact in `docs/plans/`, `docs/conversations/`, and
  ADR Context blocks — those are append-only history.

**Verification before implementation:**

- `grep -rn "pito-sh" app/ lib/ spec/ config/ bin/ Procfile* extras/` should
  return zero matches after the sweep.
- Full RSpec suite + Rubocop remain green (comments-only changes should not
  affect either, but verify).

### Footage API surface symmetry — namespace member actions under `/api/`

**Trigger:** Reviewer surfaced 2026-05-04 during Phase B review.

**Source:** Reviewer playbook
`docs/orchestration/playbooks/2026-05-04-phase-4-project-workspace.md`
non-blocking concern.

**Summary:**

The footage JSON API has asymmetric URL surface. Collection actions (POST + GET)
live at `/api/projects/:project_id/footages.json` and route to
`app/controllers/api/footages_controller.rb`. Member actions (PATCH + DELETE)
live at top-level `/footages/:id.json` and route to
`app/controllers/footages_controller.rb` because they share the URL surface with
the HTML edit/destroy flow. The Rust importer client
(`extras/cli/src/footage/api/client.rs`) handles the asymmetry, but it's
confusing and would simplify if all four actions lived under `/api/`.

**Action:**

- Move the JSON formats of `update` and `destroy` from `FootagesController` to
  `Api::FootagesController` (member actions). Update routes so
  `PATCH /api/footages/:id.json` and `DELETE /api/footages/:id.json` exist
  alongside the existing collection actions. Keep the HTML edit/destroy flow at
  top-level (`PATCH /footages/:id` HTML, no .json variant). Update the Rust
  client's PATCH and DELETE URL paths to match. Refresh the spec §7.5 amendment
  to reflect the symmetric design.

**Verification:**

- `cargo test` in `extras/cli/` green.
- `bundle exec rspec spec/requests/api/footages_spec.rb` covers all four CRUD
  methods.
- End-to-end: `pito footage import` creates / updates / deletes against
  `bin/dev` without 404s.

### CodeMirror 6 importmap pinning

**Trigger:** Reviewer surfaced 2026-05-04 during Phase B review. Implementation
choice during `pito-rails #app` deferred CM6 packaging.

**Source:** Phase 4 spec §9.5 + log.md `### Phase B — App code` entry.

**Summary:**

The Stimulus `codemirror_controller.js` mounts CM6 in markdown mode on a
`<textarea>`. The current implementation uses dynamic imports with a textarea
fallback so the surface is usable today even without CM6 packages pinned. To get
the actual CodeMirror 6 editor surface (markdown highlighting, line numbers, the
editing UX the spec describes), pin the four CM6 packages in
`config/importmap.rb` and verify the controller's dynamic import resolves to the
pinned modules.

**Action:**

- Add `pin "codemirror"` (or whichever exact package name is current), plus the
  markdown mode + view + state + commands packages, to `config/importmap.rb`.
  Test that the controller upgrades from textarea fallback to full CM6 in
  `bin/dev`. Take a smoke screenshot of a footage description edit + a note edit
  before committing.

**Verification:**

- Open a project's notes pane in `bin/dev`. The note editor renders CM6 (line
  numbers visible, markdown syntax highlighting active). Same for the footage
  description edit form. Existing system specs still green.

### `pito footage import` runtime validation against live `app.pitomd.com`

- **Trigger:** User surfaced 2026-05-04 during Phase B end-of-validation
  walkthrough. Running
  `pito footage import --project 5 --path /home/catalin/Footage` in the terminal
  returned `error: GET existing footage for project 5`. Cloudflared tunnel logs
  showed `stream X canceled by remote with error code 0` against the upstream
  Rails server.
- **Source:** Mid-Phase-4 conversation between user and architect after the
  Phase B body was ready to commit. The Rust client's URL contract was corrected
  mid-session (`/projects/<id>/footage.json` →
  `/api/projects/<id>/footages.json`) — see the post-review fixes in
  `docs/plans/beta/04-project-workspace/log.md`. The local binary the user was
  running pre-dates that fix.
- **Summary:** The Rust source code IS correct as of the Phase B commit; the
  in-flight binary on the user's machine was built BEFORE the URL contract
  correction. After the Phase B commit lands and the `pito-cli-publish.yml`
  workflow runs on `main`, a fresh `pito-<short-sha>` release ships with the
  corrected URLs. The user needs to download that fresh binary (via the
  `[ download cli ]` link on a project's footage pane in production, OR a fresh
  local `cargo build --release` from `extras/cli/`) before retrying the import
  flow.
- **Action:**
  1. Wait for Phase B commit + push to fire
     `.github/workflows/pito-cli-publish.yml`.
  2. Verify the workflow created `pito-<sha>` release with the binary.
  3. Either download via `[ download cli ]` from the production dashboard, or
     rebuild locally via
     `cargo build --release --manifest-path extras/cli/Cargo.toml`.
  4. Re-run `pito footage import --project <id> --path <dir>` against `bin/dev`
     first (lower stakes), then against `app.pitomd.com`.
- **Verification:**
  1. The `GET` to `/api/projects/<id>/footages.json` returns 200 with the
     existing-footage list (empty array on first run).
  2. The TUI confirmation overlay renders the per-file diff classification
     (additions / changes / deletions).
  3. Confirming via `y` posts each file via
     `POST /api/projects/<id>/ footages.json` (collection action) and the rows
     appear in the Project's Footage pane after the run completes.
  4. If the Cloudflared tunnel still surfaces stream-cancel errors, investigate
     as a separate concern — possibly request body size limits, timeout, or
     Rails-side strong-params rejection.

### `pito` CLI footage handling end-to-end review

- **Trigger:** User surfaced 2026-05-04 after the Phase B post-commit cycle
  (note editor revamp, project concept drop, modal footer, pane background
  color). The Rails surface for projects has changed shape — `Project#concept`
  is gone, the show page is title + 3 panes, edit page is name-only — and we
  want to confirm the `pito` CLI footage import flow still works end-to-end
  against the new shape.
- **Source:** Mid-Phase-B-2 conversation between user and architect.
- **Summary:** The Rust client at `extras/cli/src/footage/api/client.rs` hits
  `/api/projects/<id>/footages.json` for the existing-footage list and posts new
  files to the same collection. None of those endpoints are affected by the
  project rework, but the CLI also reads project metadata (name) for the
  import-confirmation overlay; verify the JSON shape still matches what the Rust
  client expects after the `concept` column drop. Plus walk the full happy path:
  list, classify (add / change / delete), confirm, post.
- **Action:**
  1. Re-read `extras/cli/src/footage/api/client.rs` and any models in
     `extras/cli/src/api/models.rs` that deserialize project payloads. Confirm
     none of them reference a `concept` field.
  2. Build a fresh release binary:
     `cargo build --release --manifest-path extras/cli/Cargo.toml`.
  3. Run `pito footage import --project <id> --path <dir>` against `bin/dev`
     first; expect the existing-footage GET to 200, the diff classification
     overlay to render, confirmation via `y` to POST each file successfully.
  4. Repeat against `app.pitomd.com` (production) once the Phase B-2 commit is
     merged and `pito-cli-publish.yml` has built a fresh release tagged
     `pito-<sha>`.
  5. If the production run surfaces any 4xx / 5xx, capture the request URL +
     body + Rails log line and triage as a separate concern.
- **Verification:**
  1. Local (`bin/dev`): one full add + change + delete cycle.
  2. Production (`app.pitomd.com`): one full add cycle from the user's
     `~/Footage` directory.
  3. The Footage pane on the project show page reflects the new rows after each
     run completes.
- **Cross-reference:** related to the existing `pito footage import` runtime
  validation against live app.pitomd.com follow-up above — that one focused on
  the URL contract; this one is the broader regression check after the project
  rework.

### `fps` BigDecimal → string serialization in non-API FootagesController

**Trigger:** post-validation of the API-side fix shipped 2026-05-05, OR the next
time `app/controllers/footages_controller.rb` is touched substantively.

**Source:** Reviewer follow-up on `aebcd7d7` rails dispatch (fps API fix). Same
symptom is latent in the non-API web controller; only the API was in scope for
the immediate fix because the field bug surfaced via the Rust CLI.

**Summary:**

`app/controllers/footages_controller.rb:122` has the same shape as the API
controller had on line 79 before the 2026-05-05 fix:

`fps: footage.fps&.to_s`

`Footage.fps` is `BigDecimal` (column type `numeric(6,3)`); `to_s` produces a
string like `"60.0"`. Any JSON consumer expecting a number breaks the same way
the Rust CLI did against the API endpoint. The web controller's `footage_json`
is consumed by inline edit / show paths and possibly Stimulus controllers.

**Action:**

1. Change `to_s` → `to_f` on the same line.
2. Audit the existing JS / Stimulus consumers of `/footages/:id.json` (or
   wherever `footage_json` is rendered) and confirm none of them are parsing
   `fps` as a string. Switch any string-shaped consumer to read it as a number.
3. Update the corresponding `spec/requests/footages_spec.rb` (or system spec) to
   assert numeric, mirroring the change made to
   `spec/requests/api/footages_spec.rb`.

**Verification:**

- `bundle exec rspec` green at full suite count (currently 1061 → still 1061
  modulo any spec assertion tweaks).
- Smoke:
  `curl -sS http://127.0.0.1:3027/footages/1.json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(type(d["fps"]).__name__)'`
  → prints `float` (was `str`).
- Manual: open a project's footage row inline-edit in the browser, confirm the
  fps value renders correctly and isn't broken by the type change.

### `pito footage import` reports "X failed" when server actually succeeded

**Trigger:** next CLI polish pass touching the footage import command, OR a
dedicated reliability sweep on the CLI's API result handling.

**Source:** Surfaced 2026-05-05 during first real-data validation run against
project 1 ("Ghost 'n Goblins Resurrection"). The 4 footage rows were created
successfully on the Rails side (HTTP 201, rows visible in the DB), but the CLI
reported `0 added, 0 changed, 0 deleted, 4 failed`. Root cause was an unrelated
wire-format mismatch (`fps` BigDecimal `to_s` vs. CLI `Option<f64>`) in the
response payload — the CLI's `resp.json()` decode failed AFTER the row was
already created server-side, and the CLI counted the decode failure as a create
failure.

**Summary:**

In `extras/cli/src/commands/footage.rs` (and any sibling result-collection
code), a POST that returns 2xx but whose response body fails to decode is
currently classified as a failure. This is misleading: the row IS in the
database, but the user thinks nothing landed and may run the import again hoping
for a different outcome (which then re-creates duplicates or hits the
existing-record diff path inconsistently).

**Action:**

1. In the create / update result handler, distinguish between:
   - HTTP non-2xx → genuine server failure (count as failed).
   - HTTP 2xx + decode failure → operation succeeded server-side but the client
     couldn't parse the response. Either count as success (with a warning) OR
     introduce a new "succeeded, response unparseable" state.
2. Update the summary line at the end of `pito footage import` to use the new
   classification.
3. Add unit tests covering both branches (mock a 2xx with malformed body; mock a
   4xx).

**Verification:**

- `cargo test --manifest-path extras/cli/Cargo.toml` green; the new
  decode-fail-but-2xx test passes.
- Manual: contrive a wire-format mismatch (revert the `fps to_f` fix on a
  branch, then run `pito footage import` against that branch) → CLI reports "4
  added (with response parse warning)" or similar, NOT "4 failed".

### Wire footage bulk-mode (Confirmable::TYPES + delete behavior)

**Trigger:** when project page footage table needs always-on checkboxes matching
the channels/videos pattern, OR a dedicated "bulk operations on footage" feature
pass.

**Source:** Surfaced 2026-05-06 by the Wave 2 Lane F architect dispatch. The
dispatch deferred the footage-table bulk shape because (a) `Footage` is not in
`Confirmable::TYPES` (currently
`%w[channel video project collection game note timeline]`) so
`/deletions/footage/:ids` would 404, and (b) the project-side decision of what
footage delete actually does — DB row only, or also the on-disk file via the
importer — needs spec confirmation.

**Items:**

1. Add `"footage"` to `Confirmable::TYPES`.
2. Add `cancel_path` / `model_for` / `scope_for` / `label_for` cases for
   `footage` in `Confirmable`.
3. Decide what footage delete means semantically: DB row only (preserves the
   `.mkv` file on disk) vs. DB row + on-disk file (matches the importer delete
   classification). Document the decision in this file before coding.
4. Mirror the always-on checkbox shape on `_footage_pane.html.erb` once the
   backend works.
5. Spec: `/deletions/footage/:ids` round-trip via `DeletionsController`.

**Verification before coding:**

- Confirm decision #3 with the user.
- Read `Confirmable::TYPES` consumers to make sure adding `"footage"` doesn't
  surprise an unrelated controller.

### Footage source column sorts by enum integer, not alphabetical

**Trigger:** if the `Footage.sources` enum grows beyond `obs` / `camera`, OR a
dedicated "footage table polish" pass.

**Source:** Surfaced 2026-05-06 during Wave 2 Lane F. Today the source column
header sorts by the enum's integer value (`obs(0)`, `camera(1)`), which happens
to be alphabetical-by-coincidence with two values. Adding a third value (e.g.,
`screen`) breaks the visual alphabetical assumption.

**Action:**

- Either map source to its string label in the `ORDER BY` clause (joined via the
  enum's reverse-lookup), or guarantee enum values are added in alphabetical
  order (fragile).
- Specs: a sort with three+ source values that asserts alphabetical ordering.

### Videos new form `[add]` rebadge mirror

**Trigger:** next time `app/views/videos/_form.html.erb` (or its equivalent) is
touched, OR a dedicated copy-sweep pass.

**Source:** Surfaced 2026-05-06 during Wave 1.5 after the channels new form was
branched on `channel.new_record?` to render `[add]` on create vs. the
post-Wave-1 `[update]` glyph. The same correction needs mirroring on the videos
new form so create reads as `[add]` and update reads as `[update]`. Wave 1.5
landed the channels half but did not touch videos in this dispatch.

**Action:**

- Branch the videos form's submit button on `video.new_record?`: `[add]` when
  new, `[update]` otherwise.
- Update any associated request-spec assertions that check the button label.
- Verify the form is consistent with the channels analogue.

**Verification:**

- `bundle exec rspec spec/requests/videos_spec.rb` green.
- Manual: `/videos/new` shows `[add]`; `/videos/:id/edit` shows `[update]`.

### projects_controller.rb sort allowlist patterns repeat

**Trigger:** dedicated controller-cleanup pass, OR if the SQL allowlist pattern
needs a third site (then DRY).

**Source:** Reviewer 2026-05-06. Both `#sort_clause` (index) and
`ordered_footages` (show) inline-build `Arel.sql("#{column} #{direction}")` from
frozen-hash allowlists. The pattern is repeated to dodge a Brakeman
flow-analysis false positive (passing the sanitized strings across method
boundaries trips the SQL-injection warning). Mirrors `ChannelsController`.

**Action:** when a third controller needs the same shape, factor into a shared
helper that Brakeman accepts. Until then, keep inline.

### Filter chip group component — share between channels and footage

**Trigger:** dedicated UI-component-DRY pass, OR if a third filter-chip surface
lands.

**Source:** Reviewer 2026-05-06. The footage filter chips (Wave 2 Lane F) and
the channels filter chips share the same conceptual shape: chip per distinct
value, `[clear]` link, URL-state serialization. Currently implemented as two
separate ERB blocks.

**Action:** introduce a `FilterChipGroupComponent` that takes the dimension +
values + current selection + clear path. Migrate channels and footage to it.
Test the component in isolation.

### request.query_parameters.merge(sort:, dir:) mixes string + symbol keys

**Trigger:** next time the projects controller's URL helpers are touched.

**Source:** Reviewer 2026-05-06. Works in practice (Rails normalizes), but the
mixed key types are subtle and could trip a future `.deep_symbolize_keys` or
`.with_indifferent_access` consumer.

**Action:** stringify the keys (`merge("sort" => sort, "dir" => dir)`) for
explicitness. One-line fix.

### .filename-cell display: flex on <td> — narrow viewport eyeball

**Trigger:** any responsive / mobile pass on the project show page.

**Source:** Reviewer 2026-05-06. Modern browsers handle `display: flex` on
`<td>` correctly, but it's not the most-tested CSS path. At very narrow
viewports the head/tail spans may overlap or wrap unexpectedly.

**Action:** test at 360px / 480px / 720px viewport widths, capture screenshots,
fix any overlap or wrapping with a media-query if needed.

### bulk_select_controller.js legacy comments mislead

**Trigger:** next time the controller is touched, OR a JS hygiene pass.

**Source:** Reviewer 2026-05-06. The controller has comments describing
`enterBulk` / `exitBulk` / `bulkToggle` as "temporary legacy hooks" — but the
notes pane and `/projects` index intentionally keep the toggle pattern (those
pages don't have always-on checkboxes today). The comments are misleading.

**Action:** either tighten the comments to "kept for the toggle-mode surfaces"
OR migrate notes pane and projects index to always-on shape and remove the
legacy hooks entirely. Probably the latter, as a follow-up to the footage
bulk-mode entry above.

### Migrate /channels + /videos sort from URL hash to query params

**Trigger:** when channels or videos lists need server-side filtering /
pagination, OR a dedicated "sort consistency" pass.

**Source:** Surfaced 2026-05-06 during Wave 3 Lane K. Today `/channels` and
`/videos` persist sort state in the URL HASH (`#0=name_asc`) via a client-side
`sortable-table` Stimulus controller. `/projects` index and `/projects/:id`
footage table use server-side query params (`?sort=...&dir=...`) via the
controller's `ALLOWED_SORTS` allowlist. Inconsistency.

**Items:**

1. Wire `ChannelsController#index` to consume `params[:sort]` and `params[:dir]`
   via the existing `ALLOWED_SORTS` / `ALLOWED_DIRS` constants (mirror
   `ProjectsController#index`).
2. Same for `VideosController#index` (the constants exist but no consumer).
3. Replace the `sortable-table` Stimulus controller invocations on the index
   views with plain `link_to` headers carrying `sort=col&dir=asc/desc` in the
   URL.
4. Update specs to assert query-param URLs and server-side sorted result sets.
5. (Optional) Keep the Stimulus controller for non-index pages if any rely on
   it; otherwise delete.

**Why now:** when `/channels` grows past a few dozen entries, server-side
pagination becomes useful; that requires server-side sort. Aligns the URL state
across the whole app.

### Meilisearch test isolation — wait_for_tasks race condition

**Trigger:** dedicated test-stability pass, OR after a related Meilisearch spec
failure recurs.

**Source:** Reviewer 2026-05-06. The Wave 2 commit `dd84eea` reported 1153/0
specs, but later runs (Wave 3I + Wave 3K) reported 2 occasional failures in
`spec/services/search/meilisearch_engine_spec.rb` (`#remove`, `#reindex_all`).
Pre-existing. The Wave 3 reviewer's full-suite runs (parallel + serial) didn't
reproduce the failure but identified the likely cause: the spec's
`wait_for_tasks` helper at
`spec/services/search/meilisearch_engine_spec.rb:137-146` reads the **global**
`client.tasks["results"]` list. Under load it may report `pending.empty?`
prematurely and let an example proceed before the `before`-block's
`delete_all_documents` task has actually been enqueued.

**Items:**

1. Scope `wait_for_tasks` to the specific `videos_test` index by `indexUid`
   rather than reading the global tasks list.
2. Add a ceiling timeout (e.g., 10s) so a hung Meilisearch task can't silently
   lock the whole suite.
3. (Optional) Force per-spec teardown via an
   `after(:each) { client.delete_all_documents }` if the index pollution recurs.

### docs/design.md:463 still references --color-bg-alt for the zebra rule

**Trigger:** trivial to fix in any docs pass.

**Source:** Reviewer 2026-05-06 during Wave 3 Lane I review. The zebra rule on
`tbody tr:nth-child(even)` was migrated from `--color-bg-alt` to
`--color-pane-bg-b` as part of unifying the pane-bg system. The design doc still
mentions the old token.

**Action:** update `docs/design.md` line 463 (or wherever the zebra rule is
described) to reference `--color-pane-bg-b`.

### --color-pane-bg single-token alias has no consumers post-Wave-3

**Trigger:** trivial CSS hygiene.

**Source:** Reviewer 2026-05-06. Wave 3 Lane I migrated all callers of the
legacy `--color-pane-bg` token to the new `-a` / `-b` / `-wide` tokens. The
alias `--color-pane-bg: var(--color-pane-bg-a)` was kept defensively but
currently has zero `app/` callers.

**Action:** `grep -rn "color-pane-bg)" app/` to confirm zero matches, then drop
the alias from `app/assets/tailwind/application.css`. Defer if the codebase
grows back into needing the singular token.

### bulk_select_controller.js comments mislead post-notes-always-on

**Trigger:** next time the controller is touched, OR a JS hygiene pass.

**Source:** Reviewer 2026-05-06. The previous follow-up ("legacy comments
mislead") said "the notes pane and `/projects` index intentionally keep the
toggle pattern". After Wave 3 Lane J, the notes pane no longer uses toggle mode
— only the project SHOW footage pane retains it (and that's deferred until
`Confirmable::TYPES` is extended for footage).

**Action:** update the controller's leading comment to reflect that the toggle
hooks (`enterBulk` / `exitBulk` / `bulkToggle`) are kept for the footage pane
only, until Wave 2 Lane F's deferred footage bulk-mode follow-up lands.

### Wave 3 :only-child rule expands single-pane mobile from 88vw to 100vw

**Trigger:** mobile UX pass on /channels/:id and /videos/:id.

**Source:** Wave 3 post-patch CSS reviewer note 2026-05-06. The
`.pane-container > .pane-wrapper:only-child` override sets
`width: 100%; flex: 1 1 auto; max-width: 100%`. On mobile, the existing media
query at `app/assets/tailwind/application.css:903` redefines `.pane-wrapper` to
`flex: 0 0 88vw` for swipe-to-navigate panes. The cascade order makes
`:only-child` more specific, so a lone pane on mobile now stretches edge-to-edge
(was 88vw with 6vw padding either side).

**Action:** decide if the visual expansion is desired. If not, wrap the override
in the same desktop media query as the rest of the `:only-child` rule. The
current behavior is full-edge on mobile lone panes — likely fine for show pages
but worth user eyeball.

### 2026-05-09 realignment — top-level direction map

**Trigger:** read first thing in any session that touches the realignment work
units (tenant drop, MCP scope simplification, Channel + Video edit surfaces,
Analytics, Game model, Calendar, Notifications, CLI parity).

**Source:** 2-hour Claude Mobile session on 2026-05-09 dropped 8 notes into
`docs/notes/`; follow-up direction conversation locked the meta-decisions.

**Summary:**

The realignment is the foundational doc for the rest of beta. It categorizes
every existing spec / phase / surface (keep / modify / drop / pending) and
orders 12 work units the master agent dispatches over the coming months. Three
ADRs lock the meta-decisions:

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — drop
  `tenant_id` from every domain table; collapse to single-install, multi-user.
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — collapse 9 scopes
  to 2 (`dev` + `app`); strip `dev` on release packaging.
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — Doorkeeper
  surface survives the tenant drop; Claude Mobile + Web MCP load-bearing.

The top-level direction map at `docs/realignment-2026-05-09.md` is the
authoritative reference. Per-phase additions / dropped tracking lives at:

- `docs/plans/beta/12-auth-ui-multi-user-readiness/dropped.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/additions.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/dropped.md`
- `docs/plans/beta/7.5-followups-and-foundations/additions.md`
- `docs/plans/beta/7.5-followups-and-foundations/dropped.md`

**Action:** the master agent's next concrete dispatch is **Tenant drop** — the
first of the 12 ordered work units. After user reviews the realignment doc and
resolves the open ambiguities listed there, dispatch `pito-architect-spec` to
produce the implementation spec. Each subsequent work unit follows in roadmap
order.

**Open ambiguities for user (10 items, summarized):**

1. Phase 7.5 pre-spec 08 (Timelines) — defer or resurrect?
2. Phase 7.5 pre-spec 09 (MCP sync) — drop abstract framing or build state-
   mirroring?
3. Phase 7.5 pre-spec 10 (Terminal sync) — drop or build live state- mirroring?
4. Token migration on scope simplification — rotate-on-deploy or in-place
   rename?
5. Calendar UI shape — full-page grid, list, both?
6. Notifications "all users see all" or "per-user opt-in"?
7. Pre-publish checklist scope — also for metadata edits?
8. Phase numbering — where does the first new spec live in the docs tree?
9. `Tenant` model — drop entirely vs. downgrade to `AppInstall` row?
10. Path A2 reversal scope — owned only or owned + tracked?

Full text in `docs/realignment-2026-05-09.md`.

### CLI feature-parity sweep — channels list / videos list / settings panes / search results

**Trigger:** post-realignment per-domain CLI parity work unit (work unit 10 in
`docs/realignment-2026-05-09.md`).

**Source:** Phase 7.5 Track B step 02 (CLI hygiene + screen-layout parity sweep)
closed under `718996c`. The parity sweep focused on the channel-detail action
legend, the help screen, and the dashboard placeholder copy — three
discrepancies fixed in flow. Eight cross-stack gaps were surfaced and explicitly
carved out of scope.

**Summary:**

The Phase 7.5 parity sweep aligned the small, single-screen discrepancies but
left the bigger column-reconciliation gaps for a dedicated parity work unit:

- Channels list — column set parity with the Rails table.
- Videos list — column set parity with the Rails table.
- Settings panes — pane-by-pane parity (layout + which fields render where).
- Search results — disabled-stub state vs. Rails-side disabled affordance.

**Action:** during the per-domain CLI parity work unit, walk these four surfaces
and reconcile column sets / pane layouts / disabled affordances against the
canonical Rails surface (per the parity rule documented in the "`pito` CLI
screen layout parity with Rails app" guidance, now superseded for single-screen
drift but still relevant for these multi-column reconciliations).

### Footage importer-side ffmpeg frame extraction + bulk PATCH upload

**Trigger:** paired with the next dispatch that touches the footage importer, OR
a dedicated "fill in real footage thumbnails" pass.

**Source:** Phase 7.5 spec 06 (footage thumbnails) shipped the Rails endpoints
(`PATCH /api/footages/:id/frames` bearer-authed) and the CLI image-rendering
pipeline under `f5fdb01`. The importer half — ffmpeg extraction + multipart
upload to the new endpoint — was explicitly carved out as a future dispatch.

**Summary:**

Until this lands, footage thumbnails on `/projects/:id` and the per-footage
scrub UI render as broken-image glyphs (404) until JPEGs are seeded under
`<assets_root>/footage_thumbs/<id>/{m,t}/...` by hand. The plumbing on both ends
is in place; only the importer's frame-extraction step is missing.

**Action:**

1. Add ffmpeg-driven frame extraction to the footage importer (one frame at 50%
   of duration as the master, plus N strip frames per `Footage.duration`).
2. Multipart-encode the extracted JPEGs and POST them via
   `PATCH /api/footages/:id/frames` with the bearer token.
3. Stamp `frames_extracted_at` server-side (already wired); CLI surfaces the
   extracted frames automatically once the response lands.

**Verification:** an importer run against a fresh footage row populates the
`m/<HH-MM-SS>.jpg` master + `t/<HH-MM-SS>.jpg` strip frames on disk; the
project-page row thumb fills in; the scrub UI's hover walks the extracted
frames.

**Tenant-drop interaction:** after Phase 8's tenant drop, the per-tenant path
prefix (`<root>/<tenant_id>/footage_thumbs/...`) collapses to
`<root>/footage_thumbs/...`. The importer dispatch picks up the post-drop path
shape; no extra hop needed if it lands after the tenant drop.

### Phase 7.5 smoke integration spec (optional)

**Trigger:** if the Phase 19 close-out playbook surfaces any regression that a
wider integration test would have caught.

**Source:** Phase 19 close-out spec
`docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
§"Optional smoke spec". Architect's recommendation: skip; master agent decision
1 confirms skip. Tracked here so the option is not lost if a future reviewer
flips the call.

**Summary:** A "Phase 7.5 smoke" integration spec under
`spec/integration/phase_7_5_smoke_spec.rb` would touch each shipped Phase 7.5
surface in a single example run (keyboard shortcuts modal renders, footage
thumbnail URL responds, `Pito::AssetsRoot.root` resolves, etc.).

**Action:** if the trigger fires, escalate to a follow-up `pito-rails-impl`
dispatch — never folded into the docs-keeper's commit.

### 2026-05-10: Realignment paperwork landed. Tenant-drop spec dispatch pending (target: `docs/plans/beta/08-tenant-drop/`). Phase 7.5 closed by the Phase 19 close-out commit.

### Rails JSON endpoints for CLI/MCP parity (Phases 14/15/16)

**Trigger:** AFTER Phase 20 friendly URLs work lands in main (currently in
flight 2026-05-10 21:35). After the JSON endpoints land, the CLI parity agent
(`pito-rust`) can add `pito games`, `pito calendar`, `pito notifications`
subcommands; the MCP agent (`pito-mcp`) can add tool tools for the same
surfaces.

**Source:** 2026-05-10 CLI parity sweep — enumerated the missing Rails JSON
endpoints the CLI / MCP surfaces need to add `games`, `calendar`, and
`notifications` parity. The HTML surfaces ship in Phases 14 / 15 / 16; the JSON
cousins are the gap.

**Summary:**

The CLI parity sweep on 2026-05-10 walked the Phase 14 (Games), Phase 15
(Calendar), and Phase 16 (Notifications) surfaces and identified the JSON
endpoints each Rails controller needs to grow before the CLI and MCP agents can
pick up the parity work. The HTML controllers exist (or are scheduled) per the
respective phase plans; this entry tracks the JSON cousins specifically.

**Games (Phase 14)** — `app/controllers/games_controller.rb`

- GET /games.json (list with sort + filter params)
- GET /games/:id.json (full record incl. IGDB-sourced metadata)
- POST /games/:id/resync.json (acknowledge enqueue)
- GET /games/search.json?q= (IGDB type-ahead)

**Calendar (Phase 15)** — `app/controllers/calendar/`

- GET /calendar/schedule.json (paginated; mirror ?types/source/state/page
  params)
- GET /calendar/month/:year/:month.json (entries grouped by date for grid)
- GET /calendar/entries/:id.json (detail incl. parent/child entries + dispatch
  declarations)
- POST /calendar/entries.json
- PATCH /calendar/entries/:id.json
- PATCH /calendar/entries/:id/note.json (read-only-bypass note endpoint)
- DELETE /deletions/calendar_entry/:ids.json (soft-cancel)

**Notifications (Phase 16)** — `app/controllers/notifications_controller.rb`

- GET /notifications.json (paginated; ?filter=unread|all, ?kind=, ?severity=,
  ?page=)
- GET /notifications/:id.json (detail w/ NotificationFormatter::InApp payload)
- Badge state surface (unread_count, has_failures)
- PATCH actions already speak JSON via 204; need data response carrying new
  state + unread_count

**When to schedule:** AFTER Phase 20 friendly URLs work lands in main (currently
in flight 2026-05-10 21:35). After the JSON endpoints land, the CLI parity agent
(`pito-rust`) can add `pito games`, `pito calendar`, `pito notifications`
subcommands; the MCP agent (`pito-mcp`) can add tool tools for the same
surfaces.

**Note:** Saved-views controller (`app/controllers/saved_views_controller.rb`)
and search controller (`app/controllers/search_controller.rb`) are the existing
JSON-rendering reference patterns. Use `.jbuilder` views for multi-field shapes.

### Analytics window-summary click-rate ratios via dedicated impressions / card-performance reports

**Trigger:** when the architect picks up a "phase 13.3 / window-summary
fidelity" pass; gated on the existing C1 + C2/V2 basic-stats path being stable.

**Source:** Phase 13.2 fix-forward (2026-05-11). C1 was first reduced to
`DAILY_BASIC_METRICS` (impressions / cards / engagement removed) after YT
rejected the combined daily set with
`400 badRequest: The query is not supported.`. C2 (channel window summary) and
V2 (video window summary) hit the same rejection because `WINDOW_RATIO_METRICS`
mixed `averageViewPercentage` (basic-stats ratio) with three click-rate ratios
that live in different reports. The fix dropped the click-rate ratios from the
window-summary call so C2 + V2 go through.

**Rejected metrics (currently not fetched by C2 / V2):**

- `videoThumbnailImpressionsClickRate` — lives in the impressions report.
- `cardClickRate` — lives in the card-performance report.
- `cardTeaserClickRate` — lives in the card-performance report.

The DB columns for these ratios are still present on `channel_window_summaries`
and `video_window_summaries` (and on `video_daily_by_traffic_sources` for the
traffic-source variant) — they just stay `NULL` until this follow-up ships.

**Action when triggered:** spec the additional `reports.query` calls against the
impressions and card-performance reports (one per report, per channel / video,
per window), then merge the returned ratio rows back into the window-summary
upserts at the rollup layer. The current `ChannelAnalyticsSync` /
`VideoAnalyticsSync` already read these keys from the `pairs` map and write them
via `dec_or_nil` — so adding the parallel calls and merging into the same
`pairs` hash before the upsert is the minimal-surface change. Verify against the
YT Analytics docs for the exact metric / dimension shape each report accepts.
Add an integration spec that exercises the merged upsert and a regression spec
asserting C2 + V2 still issue the basic-stats window summary as a separate call
(do NOT re-merge the click-rate ratios into the basic-stats call). Tracking note
for `WINDOW_RATIO_METRICS` lives inline at
`app/services/youtube/analytics_query_builder.rb`.

### Search revamp

**Search revamp** — `/` keybinding on `/games` and `/games/:id` currently opens
a `[TBD]` placeholder modal (via `StatusTbdBadgeComponent`). The actual search
experience needs a dedicated spec + dispatch. Once it lands, the placeholder
modal is replaced everywhere `/` is bound.

### FN3 — IGDB sync preserves user-added platforms (spec coverage required)

**Implementation landed** (2026-05-18 iteration mode): `Igdb::SyncGame#sync_platforms`
now scopes destroys to `from_igdb` only, and the upsert skips existing rows so
user-set `source: "user"` rows survive across syncs. Specs deferred per the
defer-specs-during-iteration discipline; capture here for the consolidation
pass.

**Canonical example** for tests: Red Dead Redemption (RDR1) — IGDB returns only
PS3 / Xbox 360. After user clicks `[owned] PS` (FN2 → adds PS5 row with
`source: "user"`), an IGDB sync must:

1. Re-upsert PS3 / Xbox 360 as `source: "igdb"`.
2. Leave PS5 (`source: "user"`) UNTOUCHED.

**Spec cases to cover:**

- Game with no IGDB PS platforms + user marks owned PS → after IGDB sync, the
  `GamePlatform` row for PS5 with `source: "user"` still exists.
- Game with IGDB PS4 + user marks owned PS → PS4 row stays as `source: "igdb"`,
  no duplicate row created.
- IGDB sync removes ONLY rows in the `from_igdb` scope when IGDB no longer
  returns them — `source: "user"` rows survive.
- Multiple consecutive IGDB syncs preserve the user-source row.
- User-source row is also visible in `game.platforms_available` (the join is
  source-agnostic).
- Filter `/games?filters=ps` includes a game whose only PS platform is
  `source: "user"`.

**File targets for the spec consolidation pass:**

- `spec/services/igdb/sync_game_spec.rb` — preservation cases.
- `spec/controllers/games/ownership_toggles_controller_spec.rb` (or request
  spec) — upsert with `source: "user"`.
- `spec/services/games/filter_spec.rb` — filter includes user-source PS games.

## Done

### YouTube credentials hot-rotation gap (omniauth boot-time read)

**Resolved:** 2026-05-15 by Phase 29 Unit A1 / ADR 0012. YouTube credentials
moved off `AppSetting` back to `Rails.application.credentials.google_oauth`; the
omniauth initializer reads them directly, so there is no longer a hot-rotation
gap to close — credentials are deploy-time config rotated via
`bin/rails credentials:edit` + redeploy. Supersedes ADR 0007.

### Meilisearch indexing parity with Voyage per-target flags

**Resolved:** 2026-05-15. The Voyage half of the pairing closed with Phase 29
Unit A1 / ADR 0012 — the Voyage API key moved off `AppSetting` back to
`Rails.application.credentials`, and the Settings → Voyage pane slimmed to the
enable toggle. The Meilisearch parity work the original entry tracked is
withdrawn alongside the Voyage AppSetting revamp it was pairing with; if
per-target Meilisearch reindex controls are wanted in the future, dispatch a
fresh architect spec against the post-A1 settings surface rather than
resurrecting this entry.

### Channel Revamp post-commit cleanup

**Shipped:** `718996c` on 2026-05-07 (Phase 7.5 Track A step 01 — Rails-side
hygiene sweep).

`app/views/shared/_confirm_dialog.html.erb` and
`app/javascript/controllers/confirm_dialog_controller.js` were deleted outright.
The unused `confirm:` kwarg was removed from
`app/components/bracketed_link_component.rb`, with the matching spec updates.
Post-deletion grep returns zero matches; full RSpec + Brakeman remained green.

### Rails-app keyboard shortcuts

**Shipped:** `f5fdb01` on 2026-05-09 (Phase 7.5 Track C spec 04 — Rails keyboard
shortcuts).

The Rails surface now mirrors the `pito` CLI keymap one-for-one (master agent's
Q6 = strict mirror; no web-only additions). `keyboard_controller.js` implements
the global key listener with the `g`-prefix state machine,
`KeyboardShortcutsModalComponent` renders the `?` modal grouped by section, and
the `[ ? ]` link anchors top-right of every layout. 33 new specs across
component + request + integration coverage. Five cross-stack gaps (browser- back
`q`, `:q` / Ctrl+C, `e` for channel-edit, `c` for connected toggle, list-row
`enter`) were documented and explicitly out-of-scope; they do not fold into this
entry's resolution.

### `pito` CLI screen layout parity with Rails app

**Shipped:** `718996c` on 2026-05-07 (Phase 7.5 Track B step 02 — CLI hygiene
sweep + screen-layout parity sweep).

Three single-screen discrepancies were aligned with the canonical Rails surface:
channel-detail action legend lost the `(s) star` keystroke hint (star/unstar
lives inline on the Starred KV row); the help screen dropped the stale `f y`
row; the dashboard placeholder copy was reconciled with web. Eight broader
cross-stack gaps (column reconciliation between channels list / videos list /
settings panes / search results) surfaced and were explicitly carved out — those
carry forward as "CLI feature-parity sweep" under `## Open`, targeted at the
per-domain CLI parity work unit (work unit 10 in the realignment).

### `pito` CLI Dependabot alert #1 (low severity) — `lru` + `paste` advisories via `ratatui 0.29.0`

**Shipped:** `718996c` on 2026-05-07 (Phase 7.5 Track B step 02 — CLI hygiene
sweep).

`extras/cli/Cargo.toml` bumped `ratatui` from 0.29.0 to 0.30.x. `cargo update`
refreshed `Cargo.lock`; both `RUSTSEC-2026-0002` (`lru`) and `RUSTSEC-2024-0436`
(`paste 1.0.15`) cleared in one move (master agent's Q3 = accept TUI breakage
and fix in-dispatch — zero callsite breakage materialized). `cargo audit` and
`cargo test` green post-bump.

### Pre-existing rustfmt drift in `extras/cli/`

**Shipped:** `718996c` on 2026-05-07 (Phase 7.5 Track B step 02 — CLI hygiene
sweep).

`cargo fmt` swept the workspace; the eight previously-drifted files (`app.rs`,
`commands/tui.rs`, `keys.rs`, `ui/dashboard.rs`, `ui/mod.rs`,
`ui/operation_progress.rs`, `ui/videos.rs`, `widgets/mod.rs`) reflowed clean.
`cargo fmt --check` exits 0 post-sweep; clippy + tests stayed green.

### OmniAuth scope-walk fallback simplification in `config/initializers/omniauth.rb`

**Shipped:** `718996c` on 2026-05-07 (Phase 7.5 Track A step 01 — Rails-side
hygiene sweep). Follow-up CI fix landed in `85453c1` (omniauth credentials
three-tier fallback + prettier sweep) when the loud-fail behavior tripped CI's
test-environment credentials block; the resolved shape is a single direct lookup
with explicit early-fail in production and a forgiving fallback for test/CI.

`config/initializers/omniauth.rb` simplified to a single direct lookup of
`Rails.application.credentials.google_oauth.{client_id, client_secret}`. The
belt-and-suspenders nil-safe walks were removed; missing credentials raise
during boot in development / production with a clear message instead of silently
falling through. RSpec + boot smoke green.

### Validate and commit Phase B-2 (note revamp + bulk on notes + inline-delete + double-delete consolidation)

**Shipped:** `4843db1` on 2026-05-04 ("Note editor revamp, project concept drop,
modal footer, pane bg").

The Phase B-2 working-tree changes on top of `11d2cbb` validated through the
manual flow listed in the original entry and committed as a single follow-up
commit. The new `GET /notes/:id` two-pane editor, `unsaved-form` Stimulus
controller, char/word counts, project-notes bulk-select, and the double-delete
consolidation (`NotesFilesystem.delete` removed from `NotesController#destroy`;
`before_destroy` callback is the single source of truth) all landed in flow.

### Agent definition sync — install monolith renames into `~/.claude/`

**Shipped:** `b833b12` on 2026-05-09 ("Add docs/agents/ stubs for installed
pito-\* agents").

The Phase 4 closeout sequence per the user's auto-memory bundled the agent
re-prefix pass with the install-script invocation. Runtime `~/.claude/agents/`
now mirrors the repo's expected pito-prefixed shape; `docs/agents/` carries the
per-agent stubs for the renamed set. Master / implementation dispatches in
subsequent sessions resolve to the `pito-architect`, `pito-rails`, `pito-mcp`,
`pito-docs`, `pito-reviewer`, `pito-auditor`, `pito-astro`, `pito-rust`,
`pito-security` names without falling back to legacy stubs.

### Re-prefix pito agents with `pito-*` for multi-project clarity

**Shipped:** `b833b12` on 2026-05-09 ("Add docs/agents/ stubs for installed
pito-\* agents"). Bundled with the Phase 4 closeout sequence per the user's
auto-memory.

Pito's installed agents now carry the `pito-*` prefix; cross-project ownership
is grep-able in `~/.claude/agents/`. The repo's source-of-truth documentation
moved from `.claude-config/agents/` to `docs/agents/` during the same pass; the
prefix change is reflected in every `subagent_type:` reference across
`CLAUDE.md` and the orchestration / playbook docs.

### Implement `--prune` flag on `install-claude-config.sh`

**Shipped:** `b833b12` on 2026-05-09 ("Add docs/agents/ stubs for installed
pito-\* agents"). Paired with the agent re-prefix pass per the user's auto-
memory; the orphaned unprefixed runtime files were swept during the same
closeout cycle.

The install-script `--prune` flag was implemented and exercised during the
re-prefix sweep (the install-script source itself lives outside this repo,
synced from the user's dotfiles per the convention noted in
`/home/catalin/.claude/projects/-home-catalin-Dev-pito/memory/MEMORY.md`). The
runtime cleanup verifies that no stale unprefixed agent files remain in
`~/.claude/agents/`.

### Phase 7.5 pre-specs 08 / 09 / 10 close-out

**Shipped:** Phase 19 close-out commit (2026-05-10). Suggested commit message:
`Phase 7.5 close-out — reconciliation, follow-ups disposition, plan complete`.

Phase 19 close-out
(`docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`)
reconciled the three pre-spec drops. The pre-spec files (08 Timelines, 09 MCP
sync, 10 Terminal sync) were deleted on 2026-05-10; durable record lives in
`docs/plans/beta/7.5-followups-and-foundations/dropped.md` and
`docs/realignment-2026-05-09.md` work unit 11 (which now carries the Resolution
line pointing back at the close-out). 07 (Games) remains preserved as historical
reference and absorbs into realignment work unit 6.

### Decorator slim question — re-evaluate Channel/Video summary JSON shape post-Path-A2

**Resolution:** Keep decorators as-is. The Path A2 directive was about not
pre-committing to a YouTube-metadata cache; aggregating computed values from
intentional sources (OAuth presence derivation, joined `video_stats` rollups) is
fundamentally different and provides legitimate API value. Spec 03
(`docs/plans/beta/7.5-followups-and-foundations/specs/03-decorator-slim-resolution.md`)
is the durable record of the decision.

**Date resolved:** 2026-05-07.

**Trigger:** Phase 7.5 polish window. Captured 2026-05-07 by the Phase 6+7+A2
reviewer playbook so the question doesn't have to be re-derived from scratch.

**Source:** Phase 6+7+Path-A2 reviewer playbook
`docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`.

**Summary:**

The Rails Path A2 retract slimmed the `Channel` and `Video` models to
`{url, star, oauth_identity_id, last_synced_at}` (plus the surviving columns)
but the matching decorators still emit a wider shape:

- `ChannelDecorator#as_summary_json` emits `connected` (derived from
  `oauth_identity_id.present?`) alongside the surviving model fields.
- `VideoDecorator#as_summary_json` emits `views` / `likes` / `comments` /
  `watch_time_minutes` / `trend` (computed by joining the surviving
  `video_stats` table).

The CLI's matching Rust structs in `extras/cli/src/api/models.rs` were aligned
to the wire shape, not the model.

**Question to revisit:** should the decorators be slimmed further to match the
model (full Path A2 symmetry — drop the derived/joined fields), or kept as-is
(storage stays thin, the API layer continues to aggregate)?

**Master agent's lean:** keep decorators as-is. The Path A2 directive was about
not pre-committing to a YouTube-metadata cache; aggregating computed values from
intentional sources (OAuth presence, the surviving `video_stats` table) is
fundamentally different. Captured here so 7.5 doesn't re-derive the question.

**Action:** in 7.5, confirm the master agent's lean (or flip it) and document
the resolution. If the lean holds, this entry closes with a one-line note in
`## Done` and no code change. If flipped, dispatch a rails-impl pass to slim the
two decorator methods + update specs + update the Rust structs to match.

### Non-default, pito-specific ports for Postgres / Redis / Meilisearch / Puma

**Shipped:** `185c016` on 2026-05-05.

Local services moved to pito-specific high ports (Web 3027, MCP 3028, Postgres
54327, Redis 64527, Meilisearch 7727), all 127.0.0.1-bound and env-overridable.
"27" suffix marker keeps them distinct from fepra's "18" family. Cloudflare
tunnel `~/.cloudflared/config.yml` was repointed to 127.0.0.1:3027 / 3028 by the
user out-of-band (config lives outside the repo). Bonus: `parallel_tests` worker
count capped at 8 via `PARALLEL_TEST_PROCESSORS=8` in CI yml,
`bin/parallel_setup`, and a new `bin/test` wrapper.

### Dedicated, pito-identifiable Docker volumes for Postgres / Redis / Meilisearch

**Shipped:** `185c016` on 2026-05-05.

Volumes named `pito-postgres-data`, `pito-redis-data`, `pito-meilisearch-data`
with explicit `name:` overrides on the top-level compose `volumes:` block to
prevent docker's project-prefix doubling. Old underscore-named volumes
(`pito_postgres_data` etc.) dropped during the swap; data was re-seeded via
`bin/setup`.
