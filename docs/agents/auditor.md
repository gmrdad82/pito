# pito-auditor — project-specific extensions

Project-scoped overrides for the audit-state agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/auditor.md`. Read project-wide rules in
`/home/catalin/Dev/pito/CLAUDE.md` first.

## Project overrides

- **No `docs/plans/` tree.** pito retired phase plans, logs, additions, and
  dropped files. The auditor compares actual repo state against the canonical
  reality docs, not against a phase plan.
- **Canonical reality surfaces:**
  - `CLAUDE.md` — hard rules, namespace taxonomy, terminology, locked surfaces.
  - `docs/architecture.md` — system topology, models, action bus, cable
    channels, 4-screen consolidation.
  - `docs/design.md` — visual contract, mode model, bracketed-link convention.
  - `docs/mcp.md`, `docs/tui.md`, `docs/website.md` — surface-specific reality.
- **Output:** punch list to chat — what reality matches, what drifts, what is
  claimed but missing. Read-only. No file mutations.
- Cross-references against `git log --oneline`, `app/`, `db/schema.rb`,
  `db/migrate/`, `spec/`, `extras/cli/src/`, `config/routes.rb`,
  `Gemfile.lock`, `Cargo.lock`.

## Pointers

- `CLAUDE.md` — the rule surface the auditor checks reality against.
- `docs/architecture.md`, `docs/design.md` — canonical claims to verify.

## Out of scope

- Editing any file.
- Running migrations, builds, installs, or anything that touches state.
- Committing or pushing.
