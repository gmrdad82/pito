# pito-architect — project-specific extensions

Project-scoped overrides for the architect agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/architect.md`. Read project-wide rules in
`/home/catalin/Dev/pito/CLAUDE.md` first.

## Project overrides

- **No `docs/plans/` tree.** pito no longer maintains phase plans, phase logs,
  additions, or dropped files. The phase-plan workflow is retired. The architect
  works directly from canonical docs + chat context.
- **Specs live in `tmp/specs/<slug>.md`** (gitignored). They are scratch
  artifacts for a single dispatch wave — once the work lands, the spec is
  reference, not history. Canonical rules absorb anything durable; specs do not
  archive.
- **No ADRs.** `docs/decisions/` is retired. Durable architectural rules are
  folded directly into `docs/architecture.md`, `docs/design.md`, or `CLAUDE.md`.
  If a decision needs a home and none of the three fits, route through
  pito-docs to add a section to the most appropriate canonical doc.
- **No phase logs.** Session work surfaces in chat + the docs that need to
  reflect new reality. The architect does not append to a log file.
- Specs cite canonical sources by `file.md § section` — never invent values.
  Bare numbers without citation are a smell (see `CLAUDE.md` → "Look up, never
  pick").

## Pointers

- `CLAUDE.md` — collaboration contract, namespace policy, 6-gate audit,
  parallel-by-default dispatch model, plan mode default.
- `docs/architecture.md` — system topology, models, action bus, cable channels,
  4-screen consolidation.
- `docs/design.md` — visual contract, terminology, mode model, bracketed-link
  convention, brand capitalization.
- `docs/mcp.md` — MCP tool surface scope.
- `docs/tui.md` — Rust CLI parity contract.

## Out of scope

- Writing code in `app/`, `extras/`, `lib/`, `db/`, `bin/`, `config/`, `spec/`.
- Editing canonical docs directly — route through pito-docs.
- Committing or pushing.
