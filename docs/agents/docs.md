# pito-docs — project-specific extensions

Project-scoped overrides for the docs-keeper agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/docs.md`.

## Project conventions

When authoring or editing prose under `docs/`, follow the same conventions the
rest of the repo enforces.

### A. Bracketed-link convention — `[label]` (no inner spaces)

Examples and references inside docs use the `[label]` form — no inner padding.
Write `[add channel]`, not `[ add channel ]`. The `[ ]` / `[x]` checkbox
indicator is a separate convention and keeps its inner space. When quoting
historical shapes (e.g. "the prior `[ label ]` shape"), make the historical
context explicit so the older form isn't mistaken for current. Canonical:
`docs/design.md` → "Bracketed Links / Buttons" and "Bracketed labels: minimum
text".

### B. Lead-paragraph copy — one sentence per line

Page-style docs that imitate web view layout (e.g. mock copy in specs) should
split the lead paragraph into one sentence per line via `<br>` inside one
`<p class="text-muted">`. Inside pure prose docs (architecture, design, ADRs),
follow regular prose with the 80-char wrap — the one-sentence-per-line rule
applies to UI copy specs, not narrative docs.

## pito specifics

- Top-level reference docs: `docs/architecture.md`, `docs/design.md`,
  `docs/mcp.md`, `docs/setup.md`, `docs/auth.md`. Keep these current with
  reality after every feature lands.
- Phase logs: `docs/plans/beta/<NN-phase>/log.md`. Append after the user
  validates work; never silently rewrite.
- Scope changes flow through `additions.md` / `dropped.md` in the phase
  directory. Never edit `plan.md` silently.
- Markdown files wrap at 80 chars. `prettier --write '**/*.md'` enforces.
- Notes commit lifecycle: stage `docs/notes/` before staging the rest of the
  change so Mobile-dropped notes land in history.
- ADR convention: `docs/decisions/` for durable structural commitments; routine
  choices stay in `log.md`.

## File scope

`docs/` only. Never touch `app/`, `extras/`, `lib/`, `db/`, `bin/`, `config/`,
`spec/`, `Gemfile`, `CLAUDE.md` (route through the architect when project-wide
rules need editing).

## Out of scope

- Committing or pushing.
- Generating new docs without a clear trigger from a feature landing or a scope
  change.
