# Phase 4 — Monolith Migration Spec

> Prerequisite to Phase 4 implementation. Migration runs FIRST; the Project
> Workspace spec at `specs/project-workspace.md` lands AFTER this migration
> succeeds, into the new structure.
>
> Sister spec: `specs/project-workspace.md` (executed after migration).
>
> **Note (2026-05-04 amendment):** This migration spec originally provisioned
> two separate Rust crates: `pito-terminal` (TUI) and `footage-sync` (importer).
> Mid-migration the architecture was simplified to a single `pito` CLI binary at
> `extras/cli/` with subcommands (`pito` for the TUI, `pito footage` for footage
> import, `pito help`, `pito version`). The migration steps below have been
> edited to reflect the consolidated structure.

---

## 1. Goal

Consolidate the four-repo Pito ecosystem (`pito`, `pito-sh`, `pito-website`,
`pito-dev-kb`) and the `pito-project` workspace shell into a single monolith
repository at `~/Dev/pito/`. The split was a multi-developer optimization that
never materialized; for a single-developer workflow it imposes cross-repo
orchestration overhead, four CI configurations, four agent file scopes, and
fragile cross-repo references. Consolidation eliminates all of that, simplifies
agent dispatch, and aligns the on-disk layout with the actual product.

---

## 2. Scope

### In scope

- Move all source code, docs, agent definitions, follow-ups, and memory
  references into the unified `pito` repo at `~/Dev/pito/`.
- Drop the `.git` directories of `pito-dev-kb`, `pito-sh`, `pito-website`, and
  the workspace root `pito-project`. Keep only `pito/.git` (renamed via the
  parent directory rename).
- Rename local directory `~/Dev/pito-project/` → `~/Dev/pito/`.
- Update all eight agent definitions in `.claude-config/agents/` from repo-based
  scope rules to path-scoped rules (root-relative under `~/Dev/pito/`).
- Add one new agent definition for the `extras/website/` lane (`website-impl`).
  The terminal-app agent is renamed (`pito-sh-impl` → `cli-impl`) and absorbs
  the footage-import surface — no separate `footage-sync-impl` agent.
- Rewrite the root `CLAUDE.md` to describe the monolith; absorb the four
  per-repo `CLAUDE.md` files; drop or shrink them to short pointer files.
- Update all internal cross-references in markdown (paths starting with
  `pito-dev-kb/`, `pito-sh/`, `pito-website/`, `pito/`) to the new in-repo
  paths.
- Replace four CI configurations with a single `.github/workflows/ci.yml` using
  path-filtered jobs.
- Add a Cargo workspace at the repo root with a single member: `extras/cli` (the
  unified `pito` CLI binary).
- Land the unified `pito` CLI at `extras/cli/`. The crate's binary is named
  `pito` and exposes the TUI as the default mode plus subcommands
  (`pito footage`, `pito help`, `pito version`, future ones). The footage-import
  flow is a subcommand of this binary, not a separate crate.
- Update `Procfile.dev`, `bin/dev`, and the Rails controller path that builds /
  serves the binary to read from `extras/cli/target/release/pito`.

### Out of scope

- Phase 4 implementation itself (separate spec, runs AFTER migration).
- Subtree-style git history preservation. Strategy is **snapshot, not
  subtree-merge** — see §3.
- Code refactoring beyond paths. No logic changes.
- pito-yt-kb. Already removed from the workspace; nothing to migrate.

---

## 3. Migration strategy — snapshot, not subtree-merge

We do not preserve cross-repo git history into the monolith. Each subproject's
`.git` directory is dropped; the file content is copied into the new layout and
committed as a single (or thematically split) "Consolidate to monolith" commit.
History before the consolidation lives in the now-archived (and soon deleted)
GitHub repos.

Rationale: subtree-merging four repos with overlapping working trees and four
years of independent histories produces a messy single timeline that nobody will
read. The user already has the old repos pushed to GitHub; we keep them
archive-only for a brief grace period and then delete.

The keeper repo is `pito/` — its `.git` directory becomes the monolith's `.git`
directory after the parent rename.

---

## 4. Final layout

```
~/Dev/pito/                           (renamed from ~/Dev/pito-project; single repo)
├── app/                              ← Rails app (preserved verbatim)
├── bin/
├── config/
├── db/
├── docs/
│   ├── architecture.md               ← existing pito/docs/* unchanged
│   ├── design.md
│   ├── mcp.md
│   ├── setup.md
│   ├── auth.md
│   ├── plans/                        ← was pito-dev-kb/plans/
│   │   ├── alpha/
│   │   └── beta/
│   ├── decisions/                    ← was pito-dev-kb/decisions/
│   ├── orchestration/                ← was pito-dev-kb/orchestration/
│   └── conversations/                ← was pito-dev-kb/conversations/
├── extras/
│   ├── cli/                          ← was pito-sh/, now the unified `pito` binary
│   └── website/                      ← was pito-website/
├── lib/                              ← Rails lib only (no Rust crate here)
├── public/
├── spec/
├── vendor/
├── .claude-config/                   ← was pito-dev-kb/.claude-config/
├── .github/
│   └── workflows/
│       └── ci.yml                    ← single workflow (path-filtered)
├── Cargo.toml                        ← workspace listing extras/cli
├── Cargo.lock                        ← workspace lockfile
├── Gemfile / Gemfile.lock
├── Procfile.dev
├── docker-compose.yml
├── Dockerfile
├── CLAUDE.md
├── README.md
├── LICENSE
├── .editorconfig
├── .prettierrc.json
└── .gitignore
```

The local rename is `~/Dev/pito-project/` → `~/Dev/pito/`. Inside the existing
`pito-project/pito/` is the keeper Rails repo whose `.git` survives; all other
`.git` dirs are dropped.

---

## 5. File-by-file move table

Exhaustive. Format: `<source>` → `<destination>`. Grouped by source.

### 5.1 Source: `pito-dev-kb/`

| Source                         | Destination                | Notes                                       |
| ------------------------------ | -------------------------- | ------------------------------------------- |
| `pito-dev-kb/.claude-config/`  | `pito/.claude-config/`     | Entire tree.                                |
| `pito-dev-kb/plans/`           | `pito/docs/plans/`         | Alpha + beta with all phase folders.        |
| `pito-dev-kb/decisions/`       | `pito/docs/decisions/`     | All ADRs.                                   |
| `pito-dev-kb/orchestration/`   | `pito/docs/orchestration/` | Includes `playbooks/`, `scripts/`.          |
| `pito-dev-kb/conversations/`   | `pito/docs/conversations/` | All durable summaries.                      |
| `pito-dev-kb/CLAUDE.md`        | (folded into root)         | Content absorbed into root `CLAUDE.md`.     |
| `pito-dev-kb/README.md`        | (drop)                     | Repo-purpose statement no longer applies.   |
| `pito-dev-kb/LICENSE`          | (drop)                     | LICENSE in pito/ already.                   |
| `pito-dev-kb/.gitignore`       | merge into root            | Reconcile with pito/.gitignore.             |
| `pito-dev-kb/.prettierrc.json` | reconcile                  | Identical to pito's; one canonical version. |
| `pito-dev-kb/.editorconfig`    | reconcile                  | Identical; one canonical version.           |

### 5.2 Source: `pito-sh/`

The legacy `pito-sh` crate lands at `extras/cli/` and is renamed to `pito` (both
the binary name and the crate package). It becomes the single Rust crate in the
workspace and is extended with subcommands (`pito footage`, etc.) under Phase 4.

| Source                     | Destination                    | Notes                                                                                   |
| -------------------------- | ------------------------------ | --------------------------------------------------------------------------------------- |
| `pito-sh/Cargo.toml`       | `pito/extras/cli/Cargo.toml`   | Crate `package` block kept; rename `name` from `pito-sh` to `pito`; binary name `pito`. |
| `pito-sh/Cargo.lock`       | (drop)                         | Workspace lockfile at root replaces it.                                                 |
| `pito-sh/src/`             | `pito/extras/cli/src/`         | Verbatim.                                                                               |
| `pito-sh/tests/`           | `pito/extras/cli/tests/`       | Verbatim.                                                                               |
| `pito-sh/docs/`            | `pito/extras/cli/docs/`        | Crate-local design notes stay with the crate.                                           |
| `pito-sh/.env.example`     | `pito/extras/cli/.env.example` | If present.                                                                             |
| `pito-sh/CLAUDE.md`        | (drop)                         | Folded into root `CLAUDE.md` as a brief subsection.                                     |
| `pito-sh/README.md`        | `pito/extras/cli/README.md`    | Crate-local README is fine; trim cross-repo references.                                 |
| `pito-sh/.gitignore`       | merge into root                | Add Rust artefacts (`target/`, etc.) at root level.                                     |
| `pito-sh/.editorconfig`    | (drop)                         | Root config applies.                                                                    |
| `pito-sh/.prettierrc.json` | (drop)                         | Root config applies.                                                                    |
| `pito-sh/LICENSE`          | (drop)                         | Root LICENSE applies.                                                                   |
| `pito-sh/target/`          | (drop)                         | Build artefact; rebuilt under root `target/`.                                           |
| `pito-sh/.git/`            | (drop)                         | History lost; archived on GitHub.                                                       |

### 5.3 Source: `pito-website/`

| Source                    | Destination                     | Notes                              |
| ------------------------- | ------------------------------- | ---------------------------------- |
| `pito-website/` (content) | `pito/extras/website/`          | Entire tree minus the items below. |
| `pito-website/CLAUDE.md`  | (drop)                          | Folded into root `CLAUDE.md`.      |
| `pito-website/README.md`  | `pito/extras/website/README.md` | Trim cross-repo references.        |
| `pito-website/docs/`      | `pito/extras/website/docs/`     | If present.                        |
| `pito-website/Pito.png`   | `pito/extras/website/Pito.png`  | Brand asset.                       |
| `pito-website/LICENSE`    | (drop)                          |                                    |
| `pito-website/.git/`      | (drop)                          |                                    |

### 5.4 Source: `pito/` (the keeper)

| Source                             | Destination             | Notes                                                                                                                                                                                      |
| ---------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `pito/CLAUDE.md`                   | root `CLAUDE.md`        | Rewritten to describe the monolith; absorbs scoping notes from the four old per-repo files.                                                                                                |
| `pito/.editorconfig`               | root `.editorconfig`    | Becomes the canonical root config.                                                                                                                                                         |
| `pito/.prettierrc.json`            | root `.prettierrc.json` | Becomes the canonical root config.                                                                                                                                                         |
| `pito/Procfile.dev`                | unchanged path          | Update the CLI build entry to point at `extras/cli` (cargo manifest + binary `pito`).                                                                                                      |
| `pito/bin/dev`                     | unchanged path          | Same — point any importer/CLI reference at `extras/cli/`.                                                                                                                                  |
| `pito/app/controllers/footage/...` | unchanged path          | The Rails controller that serves the binary download reads from `extras/cli/target/release/pito`. Phase 4 spec authors that controller; this migration spec only declares the path target. |
| `pito/.gitignore`                  | root `.gitignore`       | Augment with Rust workspace `target/`, `Cargo.lock` rules per crate, Cloudflare Pages dist dir for `extras/website/`, etc.                                                                 |
| Everything else under `pito/`      | unchanged               | App, config, db, spec, lib, bin, vendor, etc. stay where they are. No Rust crate lives under Rails `lib/`.                                                                                 |

The footage-import surface is INTRODUCED by Phase 4 as a subcommand
(`pito footage`) of the unified `pito` binary. Pre-migration there is no
separate Rust crate to move; Phase 4 lands the subcommand directly inside
`extras/cli/src/footage/` post-migration.

### 5.5 Source: workspace root (`pito-project/`)

| Source                          | Destination | Notes                                                                 |
| ------------------------------- | ----------- | --------------------------------------------------------------------- |
| `pito-project/CLAUDE.md`        | (folded)    | Content absorbed into root `CLAUDE.md` as the orchestration block.    |
| `pito-project/.editorconfig`    | reconcile   | Should be identical to `pito/.editorconfig`; pick one and drop other. |
| `pito-project/.prettierrc.json` | reconcile   | Same.                                                                 |
| `pito-project/.gitignore`       | merge       | Workspace-level rules folded into root `.gitignore`.                  |
| `pito-project/.git/`            | (drop)      | Not the keeper.                                                       |
| `pito-project/.claude/`         | reconcile   | If a workspace-level `.claude/` exists, merge into the new root.      |

---

## 6. Cross-reference rewrites

After files move, every markdown file under `docs/` must have its internal
references rewritten. Rules:

- `pito-dev-kb/plans/` → `docs/plans/`
- `pito-dev-kb/decisions/` → `docs/decisions/`
- `pito-dev-kb/orchestration/` → `docs/orchestration/`
- `pito-dev-kb/conversations/` → `docs/conversations/`
- `pito-dev-kb/.claude-config/` → `.claude-config/`
- `pito-dev-kb/CLAUDE.md` → `CLAUDE.md`
- `pito-sh/src/` → `extras/cli/src/`
- `pito-sh/Cargo.toml` → `extras/cli/Cargo.toml`
- `pito-sh/docs/` → `extras/cli/docs/`
- `pito-sh/CLAUDE.md` → `CLAUDE.md` (now the same file)
- `pito-website/` → `extras/website/`
- `pito/app/` / `pito/config/` / `pito/spec/` / `pito/db/` / `pito/lib/` /
  `pito/docs/` → drop the `pito/` prefix; these become root-relative.
- `~/Dev/pito-project/` → `~/Dev/pito/`

The implementer runs a global grep before committing and resolves every match. A
targeted Bash grep against the new tree, per pattern above, must return zero
hits except in this migration spec itself (which legitimately documents the old
paths for the historical record).

---

## 7. Agent definition rewrites

The eight existing agent definitions move to `pito/.claude-config/agents/` and
have their scope rules rewritten from repo-based to path-based, root-relative
under `~/Dev/pito/`. The terminal-app agent is renamed (`pito-sh-impl` →
`cli-impl`) and absorbs the footage-import surface — there is no separate
`footage-sync-impl` agent. One new agent (`website-impl`) is added. The
post-migration agent count is nine.

The "Scope rule" block in every agent is updated: replace
`~/Dev/pito-project/` with `~/Dev/pito/`. The "Docker
safety addendum" stays exactly as-is on every agent that already has one — it is
path-independent.

The "Role discipline" block stays. Each agent's path scope must explicitly note:
"If a task expects work outside this scope, STOP and report. The architect
dispatches the correct agent."

### 7.1 architect-spec

- Old scope: writes specs into `pito-dev-kb/plans/<phase>/specs/`.
- New scope: writes specs into `~/Dev/pito/docs/plans/<phase>/specs/`.
- Allowed write paths: `~/Dev/pito/docs/plans/`, `~/Dev/pito/docs/decisions/`
  (occasionally for new ADRs, on architect request).
- Allowed read paths: full repo (read-only is fine).
- Forbidden write paths: every other path under `~/Dev/pito/`.
- Cross-boundary report: any task asking for code, agent edits, MCP tools, Rust
  crates, ERB views, or root config → STOP and report.

### 7.2 pito-rails

- Old scope: writes Rails code in the `pito` repo.
- New scope: `~/Dev/pito/app/`, `~/Dev/pito/config/`, `~/Dev/pito/db/`,
  `~/Dev/pito/spec/`, `~/Dev/pito/lib/` (Rails lib only — explicitly NOT
  `extras/`), `~/Dev/pito/bin/`, `~/Dev/pito/Gemfile`,
  `~/Dev/pito/Gemfile.lock`, `~/Dev/pito/Procfile.dev`,
  `~/Dev/pito/docker-compose.yml`, `~/Dev/pito/Dockerfile`,
  `~/Dev/pito/Rakefile`.
- Forbidden write paths: `~/Dev/pito/extras/` (entirely), `~/Dev/pito/docs/`,
  `~/Dev/pito/.claude-config/`, `~/Dev/pito/.github/workflows/` (single
  canonical workflow lives here; edits go through architect).
- Cross-boundary report: tasks touching MCP tool definitions (pito-mcp), `pito`
  CLI code (cli-impl), or website content (website-impl) → STOP and report.

### 7.3 pito-mcp

- Old scope: pito repo MCP tools.
- New scope: `~/Dev/pito/app/mcp/`, `~/Dev/pito/spec/mcp/`,
  `~/Dev/pito/lib/mcp/` (thin glue only).
- Forbidden write paths: every other path under `~/Dev/pito/app/`,
  `~/Dev/pito/extras/`, `~/Dev/pito/docs/`.
- Cross-boundary report: missing service method implies a pito-rails task → STOP
  and report; the spec must be amended first.

### 7.4 cli-impl (renamed from pito-sh-impl)

- Old scope: pito-sh repo.
- New scope: `~/Dev/pito/extras/cli/` — the unified `pito` CLI binary. Covers
  the default TUI mode and every subcommand (`pito footage`, `pito help`,
  `pito version`, future ones).
- Allowed: anything under that path. Plus root `Cargo.toml` / `Cargo.lock` only
  when the workspace member list itself changes (rare).
- Forbidden write paths: anywhere outside `~/Dev/pito/extras/cli/` except the
  narrow `Cargo.toml` exception above.
- Cross-boundary report: changes to Rails endpoints, MCP tools, the website, or
  docs → STOP and report.
- Rename rationale: the agent describes a lane, not a repo; the lane is the
  unified `pito` CLI. Phase 4 extends it with the `pito footage` subcommand
  without spinning up a separate agent.

### 7.5 website-impl (NEW)

- New scope: `~/Dev/pito/extras/website/` only.
- Allowed tools: Bash, Read, Edit, Write, Grep, Glob.
- Forbidden: anywhere outside `extras/website/`.
- Cross-boundary report: any change to Cloudflare deployment config that touches
  CI workflows → STOP and report.
- Captured for future use; pito-website is currently dormant.

### 7.6 reviewer

- Old scope: pito + pito-sh, read full repo, write only playbooks under
  `pito-dev-kb/orchestration/playbooks/`.
- New scope: read across the whole monolith (`~/Dev/pito/` minus `target/`,
  `node_modules/`, `tmp/`, `log/`). Write only
  `~/Dev/pito/docs/orchestration/playbooks/`.
- Forbidden: any source-code or docs edit. Fix-forward routes through
  implementation agents on architect's instruction.
- The pipeline runs adapt: in addition to RSpec / Brakeman / bundler-audit
  (Rails), runs `cargo fmt --check`, `cargo clippy -- -D warnings`, and
  `cargo test` on the single `extras/cli` crate, plus
  `prettier --check '**/*.md'` from the repo root.

### 7.7 security-auditor

- Old scope: same repos.
- New scope: read across the whole monolith. Write only
  `~/Dev/pito/docs/orchestration/playbooks/security-*.md`.
- Pipeline unchanged in shape; the diff range (`git diff main...HEAD`) now spans
  all of monolith.

### 7.8 docs-keeper

- Old scope: pito docs + pito-dev-kb phase folders + sibling repo CLAUDE.md.
- New scope: `~/Dev/pito/docs/`, `~/Dev/pito/.claude-config/`, root `CLAUDE.md`,
  `~/Dev/pito/extras/<crate>/README.md` when an implementation agent reports a
  docs gap there.
- Forbidden write paths: source code anywhere, plan files except ticking
  checkboxes (with the existing `additions.md` / `dropped.md` workflow).
- The "sibling repo" language drops; everything is in-repo now.

### 7.9 audit-state

- Old scope: read-only across all four repos.
- New scope: read-only across `~/Dev/pito/`. Excluded directories: `target/`,
  `node_modules/`, `tmp/`, `log/`, `.git/`, `vendor/bundle/`.
- Output unchanged; phase-by-phase verdict against `docs/plans/beta/`.

---

## 8. Root `CLAUDE.md` rewrite

The new root `CLAUDE.md` is the single source of truth. It absorbs scoping notes
from the four old per-repo `CLAUDE.md` files and the workspace-root `CLAUDE.md`.
Sections, in order:

1. **Project overview** — one paragraph: Pito is a single-tenant Rails 8 app for
   tracking and managing YouTube channels, with a unified Rust `pito` CLI binary
   (TUI plus subcommands like `pito footage`) and a static landing page, all in
   one repo.
2. **Repository layout** — the directory tree from §4.
3. **How to work in this monolith** — a pointer per top-level area:
   - Rails app at the repo root (Ruby on Rails 8.1 + Hotwire, Postgres 17,
     Sidekiq, RSpec) — see `docs/architecture.md`, `docs/setup.md`,
     `docs/mcp.md`, `docs/design.md`, `docs/auth.md`.
   - Unified `pito` CLI at `extras/cli/` (Rust + Ratatui). Default mode is the
     TUI client; subcommands include `pito footage` (footage import),
     `pito help`, `pito version`, and future ones. Style: `claude` binary.
   - Website at `extras/website/` (Cloudflare Pages target).
   - Planning and orchestration docs at `docs/plans/`, `docs/decisions/`,
     `docs/orchestration/`, `docs/conversations/`.
4. **Workflow rules** — commit directly to `main`, no branches, no PRs in early
   stages; one-line meaningful commits, no Co-Authored-By; markdown wraps at 80
   chars (`prettier --write '**/*.md'`); no JS dialogs (action confirmation page
   framework only); bulk-as-foundation; user validates before commit.
5. **Configuration strategy** — `.env.development` / `.env.test` for
   infrastructure connection info only; `rails credentials:edit` for secrets;
   `config/master.key` on disk and gitignored; CI uses its own env vars in
   `.github/workflows/ci.yml`. Carried verbatim from the old `pito/CLAUDE.md`.
6. **Visual style** — design system pointer to `docs/design.md`; key rules
   (monospace 13px, white bg, bracketed link convention, red is destructive
   only). Carried from the old `pito/CLAUDE.md`.
7. **Architecture notes** — one paragraph each: Tenant + User singletons,
   Channel model rules, ChannelSync placeholder, Workspace model. Carried from
   the old `pito/CLAUDE.md`.
8. **Agent orchestration + role discipline** — synthesized from the old
   workspace-root `CLAUDE.md` and `docs/orchestration/agents.md`. Covers the
   architect's role (plan / delegate / review / iterate / commit), the nine
   subagents in `.claude-config/agents/`, the role-discipline / STOP-and-report
   rule.
9. **Follow-ups queued** — cross-link to `docs/orchestration/follow-ups.md`.
   Lists the four open items (Channel Revamp post-commit cleanup, Rails-app
   keyboard shortcuts, `pito` CLI screen layout parity, `pito` CLI Dependabot
   alert #1).
10. **Glossary** — Pito, Alpha, Beta, Theta, Tenant, Channel, Lane 1 / 2a / 2b,
    MCP.

The four old per-repo `CLAUDE.md` files are dropped after their content is
absorbed. Optionally, very short pointer files may exist as
`extras/cli/CLAUDE.md` and `extras/website/CLAUDE.md` — each five lines or
fewer, of the form "see root `CLAUDE.md` for project rules; this folder is the
unified `pito` CLI binary / Cloudflare Pages target." Default to NOT creating
these unless an agent's path scope is improved by their presence.

---

## 9. Memory file updates

Architect's persistent memory at
`~/.claude/projects/-home-catalin-Dev-pito-project/memory/` needs path renames
anywhere it references `~/Dev/pito-project/<subdir>` paths.

### 9.1 In-file rewrites

- `project_overview.md` — describes the layout. Rewrite to reflect the monolith:
  one repo at `~/Dev/pito/`, Rails at root, the unified `pito` Rust CLI at
  `extras/cli/`, and a static landing page at `extras/website/`. Planning under
  `docs/plans/`.
- `MEMORY.md` — index file. Update the bullet pointing at `project_overview.md`.
  Re-scan every other line for path references and flag for rewrite.
- Each `feedback_*.md` and `project_*.md` file — surface every path reference
  matching `~/Dev/pito-project/`, `pito-dev-kb/`, `pito-sh/`, `pito-website/`,
  or `pito/` (when used as a subdirectory prefix). The implementer enumerates
  them in a list under the migration log entry and the architect rewrites each.

### 9.2 Memory directory rename

The `~/.claude/projects/-home-catalin-Dev-pito-project/` directory itself
encodes the OLD path. After renaming `~/Dev/pito-project/` to `~/Dev/pito/`,
Claude Code will look for `~/.claude/projects/-home-catalin-Dev-pito/`.

User-side step (executed manually by the user, not by an agent):

```bash
mv ~/.claude/projects/-home-catalin-Dev-pito-project \
   ~/.claude/projects/-home-catalin-Dev-pito
```

Alternatively, the user can start fresh memory under the new path (slower
ramp-up but clean slate). The migration spec does not prescribe which; the user
decides at execution time.

---

## 10. CI workflow

Single `.github/workflows/ci.yml` replaces four. Path-filtered jobs using
`dorny/paths-filter@v3`. Sketch (implementer fills in details):

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      rails: ${{ steps.filter.outputs.rails }}
      cli: ${{ steps.filter.outputs.cli }}
      website: ${{ steps.filter.outputs.website }}
      docs: ${{ steps.filter.outputs.docs }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            rails:
              - 'app/**'
              - 'config/**'
              - 'db/**'
              - 'lib/**'
              - 'spec/**'
              - 'Gemfile*'
              - 'bin/**'
              - 'Procfile.dev'
              - 'docker-compose.yml'
              - 'Dockerfile'
            cli:
              - 'extras/cli/**'
              - 'Cargo.toml'
              - 'Cargo.lock'
            website:
              - 'extras/website/**'
            docs:
              - 'docs/**'
              - '**/*.md'

  rails:
    needs: changes
    if: needs.changes.outputs.rails == 'true'
    # Postgres + Redis services, bundle install, db:setup, rspec,
    # brakeman, bundler-audit.

  cli:
    needs: changes
    if: needs.changes.outputs.cli == 'true'
    # cargo fmt --check + cargo clippy -- -D warnings + cargo test
    # + cargo build --release in extras/cli (the unified `pito` binary).

  cli-release:
    needs: cli
    if: github.ref == 'refs/heads/main' && needs.changes.outputs.cli == 'true'
    # tag-driven release with the `pito` binary attached, tagged
    # `pito-<short-sha>` (per project-workspace.md §12.1).

  docs-lint:
    needs: changes
    if: needs.changes.outputs.docs == 'true'
    # prettier --check '**/*.md'

  website:
    needs: changes
    if: needs.changes.outputs.website == 'true'
    # Cloudflare Pages deploy hook (when pito-website work resumes).
```

GitHub Actions secrets stay associated with the `pito` repo (the keeper).
`GITHUB_TOKEN` is auto-provided. No new secrets required by the migration
itself; Phase 4 will add `VOYAGE_API_KEY` and a `GITHUB_PAT` for the `pito` CLI
release-asset download path, but those belong to the Phase 4 spec.

---

## 11. Cargo workspace setup

Top-level `~/Dev/pito/Cargo.toml`:

```toml
[workspace]
members = ["extras/cli"]
resolver = "3"

[workspace.dependencies]
# shared deps go here if/when a second crate joins the workspace
```

Use `resolver = "3"` if the crate is on Rust 2024 edition. If it is on 2021, use
`resolver = "2"`. Implementer reads `extras/cli/Cargo.toml [package] edition`
and picks the matching resolver. The workspace ships with a single member today;
the resolver line stays workspace-level for forward compatibility.

The member crate keeps its own `Cargo.toml` `[package]`, `[dependencies]`, and
`[[bin]]` sections (binary `name = "pito"`). Workspace-level `Cargo.lock` is
single, at the repo root.

Add to `~/Dev/pito/.gitignore`:

```
# Rust workspace build artefacts
/target/

# Per-crate target dirs (defensive — workspace target/ is at root)
extras/*/target/
```

---

## 12. Migration steps (execution order)

1. **Backup**. User confirms all four subprojects are pushed to GitHub on their
   default branches with no uncommitted changes:
   `cd ~/Dev/pito-project/pito && git status` (and likewise for `pito-sh`,
   `pito-website`, `pito-dev-kb`, and the workspace root).
2. **Stop dev environment**. `bin/dev` down. Cloudflared tunnel down. Sidekiq
   down. `docker compose down` (without `-v`).
3. **Architect dispatches subagents** to perform the migration in-place. The
   migration is broken into N parallel migration agents, each owning a slice of
   the move table:
   - Agent A (`migration: pito-dev-kb content`): moves `pito-dev-kb/` content
     into `pito/docs/` and `.claude-config/`.
   - Agent B (`migration: pito-sh`): moves `pito-sh/` content into
     `pito/extras/cli/` and renames the binary/package to `pito`.
   - Agent C (`migration: pito-website`): moves `pito-website/` content into
     `pito/extras/website/`.
   - Agent D (`migration: agent definitions`): rewrites all eight existing agent
     files for path-based scope, renames `pito-sh-impl` to `cli-impl`, and
     authors the one new agent (`website-impl`). Final count: nine agents.
   - Agent E (`migration: CI + Cargo workspace`): writes
     `.github/workflows/ci.yml` and root `Cargo.toml` (single member,
     `extras/cli`); updates `.gitignore`.
   - Agent F (`migration: root CLAUDE.md`): writes the new root `CLAUDE.md` from
     the §8 spec.
   - Agent G (`migration: cross-reference rewrite`): runs the §6 rewrite pass
     across the migrated tree.
   - Agent H (`migration: memory file rewrite`): rewrites architect memory
     references per §9.1; does NOT rename the memory directory (user step).
4. **Drop subproject `.git` directories**. Manual step the architect coordinates
   after every agent reports done:
   ```
   rm -rf ~/Dev/pito-project/pito-dev-kb/.git
   rm -rf ~/Dev/pito-project/pito-sh/.git
   rm -rf ~/Dev/pito-project/pito-website/.git
   rm -rf ~/Dev/pito-project/.git
   ```
   Only `~/Dev/pito-project/pito/.git` survives.
5. **Move content into `pito/`**. Agents may have written into a staging tree
   under `pito-project/pito/...`; if not, a final sweep `cp -r` runs here.
   Verify the new directories exist with the expected content.
6. **Drop other subproject directories**.
   `rm -rf ~/Dev/pito-project/{pito-dev-kb,pito-sh,pito-website}` after
   confirming their content is now under `pito-project/pito/`.
7. **Rename**. `mv ~/Dev/pito-project/pito ~/Dev/pito` (this also moves the
   surviving `.git` dir). Then `rmdir ~/Dev/pito-project` (now empty).
8. **Update memory dir**. User runs the rename described in §9.2.
9. **`cd ~/Dev/pito`**. Verify structure visually with `ls` and `tree -L 2`.
10. **Reviewer agent runs gates**. RSpec, Brakeman, bundler-audit (Rails side);
    `cargo test --workspace` (Rust side); `cargo build --release -p pito` (the
    unified CLI binary); `prettier --check '**/*.md'`; agent definition
    spot-check.
11. **User validates manually**. `bin/dev` boots and Rails comes up at
    `https://app.pitomd.com` via Cloudflared. `cargo run -p pito` (no args)
    launches the TUI client. `cargo run -p pito -- version` and
    `cargo run -p pito -- help` return the expected output. Phase 4 lands
    `pito footage` afterwards.
12. **User commits**. A single big "Consolidate to monolith" commit, OR a
    thematic split (code, docs, agents, CI). User's choice. Push to `main` of
    `gmrdad82/pito`.
13. **User deletes old GitHub repos**. After the consolidation commit pushes
    successfully and the user has reviewed the live monolith on GitHub:
    - Delete `gmrdad82/pito-dev-kb`.
    - Delete `gmrdad82/pito-sh`.
    - Delete `gmrdad82/pito-website`.
    - Delete `gmrdad82/pito-project`.
    - Keep `gmrdad82/pito` (the monolith).
14. **Post-migration cleanup**. Update any nvim sessions, alias scripts, shell
    history, shortcuts, or `~/.zshrc` / `~/.bashrc` paths that referenced
    `~/Dev/pito-project/`. The user is responsible for these — agents do not
    touch user dotfiles.

---

## 13. Risks

- **Memory path mismatch.** Claude Code's per-project memory dir was named after
  the old workspace path. Without the rename in §9.2 the next session starts
  with empty memory.
- **Cargo workspace edition / lock conflicts.** Verify the crate's
  `[package] edition` before writing the `resolver` line; run
  `cargo build --workspace` early in step 10 and resolve any dep version
  conflicts.
- **Crate package rename.** The `pito-sh` package is renamed to `pito` at
  migration time so the binary name matches the lane (`pito`, with
  `pito footage` subcommand etc.). Rust users referencing the crate by name
  update accordingly.
- **Rails autoloader.** Verify Zeitwerk doesn't sweep `extras/`. Apply
  `Rails.application.config.autoload_paths -= [Rails.root.join("extras").to_s]`
  if reviewer flags an issue.
- **CI secrets.** Stay associated with `gmrdad82/pito`. No new secrets required
  by the migration itself.
- **Branch protection.** If `gmrdad82/pito` enforces branch protection on
  `main`, temporarily relax for the migration push; restore after.
- **Cloudflared tunnel config** may reference old paths. User searches
  `~/.cloudflared/` and resolves manually (agents don't touch dotfiles).
- **bin/dev / Procfile.dev** reference `extras/cli` even though the
  `pito footage` subcommand is empty pre-Phase 4. The reference is a forward
  declaration; Phase 4 implementation fills in the subcommand.

---

## 14. Acceptance criteria

After migration:

- [ ] `~/Dev/pito/` exists and is the only Pito-related directory under
      `~/Dev/`. `~/Dev/pito-project/` does not exist.
- [ ] `~/Dev/pito/.git` exists; `find ~/Dev/pito -name .git -type d` returns
      exactly one path.
- [ ] `extras/cli/` (the unified `pito` binary, ported from pito-sh) and
      `extras/website/` exist under `~/Dev/pito/`.
- [ ] `docs/plans/`, `docs/decisions/`, `docs/orchestration/`,
      `docs/conversations/` exist under `~/Dev/pito/`.
- [ ] `.claude-config/agents/*.md` lists nine files: the eight originals (with
      `pito-sh-impl` renamed to `cli-impl`) plus the one new `website-impl`.
      Every file's "Scope rule" points at `~/Dev/pito/`.
- [ ] Root `CLAUDE.md` describes the monolith per §8.
- [ ] No file under `~/Dev/pito/` (except this migration spec) references
      `pito-dev-kb/`, `pito-sh/`, `pito-website/`, or `~/Dev/pito-project/` as a
      path. Verified by grep.
- [ ] Single `.github/workflows/ci.yml` with path filtering. Old per-repo
      workflows deleted from their original repos (which are themselves deleted
      in step 13).
- [ ] `~/Dev/pito/Cargo.toml` workspace exists with a single member
      `extras/cli`. `cargo build -p pito` produces a `pito` binary at
      `target/release/pito`.
- [ ] `bin/dev` boots all services (Rails, Sidekiq, Tailwind, Cloudflared).
- [ ] `cargo test --workspace` passes (the `extras/cli` crate carries tests
      inherited from pito-sh; the `pito footage` subcommand tests land with
      Phase 4).
- [ ] `bundle exec rspec` passes on the Rails side.
- [ ] `bundle exec brakeman --quiet` clean.
- [ ] `prettier --check '**/*.md'` clean.
- [ ] User can navigate to `https://app.pitomd.com` via the Cloudflared tunnel.
- [ ] Architect memory references rewritten per §9.1; memory directory renamed
      per §9.2.
- [ ] Old GitHub repos (`pito-dev-kb`, `pito-sh`, `pito-website`,
      `pito-project`) deleted; `gmrdad82/pito` is the only remaining repo.

---

## 15. What changes for downstream work

- **Phase 4 implementation** dispatches agents into the new structure. The Phase
  4 spec moves with the rest of `pito-dev-kb/plans/` and lives at
  `~/Dev/pito/docs/plans/beta/04-project-workspace/specs/project-workspace.md`
  after migration. That spec becomes the active spec for Phase 4 work.
- **All four follow-ups** in `docs/orchestration/follow-ups.md` carry over
  unchanged in content; only their internal path references update per §6. In
  particular, the "Pito-sh Dependabot alert #1" follow-up now refers to the
  dormant `gmrdad82/pito-sh` GitHub repo before it gets deleted; once deleted,
  the Dependabot alert becomes moot and the follow-up can move to Done with
  rationale "repo deleted as part of monolith migration; alert no longer
  applies."
- **Memory files** carry over. Reference paths under `~/Dev/pito/`.
- **Agent dispatch language** changes from "repo: scope" (e.g.,
  `pito-sh: API client`) to "lane: scope" (e.g., `cli: API client`). The
  architect's invocation pattern in `CLAUDE.md` reflects this rename.
- **Future MCP `dev:*` tool surface** that may eventually expose the dev-kb to
  MCP callers points at `docs/` paths, not `pito-dev-kb/` paths.

---

## 16. Open questions

1. **Crate package rename** — resolved at migration time: rename `pito-sh` to
   `pito` so the binary name matches the lane (`pito`, with subcommands
   `pito footage`, `pito help`, `pito version`).
2. **Single commit vs. thematic split** — implementer/user preference. Default
   is single "Consolidate to monolith" commit for simplicity.
3. **`extras/cli/CLAUDE.md` pointer file** — create a five-line pointer to the
   root `CLAUDE.md`, or leave the directory without a `CLAUDE.md` and rely on
   path-scoped agent rules? Default: no pointer file (path scope is already
   explicit in agent definitions).
4. **Branch protection on `main`** — confirm with the user whether
   `gmrdad82/pito` currently enforces branch protection that would block a
   direct push of the consolidation commit. If yes, temporarily relax for the
   migration push; restore after.
