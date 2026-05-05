# Follow-ups — deferred items tracked across phases

This file lists work items the architect or user has explicitly deferred — items
that should be picked up at a specified trigger condition, not now. Each item
names the trigger so it doesn't get lost.

When the trigger condition fires, a small dedicated agent should be dispatched
to handle the cleanup, run gates, and report. Once the item ships and commits,
mark it Done with the commit reference.

## Open

### Channel Revamp post-commit cleanup

**Trigger:** after Channel Revamp phase commits have landed on `main` across all
repos AND the user confirms the phase is closed (testing complete, validation
done).

**Items:**

1. Delete `pito/app/views/shared/_confirm_dialog.html.erb` — orphaned generic
   confirm dialog from Alpha. The May 2 2026 grep confirmed no callers anywhere.
2. Delete `pito/app/javascript/controllers/confirm_dialog_controller.js` —
   companion Stimulus controller. No `data-controller="confirm-dialog"`
   references in any view.
3. Remove the `confirm:` kwarg from
   `pito/app/components/bracketed_link_component.rb` — currently
   accepted-but-ignored after the modal refactor; no call sites use it. Update
   specs accordingly.

**Verification before deletion:**

- Re-run the grep used during the modal refactor to confirm continued orphanage:
  - `grep -rn "_confirm_dialog\|confirm_dialog_controller\|data-controller=\"confirm-dialog\"" app/`
  - Should return zero matches.
- After deletion: full RSpec suite + Brakeman remain green.

**Commit message suggestion:** `Remove orphaned confirm-dialog primitives`

### Rails-app keyboard shortcuts

**Trigger:** future phase, after Channel Revamp commits land. Could be folded
into a broader "polish / accessibility" phase or a dedicated "keyboard
navigation" phase.

**Items:**

The Pito Rails web app should adopt the same keyboard shortcut schema as the
`pito` CLI. The CLI dictates the canonical shortcuts; the web app follows.
Specifically:

1. Add a `?` keyboard binding to the web app that opens a keyboard-shortcuts
   modal. The modal lists all bindings grouped by section (general, navigation,
   channels list, channel detail, confirmation prompts, etc.) — same sections as
   the `pito` CLI's help dialog.
2. Add a visible `?` button at the top-right of every page, near the theme
   switcher. Clicking it opens the same modal as pressing `?`.
3. Implement the keyboard bindings themselves:
   - `?` — toggle help modal
   - `q` — back / close
   - `g d` / `g c` / `g v` / `g s` / `g e` — navigate to dashboard / channels /
     videos / saved views / settings
   - `n` — toggle dark/light theme
   - `/` — open search (focus the existing search input)
   - `j` / `k` — down / up in tables
   - `space` — toggle bulk select on highlighted row, ONLY when bulk mode is on
     (clicking `[bulk]` first). When bulk mode is off, `space` is a silent
     no-op. Mirrors the `pito` CLI's gated behavior.
   - `b` — toggle bulk mode
   - `s` — toggle star on highlighted row
   - `c` — toggle connected on highlighted row
   - `D` — delete selection (or current row)
   - `Y` — sync selection (or current row)
   - `f s` / `f c` / `f y` — filter chips toggle (starred / connected / syncing)
   - `v` — view URL in browser (channel detail)
   - `y` — confirm in confirmation dialogs
   - `Esc` / any other key — cancel in confirmation dialogs

Mirror the exact key bindings used in the `pito` CLI (verify by reading
`extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs` at the time of
implementation).

4. The shortcuts must NOT conflict with browser-level shortcuts (e.g., `Ctrl+F`
   for search stays browser; the in-app `/` opens the app's search input). Test
   with screen-reader compatibility.

5. Stimulus controller(s) handle the global key listener and the per-screen
   behaviors. Multi-key sequences like `g d` need a state machine (similar to
   vim's leader-key prefix).

6. The modal that opens for `?` reuses or mirrors the `ConfirmModalComponent`
   styling — match the design system. Lists the bindings in the same grouping as
   the `pito` CLI's help screen.

**Verification before implementation:**

- Read the `pito` CLI's keyboard schema at the time of implementation
  (specifically `extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs`) to
  capture any updated bindings.
- Confirm with the user that the schema is still desired before coding.

### `pito` CLI screen layout parity with Rails app

**Trigger:** any future phase that touches a `pito` CLI screen, OR a dedicated
polish pass after the current phase commits.

**Items:**

The `pito` CLI (`extras/cli/`) and the Rails web app should mirror each other in
screen layout, link placement, and which links/actions are available where. The
Rails app dictates the canonical layout; the `pito` CLI follows.

Known discrepancies as of 2026-05-03 (Channel Revamp validation):

1. **Channel detail screen — top action legend:** the `pito` CLI currently shows
   `[view] [sync] [delete]   (v) view  (Y) sync  (D) delete  (s) star` at the
   top. Web shows only `[view] [sync] [delete]` in the breadcrumb actions. The
   `(s) star` keystroke hint should NOT appear at the top — star/unstar lives
   inline on the Starred row (mirrors web's `[star] / [unstar]` button on the
   Starred KV row).

2. **Sync link placement:** verify the `pito` CLI's `[sync]` button placement
   matches web's. Web has `[sync]` in the breadcrumb actions row. The CLI should
   match.

3. **Other discrepancies:** sweep every screen — channels list, channel detail,
   videos list, video detail, dashboard, search, settings — and surface every
   layout/link mismatch. Document each in this entry as a sub-bullet before
   fixing.

**Implementation strategy:**

- Read the corresponding Rails ERB views first; they're the spec.
- Map each Rails action / link / data display to the `pito` CLI equivalent.
- Where the `pito` CLI diverges (extra hints, missing actions, different
  placement), align to Rails.
- Where the divergence is intentional (e.g., terminal-only keystroke hints in
  the help screen), document and keep.
- One Stimulus-style "actions row" matches one TUI "breadcrumb actions" line.
  One inline button matches one inline keystroke hint, etc.

**Verification before implementation:**

- Open both surfaces side-by-side. Take screenshots of each Rails screen + the
  matching `pito` CLI screen.
- Diff them mentally / on paper.
- Confirm the spec captures every discrepancy before dispatching the
  implementer.

**Out of scope for this follow-up:**

- Adding NEW features to either side (e.g., implementing keyboard shortcuts in
  Rails — that's the separate "Rails-app keyboard shortcuts" follow-up).
- Refactoring the visual design system itself.
- Adding screens that don't yet exist on one side.

This follow-up is about parity, not feature parity. It strictly aligns the
EXISTING screens.

### `pito` CLI Dependabot alert #1 (low severity)

**Trigger:** the next time the `pito` CLI is touched, OR a dedicated
dependency-hygiene pass.

**Items:**

GitHub Dependabot flagged 1 low-severity vulnerability on the `pito` repo's
default branch after the Channel Revamp commit (`0e096b7`), originating from the
Rust crates under `extras/cli/`. Surfaced via the `git push` warning:

```
remote: GitHub found 1 vulnerability on gmrdad82/pito's default branch (1 low).
remote:      https://github.com/gmrdad82/pito/security/dependabot/1
```

**Actions:**

1. Visit the Dependabot alert in the `pito` repo's Security tab to identify the
   vulnerable crate and the recommended fix version.
2. Bump the affected dependency in `extras/cli/Cargo.toml` to the patched
   version. Run `cargo update` to refresh `Cargo.lock`.
3. `cargo check --all-targets` and `cargo test` must pass after the bump.
4. Commit + push to `main`. Verify the alert clears on GitHub.

**Note:** low severity, not blocking — but worth clearing during normal dev
hygiene rather than letting it sit. Same approach for any future Dependabot
alerts on the `pito` repo.

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

### Agent definition sync — install monolith renames into `~/.claude/`

**Trigger:** Architect noticed 2026-05-04 during Phase B closing review. Quiet
drift between `.claude-config/agents/` (repo) and `~/.claude/agents/` (runtime).

**Source:** Mid-Phase-4 conversation between user and architect during Phase B
reviewer pass. Confirmed via `ls .claude-config/agents/` vs
`ls ~/.claude/agents/`.

**Summary:** During the monolith pivot the four `pito-*` agent files were
renamed to `<lane>-impl` style and a new `website-impl` agent was added. Those
changes landed in `.claude-config/agents/` (the repo source of truth) but were
never installed into `~/.claude/agents/` (the Claude Code runtime). The runtime
still has the legacy `pito-mcp.md`, `pito-rails.md`, `pito-sh-impl.md` from the
four-repo era. All Phase 4 dispatches in this session ran via the legacy names
because those are what's actually live; the renamed files in the repo have been
inert. Functionally it works (legacy files still describe the agents correctly),
but post-monolith updates to the renamed files don't reach the runtime, and the
new `website-impl` agent isn't available at all.

**Action:** Three steps, run from `/home/catalin/Dev/pito/`:

1. `./docs/orchestration/scripts/install-claude-config.sh` — installs the new
   and renamed files (`cli-impl.md`, `mcp-impl.md`, `rails-impl.md`,
   `website-impl.md`) into `~/.claude/agents/`. The script is mtime-safe and
   idempotent; it never deletes.
2. Manually remove the orphaned legacy files (the script doesn't auto-delete to
   protect user-installed agents):
   ```
   rm ~/.claude/agents/pito-mcp.md \
      ~/.claude/agents/pito-rails.md \
      ~/.claude/agents/pito-sh-impl.md
   ```
3. Restart Claude Code so the agent registry picks up the new names.

**Verification:** New session opens with `cli-impl`, `mcp-impl`, `rails-impl`,
and `website-impl` available as `subagent_type` values. Old `pito-*` names no
longer match. `ls ~/.claude/agents/` shows nine files matching
`.claude-config/agents/`. Architect dispatches in the next session use the
renamed names without falling back to legacy stubs.

> **Timing.** Run AT THE END of the current session (after the Phase B commit +
> push) OR AS THE FIRST THING in the next session — either path ensures the next
> session starts with synced agent definitions. Don't run mid-session: a partial
> registry refresh while agent dispatches are in flight could confuse Claude
> Code's name resolution.

> **Future enhancement (separate follow-up if it sticks):** add a `--prune` flag
> to `install-claude-config.sh` that deletes `~/.claude/agents/*.md` files
> without a counterpart in `.claude-config/`. Gated behind the flag because the
> script's current "never deletes" property protects user-installed agents that
> don't live in this repo.

### Meilisearch indexing parity with Voyage per-target flags

**Trigger:** User surfaced 2026-05-04 alongside the Voyage AppSetting revamp
dispatch (project-workspace log entry: "Voyage revamp: encrypted key on
AppSetting + per-target flags").

**Source:** Mid-Phase-4 conversation — the same shape the user wanted for Voyage
(per-target Boolean flags instead of a single all-or-nothing boolean) should
apply to Meilisearch indexing.

**Summary:** Meilisearch currently indexes channels and videos via background
jobs (the existing pre-Phase-4 search infrastructure). Phase 4 added
project-notes indexing on top, dual-writing alongside the Voyage pgvector
pipeline. As more index targets land (notes from videos, video metadata
enrichment, channel metadata enrichment), the indexing surface needs the same
per-target on/off control Voyage just got. Today's `[ reindex ]` button on the
search fieldset is all-or-nothing: it triggers a sweep without distinguishing
which target. The user wants per-target reindex buttons + per-target enable
flags so we can develop / tune one index target without disturbing others.

**Action:** Add per-target Boolean columns to AppSetting matching the Voyage
shape — e.g., `meilisearch_index_channels`, `meilisearch_index_videos`,
`meilisearch_index_project_notes` (more added as new index targets ship). Update
the existing Meilisearch reindex job(s) to honor those flags (if a target's flag
is false, skip its reindex sweep). Update the `search` fieldset on the Settings
page to expose per-target toggles AND per-target `[ reindex <target> ]` buttons.
Pick a representation for the indexed-document counts shown today — they
currently display per-index (channels_development, channels_test,
videos_development, videos_test). When project-notes-indexing lands its own
count, surface it the same way.

**Verification:**

1. Toggling `meilisearch_index_channels` to false then triggering channel sync
   (or hitting the channels reindex job directly) does NOT touch Meilisearch.
2. Per-target `[ reindex ]` button under the search fieldset reindexes only that
   target.
3. The all-or-nothing `[ reindex ]` button is removed (or repurposed as "reindex
   all enabled targets").
4. Specs cover each target's no-op branch (flag false → no Meilisearch HTTP) and
   active branch.
5. The `voyage:smoke_test` rake task gets a `meilisearch:smoke_test` sibling
   that probes connectivity without doing a full reindex.
6. Settings UI displays the indexed-document counts per target alongside the
   toggle.

> **Pairs with the Voyage revamp.** This follow-up should be tackled together
> with — or shortly after — the Voyage AppSetting revamp lands, so the Settings
> page's "search" and "voyage" fieldsets stay structurally parallel. Both use
> per-target Boolean flags; both surface per-target action buttons; both share
> the same UI affordances.

### Re-prefix Pito agents with `pito-*` for multi-project clarity

- **Trigger:** User surfaced 2026-05-04 after evaluating a parallel Claude-agent
  setup in another project (Fepra) that prefixes all its agents with `fepra-*`.
- **Source:** Mid-Phase-4 conversation between user and architect. Fepra's
  analysis flagged the prefix as collision-avoidance against the OLD `pito-*`
  allow-list; with pito's monolith rename to unprefixed names (`architect-spec`,
  `cli-impl`, etc.), there's no collision today, BUT the asymmetric naming makes
  `~/.claude/agents/` harder to grok at a glance — `architect-spec.md` is
  anonymously pito's; `fepra-architect.md` is explicitly fepra's.
- **Summary:** Re-prefix Pito's nine agents to `pito-*` so cross-project
  ownership is grep-able and future projects can join the host shell without
  contention. Renames: `architect-spec` → `pito-architect-spec`; `audit-state` →
  `pito-audit-state`; `cli-impl` → `pito-cli-impl`; `docs-keeper` →
  `pito-docs-keeper`; `mcp-impl` → `pito-mcp-impl`; `rails-impl` →
  `pito-rails-impl`; `reviewer` → `pito-reviewer`; `security-auditor` →
  `pito-security-auditor`; `website-impl` → `pito-website-impl`. (Or pick a
  shorter prefix like `p-` if `pito-` feels long — implementer's call.) Update
  every `subagent_type:` reference in `CLAUDE.md`,
  `docs/orchestration/agents.md`, all dispatch documentation in the architect's
  playbook, and any `.claude-config/commands/` or `.claude-config/skills/` that
  reference agent names. Run `install-claude-config.sh` to install the renamed
  files into `~/.claude/agents/`. Manually delete the orphaned unprefixed files
  from `~/.claude/agents/` (the install script doesn't auto-delete — see the
  related `--prune` follow-up).
- **Action:**
  1. Rename files in `<repo>/.claude-config/agents/` (`git mv` to preserve
     history).
  2. Update agent self-references inside the renamed files (each file's
     frontmatter `name:` field, and any `Subagent reference:` cross-pointers in
     the prompt body).
  3. Sweep `CLAUDE.md`, `docs/orchestration/agents.md`,
     `docs/orchestration/lanes.md`, `docs/orchestration/follow-ups.md`,
     `docs/plans/beta/<phase>/log.md` and update mentions where they appear in
     user-facing copy. Don't rewrite historical log entries — those are frozen
     records of past dispatches that used the old names.
  4. Run `./docs/orchestration/scripts/install-claude-config.sh --yes` to
     install the renamed files into `~/.claude/agents/`.
  5. After confirming the new names work in a fresh Claude Code session,
     manually delete the orphaned unprefixed files from `~/.claude/agents/` (or
     use the `--prune` flag if the related follow-up has landed by then).
- **Verification:** A new Claude Code session in `~/Dev/pito/` opens with
  `pito-architect-spec`, `pito-cli-impl`, etc. available as `subagent_type`
  values. The unprefixed names no longer match.
  `ls ~/.claude/agents/ | grep pito-` shows nine files. Architect dispatches in
  the next session use the prefixed names without falling back to the old
  unprefixed stubs.

> **Timing.** Bundle with the next agent-sync pass — not urgent. Coordinate with
> the `--prune` follow-up so both edits land in one cycle and the orphaned
> unprefixed files get cleaned up automatically.

### Implement `--prune` flag on `install-claude-config.sh`

- **Trigger:** User surfaced 2026-05-04 alongside the agent re-prefix follow-up.
  Originally captured as a future enhancement sub-bullet under the agent-sync
  follow-up; promoted to its own entry now that Fepra and future multi-project
  sync make it more pressing.
- **Source:** Architect's evaluation of Fepra's parallel Claude setup. The
  accumulating-orphans problem is generic to any repo with a sync script that
  "never deletes" — Fepra will hit it too once their script lands.
- **Summary:** Add a `--prune` flag to
  `docs/orchestration/scripts/install-claude-config.sh` that deletes any
  `~/.claude/agents/<name>.md` (and `commands/`, `skills/`) that doesn't have a
  counterpart in this repo's `.claude-config/`. Critical safety property: the
  prune is scoped to THIS repo's allow-list — `--prune` from pito's script never
  touches `fepra-*.md` or any other project's files. Implementation: collect the
  source file names from `<repo>/.claude-config/{agents,commands,skills}/`; for
  each `~/.claude/{agents,commands,skills}/` file, if its name matches a "this
  could plausibly belong to this repo" pattern (e.g. unprefixed for current pito
  naming, or `pito-*` after the re-prefix follow-up), AND it's NOT in the source
  list, delete it. Files that match neither pattern (e.g. `fepra-*.md`) are LEFT
  ALONE. The current "never deletes" property is preserved by default; `--prune`
  is opt-in.
- **Action:**
  1. Update `install-claude-config.sh` to accept a `--prune` flag.
  2. Define the "this repo's namespace" predicate. Today: any unprefixed name.
     Post-rename: `^pito-`. Capture in a top-of-script variable so it's easy to
     update.
  3. The prune step runs AFTER the install step so the new files are guaranteed
     to exist before potentially-orphaned old files are removed.
  4. Add a `--dry-run` interaction with `--prune`: print which files WOULD be
     deleted, exit without deleting.
  5. Update the script header comment + the `README.md` in the same directory.
- **Verification:** Running `install-claude-config.sh --prune --dry-run` from a
  checkout that has dropped `mcp-impl.md` (e.g. mid-rename) prints
  `WOULD DELETE ~/.claude/agents/mcp-impl.md` and exits without changing
  anything. Running `--prune` (no dry-run) actually deletes it. Files matching
  `fepra-*.md` are NEVER listed as deletion candidates regardless of flag
  combinations.

> **Timing.** Pair with the agent re-prefix follow-up — the prune step handles
> the cleanup of unprefixed orphans automatically once both land.

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

### Validate and commit Phase B-2 (note revamp + bulk on notes + inline-delete + double-delete consolidation)

- **Trigger:** User opted to defer validation + commit of the Phase B-2 body
  while continuing iteration on other surfaces. Phase B-2 landed as uncommitted
  working-tree changes on top of `11d2cbb` (the Phase B commit on `main`).
- **Source:** Mid-Phase-B-2 conversation between user and architect on
  2026-05-04 after the rails-impl dispatch reported clean (1042 → 1056 / 0, +14
  specs, Brakeman 0, RuboCop 0, migration `20260504000012_add_counts_to_notes`
  reversible).
- **Summary:** The note editor was rewritten as a single `GET /notes/:id`
  two-pane page (rendered markdown preview | source textarea), with live preview
  via `marked@15.0.7` + `dompurify@3.2.4` (importmap-pinned), char/word counts
  as model columns + status bar at the bottom of the source pane, an
  `unsaved-form` Stimulus controller that triggers the browser's native
  `beforeunload` "Leave site?" dialog (documented as a carve-out in `CLAUDE.md`
  under the "no JS confirms" hard rule), bulk- select on the notes pane (delete
  only), and consolidation of the destroy double-delete (the explicit
  `NotesFilesystem.delete` call in `NotesController#destroy` was removed; the
  `before_destroy` callback is now the single source of truth). The `[ delete ]`
  audit found no drift to fix on other edit screens.
- **Action:**
  1. Walk through the new note editor in `bin/dev` — `GET /notes/:id` opens the
     editor; type in the source pane and watch the rendered pane update live;
     verify char/word counts increment in the status bar; verify the
     `[ delete ]` button opens `ConfirmModalComponent`.
  2. Verify the auto-derived title — type `# My new note` as the first line;
     save; the breadcrumb / pane row updates to "My new note".
  3. Verify `unsaved-form` — make a change without saving, try to navigate away;
     the browser's native unsaved-changes prompt should fire. Save first, then
     navigate; no prompt.
  4. Verify bulk-select on the project's notes pane — `[ bulk ]` toggle reveals
     checkboxes; selecting two notes + clicking the bulk delete action routes to
     `/deletions/note/<id1>,<id2>`.
  5. Verify cascading delete — destroy a project, confirm the note files under
     `<PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/` are gone (single
     source of truth via the `before_destroy` callback + `after_destroy_commit`
     directory cleanup).
  6. If everything passes, commit + push as a follow-up commit on `main`.
     Suggested message:
     `Phase B post-commit: note revamp, bulk on notes, double-delete consolidation`.
- **Verification:** RSpec suite green at 1056 / 0 (already verified by the
  dispatch). Post-commit, the user re-runs the manual flow above against
  `bin/dev` to confirm UX actually behaves as the specs assert.
- **Cross-reference:** `docs/plans/beta/04-project-workspace/log.md`'s `###
  Phase B post-commit — Note revamp + bulk on notes + inline-delete
  - double-delete consolidation (2026-05-04)` subsection captures the full diff
    narrative.

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

### Pre-existing rustfmt drift in extras/cli/

**Trigger:** next time the affected files are touched substantively, OR a
dedicated CLI hygiene pass.

**Source:** Flagged 2026-05-06 by Wave 2 Lane E. `cargo fmt --check` over the
workspace flags drift in:

- `extras/cli/src/app.rs`
- `extras/cli/src/commands/tui.rs`
- `extras/cli/src/keys.rs`
- `extras/cli/src/ui/dashboard.rs`
- `extras/cli/src/ui/mod.rs`
- `extras/cli/src/ui/operation_progress.rs`
- `extras/cli/src/ui/videos.rs`
- `extras/cli/src/widgets/mod.rs`

None introduced by today's work; these were already drifted before Wave 2.

**Action:** `cargo fmt --manifest-path extras/cli/Cargo.toml` over the workspace
at a quiet moment. Verify clippy + tests stay green post-format.

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

## Done

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
