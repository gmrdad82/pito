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

## Done

(Items move here after they ship, with commit hash + date.)
