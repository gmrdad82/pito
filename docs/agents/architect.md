# pito-architect — project-specific extensions

Project-scoped overrides for the architect agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/architect.md`.

## Project conventions (gate every spec on these)

The architect must encode every one of these into specs before dispatching
implementation lanes. These are standing rules; they apply across web, MCP, CLI,
and website surfaces unless a rule says otherwise.

### A. Bracketed-link convention — `[label]` (no inner spaces)

User-facing bracketed links use the `[label]` form — no inner padding spaces.
Examples: `[add channel]` not `[ add channel ]`, `[connect]` not `[ connect ]`.
When the surrounding heading already supplies the noun, drop it: `[add]` inside
an "Add channel" heading. Tightening adopted 2026-05-10.

The 3-char checkbox indicator (`[ ]` paired with `[x]`) is a separate convention
and stays with inner space.

Canonical reference: `docs/design.md` → "Bracketed Links / Buttons" and
"Bracketed labels: minimum text".

### B. Lead-paragraph copy — one sentence per line

The muted lead paragraph under each page H1 splits one sentence per line — no
chunky body of text. Use `<br>` between sentences inside one
`<p class="text-muted">` to preserve the existing margin styling. Apply on every
settings detail page and every `new` / `show` / `edit` page that has explanatory
prose under the heading.

### C. Pane primitives

Three primitives, all driven by `--color-pane-bg-a` with zebra
`:nth-child(even)` swap on multi-pane rows:

- `.pane` — fixed-width (`flex: 0 0 452px`) workspace column. Used inside
  `.pane-row` for the channels / videos workspace and the settings index grid.
- `.pane.pane--standalone` — full-width single-column container with the same
  pane background but no fixed width. Used for full-width data-display surfaces
  (oauth_applications create / show / revoke, doorkeeper authorizations new /
  show / error, settings/tokens create / revoke, settings/sessions revoke). Form
  pages also use it.
- `.pane--wide` — fixed 904px workspace double-column variant.

`.framed-block` is now orphaned — `pane--standalone` replaced it. Specs that
reach for a frame-style container call out `pane--standalone` instead.

Canonical reference: `docs/design.md` → "Panes (Multi-item View)".

### D. Spec pyramid (mandatory sweep on every dispatch)

For every architect dispatch and every implementation pass, the spec sweep
covers:

1. Model specs — validations, associations, callbacks, scopes, public methods.
2. Service specs — every service object.
3. Job specs — every Sidekiq / cron job.
4. Component specs — every ViewComponent.
5. Helper specs — every helper module.
6. Validator specs — every custom validator.
7. Lib specs — every `app/lib/` and `lib/` class.
8. MCP tool specs — every tool.
9. Request specs — every controller / route, happy / sad / edge / flaw.
10. System specs — ONLY for critical user journeys (login, OAuth pair, publish
    flow, MCP token re-pair, etc.). Selective, not blanket.
11. Routing specs — only when route logic is non-trivial.

System specs are intentionally thin; they're slow and brittle.

### E. Yes / no boundary

External booleans (URL params, JSON, MCP I/O, CLI args, Rust client wire format)
use `"yes"` / `"no"` strings — never `true` / `false` / `0` / `1`. Internal
storage stays Boolean. Convert at every boundary. See `CLAUDE.md` hard rules.

### F. Tenant-free single-install + multi-user

No `tenant_id` columns, no `BelongsToTenant` concern, no `Current.tenant`.
Single-install + multi-user; every authenticated user has install-wide access.
IDOR test obligations retired. Canonical decision:
`docs/decisions/0003-drop-tenant-single-install-multi-user.md` (and
`0004-mcp-scope-simplification-dev-app.md` for the matching MCP scope collapse).

## pito specifics

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
