# pito-docs — project-specific extensions

Project-scoped overrides for the docs-keeper agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/docs.md`. Read project-wide rules in
`/home/catalin/Dev/pito/CLAUDE.md` first.

## Project overrides

- **Canonical docs (the full set):** `CLAUDE.md`, `docs/architecture.md`,
  `docs/design.md`, `docs/mcp.md`, `docs/tui.md`, `docs/website.md`, and the
  per-agent stubs under `docs/agents/`. That is the entire durable docs surface.
- **No `docs/plans/`, no `docs/orchestration/`, no `docs/decisions/`,**
  **no `docs/notes/`, no `docs/setup.md`, no `docs/auth.md`.** All retired.
  `auth.md` content folded into `docs/architecture.md`. Phase logs and
  additions/dropped tracking are gone — the docs reflect current reality, not
  history.
- **Update reality in place.** When a feature lands and a canonical doc no
  longer matches the code, edit the doc directly. Never archive prior versions
  in-file; git history is the archive.
- **Markdown wraps at 80 chars.** `prettier --write '**/*.md'` enforces.
- **Brand capitalization:** Slack, Discord, YouTube, Voyage AI, PostgreSQL,
  Meilisearch, OAuth, Git. pito renders lowercase everywhere in prose —
  including sentence-start and headings — like iPhone / git / bash. The only
  uppercase form is the Ruby namespace (`Pito::*`).

## Pointers

- `CLAUDE.md` — collaboration contract; the durable-rule surface.
- `docs/architecture.md` — topology, models, action bus, cable channels.
- `docs/design.md` — visual contract, terminology, mode model.

## File scope

`docs/` only. Never touch `app/`, `extras/`, `lib/`, `db/`, `bin/`, `config/`,
`spec/`, `Gemfile`. `CLAUDE.md` edits go through the architect.

## Out of scope

- Committing or pushing.
- Generating docs without a clear trigger from a feature landing or scope
  change.
