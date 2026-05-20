# Subagent Catalog

The architect (the orchestrating Claude session) never writes code or markdown
directly. All implementation, review, and documentation work is delegated to the
nine subagents catalogued below.

Each agent is invoked with a focused brief, operates inside a defined repo and
file scope, and returns its output for the architect to compose into the next
step. No subagent commits or pushes without explicit architect approval, and the
architect itself only commits after the user has tested and validated.

---

## Role discipline

Every actor in this orchestration system operates strictly within its declared
role.

- **Architect (parent Claude session):** plans, dispatches subagents, reviews
  outputs, commits + pushes after the user validates. Does NOT write code or
  edit project markdown directly. The architect's writes are limited to personal
  memory under `~/.claude/projects/.../memory/` and Git operations.
- **Subagents:** each is defined for a specific role with declared inputs,
  outputs, file scope, and forbidden actions. They do not cross into other
  agents' work even when it would be convenient.
- **STOP-and-report rule:** when an actor's task expects output outside its
  role, the actor stops and reports. The architect then dispatches the correct
  agent. Silent scope expansion is treated as a process failure.

This discipline keeps outputs reviewable, predictable, and free of cross-agent
collisions. It also makes responsibility unambiguous: when something is wrong,
the failing role is identifiable.

Every implementation agent (rails-impl, website-impl, future ones) must honor
**"ViewComponents are kings"** per CLAUDE.md — every visible HTML element wraps
in a ViewComponent (Rails) or `.astro` component (website), even on first use.
No raw inline HTML in templates with classes/styling/variants. This also means:
every ViewComponent dispatch produces both the component files AND the matching
`spec/components/<path>/<name>_component_spec.rb`. Specs are not deferred for
VCs — they are part of the deliverable.

---

## Canonical terminology

All agents use the 5 locked terms — **panel** (not pane), **screen** (not page),
**dialog** (not modal), **action** (not link / url / button), **hint** (not text
/ caption). Canonical source: `CLAUDE.md` § Terminology (canonical) and
`docs/design.md` § Terminology. Dispatch prompts and agent outputs that drift to
the legacy terms are bugs to fix.

---

## Project-scoped agent stubs

Standing project conventions live in `docs/agents/*.md` so dispatch prompts
don't re-paste them. Agents read the stub for their role once. Cross-cutting
stubs (e.g. `docs/agents/testing.md` — suite-run commands, the 8-process
parallelism cap, and the known baseline-failure list) are read by every agent
that runs the RSpec suite, implementation and verification alike.

---

## architect-spec

**Role.** Reads `docs/plans/beta/beta.md`, the active phase plan, and recent log
entries; produces a feature spec the implementation agents can execute against.
Writes markdown only — no code.

**Scope.** The monolith's `docs/` tree (read across all phases; write only
inside the active phase folder and `docs/orchestration/`).

**File scope.**

- Read: `docs/plans/beta/beta.md`, `docs/plans/beta/<phase>/*.md`,
  `docs/orchestration/**`, `docs/decisions/**`, `docs/conversations/**`.
- Write: `docs/plans/beta/<phase>/spec-<feature-slug>.md`.

**Allowed tools.** Read, Grep, Glob, Write.

**Forbidden actions.** No Bash. No Edit on existing specs without architect
approval. No commit, no push, no work in any other repo.

**Output format.** A single markdown file with the sections: Scope, Files
Touched (Lane 1), JSON / ActionCable Surface, Lane 2 Scope (and skips),
Acceptance Criteria, Manual Test Recipe, Open Questions.

**Example invocation context.** "Architect-spec: produce the spec for phase 11's
video-workflow feature. Read beta.md sections 11.x and the phase log. Capture
which Lane 2 surfaces skip and why."

---

## rails-impl

**Role.** Implements Lane 1 features in the `pito` repo: ActiveRecord models,
controllers, ERB views, Stimulus controllers, JSON endpoints, ActionCable
channels, RSpec specs, and migrations. Works directly on `main` — no branch, no
worktree, no PR.

**Repo scope.** `pito` (on `main`).

**File scope.**

- `app/**`, `config/**`, `db/migrate/**`, `spec/**`, `lib/**`, `Gemfile`,
  `Gemfile.lock`.
- Must not touch `docs/**` (that belongs to docs-keeper) and must not touch the
  MCP tool definitions (those belong to mcp-impl).

**Allowed tools.** Bash, Read, Edit, Write, Grep, Glob.

**Forbidden actions.** No commit and no push — the architect commits directly to
`main` after the user validates. No edits to other repos.

**Output format.** A unified diff summary plus a short narrative of decisions
made, surprises encountered, and any tests still red. The working tree is left
in place on `main` for the architect to inspect.

**Example invocation context.** "Rails-impl: on `main` in the pito repo,
implement the spec at
`docs/plans/beta/11-video-workflow-features/spec-video-pipeline.md`. RSpec must
be green. Do not commit."

---

## mcp-impl

**Role.** Adds MCP tool surfaces inside the `pito` repo for a Lane-1 feature.
Defines tool schemas, wires them to the existing services, writes RSpec
coverage. Lane 2b work. Works directly on `main` — no branch, no worktree, no
PR.

**Repo scope.** `pito` (on `main`).

**File scope.**

- `app/mcp/**` (or wherever the MCP server lives in the Rails app),
  `spec/mcp/**`, and any thin glue under `lib/mcp/**`.
- Must not touch ERB views, Stimulus controllers, or HTTP controllers.

**Allowed tools.** Bash, Read, Edit, Write, Grep, Glob.

**Forbidden actions.** No commit and no push — the architect commits directly to
`main` after the user validates. No changes to Lane 1 surfaces; if the MCP work
reveals a missing service method, file it back to the architect rather than
patching rails-impl territory.

**Output format.** Diff summary plus a list of new MCP tool names with short
descriptions, schemas, and the RSpec files covering them.

**Example invocation context.** "Mcp-impl: expose `list_videos`, `get_video`,
and `update_video` as MCP tools mirroring the JSON endpoints from
spec-video-pipeline. Skip uploads per ADR 0001."

---

## cli-impl

**Role.** Implements the Lane 2a `pito` CLI binary at `extras/cli/` (Rust +
Ratatui for the default TUI, `reqwest` for the API client, the existing
auth/session flow for credentials, plus subcommands such as `pito footage` for
footage import). Skips browser-only flows. Works directly on `main` — no branch,
no worktree, no PR.

**Repo scope.** `pito` (on `main`).

**File scope.**

- `extras/cli/src/**`, `extras/cli/Cargo.toml`, `extras/cli/tests/**`, and the
  workspace `Cargo.lock` at the repo root.

**Allowed tools.** Bash, Read, Edit, Write, Grep, Glob.

**Forbidden actions.** No commit and no push — the architect commits directly to
`main` after the user validates. No work outside `extras/cli/` (Rails app, docs,
and website each have their own agents). Do not implement features marked as
Lane-2a-skipped in the spec.

**Output format.** Diff summary, screenshots/ASCII captures of the new TUI
screens (or subcommand transcripts) where applicable, and a list of API
endpoints consumed.

**Example invocation context.** "Cli-impl: on `main` in the pito repo, mirror
the video list/detail screens from the Rails app inside `extras/cli/`. Use the
JSON endpoints listed in the spec. Skip the upload screen — server has no upload
endpoint."

---

## website-impl

**Role.** Implements the Cloudflare Pages landing page at `extras/website/`.
Static HTML/CSS/JS only — no Rails or Rust dependencies. Works directly on
`main` — no branch, no worktree, no PR.

**Repo scope.** `pito` (on `main`).

**File scope.**

- `extras/website/**` only.

**Allowed tools.** Bash, Read, Edit, Write, Grep, Glob.

**Forbidden actions.** No commit and no push — the architect commits directly to
`main` after the user validates. No edits outside `extras/website/`.

**Output format.** Diff summary plus a short narrative of layout / copy
decisions and any new assets added.

**Example invocation context.** "Website-impl: on `main` in the pito repo,
update `extras/website/index.html` to include the new beta-program copy from the
spec."

---

## reviewer

**Role.** Runs the standard review pipeline against the working tree on `main`
left by an implementation agent and produces the manual test playbook the user
will follow before the architect commits. Combines tooling: `/code-review`,
`/simplify`, RSpec, Brakeman, bundler-audit, and a design-alignment check
against `pito/docs/design.md`.

**Repo scope.** Whichever repo the implementation agent worked in (on `main`,
read + targeted edits for fixes only on architect's instruction).

**File scope.**

- Read: full repo.
- Write: only the playbook file at
  `docs/orchestration/playbooks/<YYYY-MM-DD>-<feature-slug>.md`. Code edits are
  out of scope unless the architect explicitly delegates a fix back to an
  implementation agent.

**Allowed tools.** Bash, Read, Grep, Glob, Write.

**Forbidden actions.** No Edit on source files (route fixes back through
implementation agents). No commit, no push.

**Output format.** A review report (issues found, severity, suggested fix owner)
plus the manual test playbook markdown file.

**Example invocation context.** "Reviewer: on `main` in the pito repo after the
latest pito-rails session. Run the full pipeline. Produce playbook
`2026-05-01-video-workflow.md`."

---

## security-auditor

**Role.** A standalone, deeper security pass independent of the reviewer. Runs
`/security-review` against the diff before each commit. Specifically looks at
authn/authz, mass-assignment, IDOR, SSRF, secrets handling, and the MCP tool
surface (which can be driven by an untrusted LLM caller).

**Repo scope.** Whichever repo is about to receive a commit.

**File scope.**

- Read: full repo.
- Write: a security report in the architect's chat output; no file writes.

**Allowed tools.** Bash, Read, Grep, Glob.

**Forbidden actions.** No Edit, no Write, no commit, no push. Findings flow back
to implementation agents via the architect.

**Output format.** A structured report with sections: Critical, High, Medium,
Low, Informational. Each finding includes file path, line range, description,
and remediation.

**Example invocation context.** "Security-auditor: pre-commit pass on the
pending changes on `main` in the pito repo. Pay attention to the new MCP tools
and the JSON endpoints they expose."

---

## docs-keeper

**Role.** Keeps documentation in sync with code that has just landed on `main`.
Updates the canonical docs in the `pito` repo and the phase logs in the dev
knowledge base.

**Scope.** The monolith's `docs/` tree only (product docs and phase folders).

**File scope.**

- `docs/architecture.md`, `docs/mcp.md`, `docs/setup.md`, `docs/design.md`,
  `docs/auth.md`.
- `docs/plans/beta/<phase>/log.md`, `docs/plans/beta/<phase>/additions.md`,
  `docs/plans/beta/<phase>/dropped.md`.

**Allowed tools.** Read, Edit, Write, Grep, Glob.

**Forbidden actions.** No source-code edits. No commit, no push. No edits
outside the listed docs and phase folders.

**Output format.** Diff summaries per file plus a one-paragraph changelog the
architect can use as the commit message when landing the docs on `main`.

**Example invocation context.** "Docs-keeper: phase 11 just landed on `main`.
Update architecture.md (new video service), mcp.md (new tools), and append to
`plans/beta/11-video-workflow-features/log.md`."

---

## audit-state

**Role.** Read-only inspection of the actual repo state versus the master plan.
Produces gap reports answering: which phases of `beta.md` are complete,
partially complete, or untouched; which Lane 2 surfaces are missing for
already-shipped Lane 1 features; which docs are stale.

**Scope.** The monolith — Rails app at the root, `extras/cli/`,
`extras/website/`, and `docs/` — all read-only.

**File scope.**

- Read: full filesystem under `~/Dev/pito/`.
- Write: nothing. Output is delivered as a chat report only.

**Allowed tools.** Bash, Read, Grep, Glob.

**Forbidden actions.** No Edit, no Write, no commit, no push, no mutation of any
kind.

**Output format.** A structured gap report: phase-by-phase status table, list of
stale docs, list of Lane 2 deltas (per feature: Lane 1 present, Lane 2a
present/skipped/missing, Lane 2b present/skipped/missing).

**Example invocation context.** "Audit-state: full ecosystem pass. I want to
know what's missing before we open phase 12."
