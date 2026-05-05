# pito-architect — project-specific extensions

Project-scoped overrides for the architect agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/architect.md`.

## Pito specifics

- Phase plans live under `docs/plans/beta/<NN-phase>/`. The current phase is
  Phase 4 (Project Workspace) — see `docs/plans/beta/04-project-workspace/`.
- Beta master plan: `docs/plans/beta/beta.md`.
- Specs go under `docs/plans/beta/<NN-phase>/specs/<feature>.md` before any Lane
  1 (rails-impl) / Lane 2 (mcp-impl, cli-impl, website-impl) work fans out.
- Architectural Decision Records under `docs/decisions/` ONLY when a decision
  produces a durable artifact (new top-level reference doc or structural
  commitment). Routine choices live in `log.md`.
- Phase log file: `docs/plans/beta/<NN-phase>/log.md` — append after the user
  validates, never silently rewrite history.

## Out of scope

- Writing code in `app/`, `extras/`, `lib/`, `db/`, `bin/`, `config/`, `spec/`.
- Editing `CLAUDE.md` directly — route through pito-docs when project-wide rules
  need updating.
