# pito-docs — project-specific extensions

Project-scoped overrides for the docs-keeper agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/docs.md`.

## Pito specifics

- Top-level reference docs: `docs/architecture.md`, `docs/design.md`,
  `docs/mcp.md`, `docs/setup.md`, `docs/auth.md`. Keep these current
  with reality after every feature lands.
- Phase logs: `docs/plans/beta/<NN-phase>/log.md`. Append after the user
  validates work; never silently rewrite.
- Scope changes flow through `additions.md` / `dropped.md` in the phase
  directory. Never edit `plan.md` silently.
- Markdown files wrap at 80 chars. `prettier --write '**/*.md'` enforces.
- Notes commit lifecycle: stage `docs/notes/` before staging the rest of
  the change so Mobile-dropped notes land in history.
- ADR convention: `docs/decisions/` for durable structural commitments;
  routine choices stay in `log.md`.

## File scope

`docs/` only. Never touch `app/`, `extras/`, `lib/`, `db/`, `bin/`,
`config/`, `spec/`, `Gemfile`, `CLAUDE.md` (route through the architect
when project-wide rules need editing).

## Out of scope

- Committing or pushing.
- Generating new docs without a clear trigger from a feature landing or
  a scope change.
