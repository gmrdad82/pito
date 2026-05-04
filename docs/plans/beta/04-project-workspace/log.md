# Phase 4 — Project Workspace · Session Log

## 2026-05-04 — Step 0 — MCP Dev KB surface

**State at start:** Phase 3 (Channel Revamp) committed and pushed. The
multi-repo split was consolidated into the monolith earlier in the week
(commit `2a920e3`), so `pito-sh` is now `extras/cli/`, the website lives at
`extras/website/`, and the dev knowledge base merged into `docs/`. Phase 4
master spec
(`docs/plans/beta/04-project-workspace/specs/project-workspace.md`) is in
place but no Phase 4 implementation has started. The MCP server at
`mcp.pitomd.com` (Cloudflare tunnel, single-user, no auth concerns yet) was
running with the existing Channel/Video tool surface only — no docs surface,
no Mobile-side capture path.

**Decisions captured before execution:**

- The user wanted natural conversation flow between Desktop Claude (this
  Claude Code session, file-system access) and Claude Mobile (over the
  existing MCP server). Claude Code's first sketch was a generic three-tool
  docs surface (`list_docs`, `read_doc`, `write_doc`). The user pushed back
  on the over-engineered shape and reframed the requirement: Mobile is a
  scratchpad-and-recovery surface, not a generic file system. Desktop
  curates; Mobile captures.
- Locked tool surface:
  - `list_docs` — filterable, mtime-sortable enumeration under `docs/`.
  - `read_doc` — single-file read by relative path, anywhere under `docs/`
    (logs, plans, specs, ADRs, curated reference docs).
  - `save_note` — write-only into `docs/notes/`. Server-generated filename
    `YYYY-MM-DD-HH-MM-SS-<slug>.md`. No overwrite. Multiple captures of the
    same thought are fine; cleanup is Desktop's job per the user's
    preference. Mobile never edits, deletes, or renames.
- Path safety: lexical containment via `Pathname#cleanpath`, traversal
  rejected. Symlink resolution via `realpath` was specced but skipped in
  implementation — Mobile cannot create symlinks, so practical risk is near
  zero. Captured as the single spec/implementation deviation in the
  reviewer playbook.
- Credentials wired up live in parallel: Voyage AI API key + a GitHub
  fine-grained PAT scoped to `gmrdad82/pito` with Contents:Read-only +
  Metadata:Read-only. Voyage embed call returned a 1024-dim vector for
  1 token billed; GitHub releases endpoint returned 200 with zero releases
  yet (workflow hasn't run).
- Two Phase 4 master spec amendments dropped out of the credential
  verification:
  - Voyage call gating (§3.5) — defaults `false` in dev/test, `true` in
    prod, env-var override. The user explicitly said don't fire Voyage on
    dummy data.
  - `pito version` prints the short build SHA (7 chars) instead of semver
    (§7), with §8.1 restating the served filename is always `pito` (no
    `-<sha>` suffix).

**What landed (file-level):**

- **Step 0 sibling spec:**
  `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md` (new).
- **Step 0 implementation:** `app/lib/dev_doc_path.rb` (path-safety helper);
  `app/mcp/tools/list_docs.rb`, `read_doc.rb`, `save_note.rb`; spec coverage
  at `spec/lib/dev_doc_path_spec.rb` and
  `spec/mcp/tools/{list_docs,read_doc,save_note}_spec.rb`. 62 new examples,
  0 failures. Full suite 746 / 0. Brakeman 0 warnings. RuboCop 0 offenses.
  The MCP server (`app/mcp/pito_server.rb`) auto-registers any
  `Mcp::Tools::*` class via cold-require — no edits to the server itself.
- **Folder normalization:** 16 phase folders renamed `<NN>-plan.md` →
  `plan.md` via `git mv` so `list_docs(name_pattern: "plan.md")` works
  cleanly. `beta.md` updated for the live phase index (14 path pointers).
  Frozen historical files (postgres-migration / channel-revamp specs and
  additions, pre-2026-05-04 playbooks) intentionally left with their old
  `<NN>-plan.md` references so they remain accurate historical records.
- **CLAUDE.md additions:** "Logging convention" section (codifying this
  log entry's format) + "MCP Dev KB surface (Mobile interop)" section.
- **Phase 4 master spec amendments**
  (`docs/plans/beta/04-project-workspace/specs/project-workspace.md`):
  - §3.5 "Voyage call gating (2026-05-04 amendment)" — flag, env override,
    EmbedJob short-circuit, `voyage:smoke_test` rake task.
  - §7 "Version output — short Git SHA (2026-05-04 amendment)" —
    `pito version` and `pito --version` print 7-char SHA from build-time
    embed (build.rs or vergen, cli-impl decides edge cases).
  - §8.1 served-filename restatement (always `pito`, no `-<sha>` suffix).
  - §15 acceptance-criteria additions for the three new behaviors.
  - §14 "Step 0 — MCP Dev KB surface (precedes Phase A)" pointer to the
    sibling spec.
- **Step 0 additions.md entry:**
  `docs/plans/beta/04-project-workspace/additions.md` (new) — records the
  scope addition with rationale.
- **Reviewer playbook:**
  `docs/orchestration/playbooks/2026-05-04-mcp-dev-kb-surface.md` — gates
  summary, six minor spec ambiguities resolved by implementation, one
  spec/implementation deviation (path-safety is lexical via `cleanpath`,
  NOT `realpath` as the spec said — symlink resolution skipped).
- **Follow-ups index** (`docs/orchestration/follow-ups.md`) — three new
  entries from the monolith pivot: CI cli-job working-directory not
  exercising workspace-root clippy; `Procfile.dev` / `bin/dev` /
  Rails-controller wiring for `extras/cli/target/release/pito` (zero
  references currently — Phase 4 decides); 14+ stale `pito-sh` comments in
  Rails controllers / config (rename sweep).
- **Empty inbox folder:** `docs/notes/.gitkeep`.
- **Commit:** `5faad26` "Add MCP Dev KB surface (Phase 4 Step 0)" — 34
  files, +1,699 / −13. Pushed to `origin/main`.

**Where we stand:**

- Phase 4 — Project Workspace. Step 0 (MCP Dev KB surface) shipped. Phase A
  (sequential foundation, 9 steps via `pito-rails` agent) is queued and
  unblocked: Voyage credentials + GitHub PAT both in place; Voyage gated
  off in dev/test until real notes flow. The user's go-ahead is the only
  thing standing between us and Phase A's `add_notes_syncing_at_to_tenants`
  migration.
- Open items for the next session to address (small, non-blocking):
  - One spec/implementation deviation in the path-safety helper (lexical
    vs realpath) — decide whether to amend the spec to match
    implementation, or tighten the helper. Low practical risk.
  - Six minor spec ambiguities resolved by implementation defaults
    (H1-only first_heading, CLAUDE.md inclusion rules, slug hygiene,
    integer/ISO8601 formats, recursive globbing, prefix traversal
    rejection) — capture in spec if locking is desired.
  - `CLAUDE.md` line 32 references `docs/auth.md` which doesn't exist on
    disk. Phase 12 territory; leave for now.
  - One untracked test note
    `docs/notes/2026-05-04-00-02-40-test-note.md` from manual validation.
    User asked to leave it for now.
  - 1 low Dependabot alert raised by GitHub at push time — separate from
    the existing CLI-side alert; review on dashboard.
- Forward-looking: the Phase 4 master spec lists Phase B's six parallel
  workstreams (controllers/views/Stimulus, NoteSyncJob+cron+lock,
  `pito footage` subcommand, GitHub Actions, design refresh, ADR
  addendum + log) — those fan out after Phase A converges.

**References (full paths so Mobile can `read_doc` them):**

- `docs/plans/beta/04-project-workspace/specs/project-workspace.md` —
  master spec for Phase 4.
- `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md` —
  Step 0 sibling spec.
- `docs/plans/beta/04-project-workspace/additions.md` — scope additions.
- `docs/orchestration/playbooks/2026-05-04-mcp-dev-kb-surface.md` — Step 0
  reviewer playbook.
- `docs/mcp.md` — MCP server docs (now includes the Dev KB surface
  section).
- `CLAUDE.md` — root project instructions (Logging convention + MCP Dev KB
  surface sections).
