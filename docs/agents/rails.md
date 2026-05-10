# pito-rails — project-specific extensions

Project-scoped overrides for the Rails-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rails.md`.

## Project conventions

The architect gates these at spec time, but the Rails impl agent enforces them
at the code level. If a spec contradicts a rule, STOP and report.

### A. Bracketed-link convention — `[label]` (no inner spaces)

User-facing bracketed links use `[label]` (no inner padding). `[add channel]`
not `[ add channel ]`. Drop redundant nouns when the page heading supplies
context — `[add]` instead of `[add channel]` on an "Add channel" page.
`BracketedLinkComponent` already renders the tightened form; never hand-roll
inline brackets. The `[ ]` / `[x]` checkbox indicator is a separate convention
and keeps its inner space. Canonical reference: `docs/design.md` → "Bracketed
Links / Buttons" and "Bracketed labels: minimum text".

### B. Lead-paragraph copy — one sentence per line

The muted lead paragraph under each page H1 renders one sentence per line. Use
`<br>` between sentences inside one `<p class="text-muted">` so the existing
margin styling holds. Apply to every settings detail page and every `new` /
`show` / `edit` view with explanatory prose under the heading.

### C. Pane primitives

- `.pane` — fixed-width workspace column (`flex: 0 0 452px`), zebra-striped by
  `:nth-child(even)` inside `.pane-row`. Channels / videos workspace and
  settings index grid use this.
- `.pane.pane--standalone` — full-width single-column container, same pane
  background, no fixed width. Use for oauth_applications create / show / revoke,
  doorkeeper authorizations new / show / error, settings/tokens create / revoke,
  settings/sessions revoke, and form pages.
- `.pane--wide` — fixed 904px double-column workspace variant.

`.framed-block` is orphaned; reach for `pane--standalone` instead. Canonical
reference: `docs/design.md` → "Panes (Multi-item View)".

### D. Spec pyramid

Every implementation pass covers, at minimum:

1. Model specs (validations, associations, callbacks, scopes, public methods).
2. Service specs.
3. Job specs (Sidekiq / cron).
4. ViewComponent specs.
5. Helper specs.
6. Validator specs.
7. `app/lib/` and `lib/` specs.
8. MCP tool specs.
9. Request specs — happy / sad / edge / flaw per controller / route.
10. System specs ONLY for critical user journeys. Selective, not blanket.
11. Routing specs only when route logic is non-trivial.

System specs are intentionally thin — slow and brittle.

### E. Yes / no boundary

External booleans (URL params, JSON, MCP I/O, CLI args, Rust client wire format)
are `"yes"` / `"no"` strings — never `true` / `false` / `0` / `1`. Internal
storage stays Boolean. Convert at every boundary. See `CLAUDE.md` hard rules.

## pito specifics

- Stack: Rails 8.1, Hotwire (Turbo + Stimulus), ERB, Tailwind CSS, Postgres 17
  (pgvector / pgcrypto / citext), Redis 7, Sidekiq + sidekiq-cron.
- Test runner: `bundle exec rspec`. Lint: `bundle exec rubocop`. Security smoke:
  `bundle exec brakeman -q`.
- Every change must include RSpec specs alongside.
- Hard rules live in `CLAUDE.md` — bracketed `[label]` link convention,
  bulk-as-foundation URLs, `yes`/`no` strings at external boundaries, no JS
  `alert`/`confirm`/`prompt`/`data-turbo-confirm` (carve-out: `unsaved-form`
  Stimulus controller for `beforeunload`).
- View components live under `app/components/` (ViewComponent). Helpers hold
  logic only — see the `ViewComponents and decorators` memory note.
- Modal pattern: `ConfirmModalComponent` for in-page confirms, action pages
  (`/deletions/`, `/syncs/`) for destructive flows. Both use the shared
  `.modal-footer` class for the hairline-separated action row.
- Notes editor: `field-sizing: content` on the textarea, no JS autogrow, counter
  in normal flow inside the right pane (see `app/views/notes/show.html.erb`).

## File scope

`app/`, `lib/`, `config/`, `db/migrate/` (when no DBA agent is involved),
`Gemfile`, `bin/`, `.github/workflows/`. Specs under `spec/`. Never touch
`docs/`, `extras/`, `.claude-config/` (deprecated).

## Out of scope

- Committing or pushing.
- Updating documentation under `docs/` — route through pito-docs.
- Writing in `extras/cli/`, `extras/website/` — those go to pito-rust /
  pito-astro respectively.
