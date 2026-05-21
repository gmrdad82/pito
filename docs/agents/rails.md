# pito-rails — project-specific extensions

Project-scoped overrides for the Rails-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rails.md`. Read project-wide rules in
`/home/catalin/Dev/pito/CLAUDE.md` first.

## Project overrides

### Namespace taxonomy (canonical, locked)

Every new Ruby/ERB module respects this taxonomy. See `CLAUDE.md` and
`docs/architecture.md` § "Namespaces" for the full rationale.

- `Pito::*` — cross-cutting app primitives (`Pito::ActionDispatcher`,
  `Pito::Theme`, etc.).
- `Settings::*`, `Channel::*`, `Video::*`, `Game::*`, `Bundle::*`,
  `Footage::*` — per-domain models, services, jobs.
- `Screen::<screen>::*PanelComponent` — every panel ViewComponent under a
  screen. `Screen::Settings::SecurityPanelComponent`,
  `Screen::Channel::HistoryPanelComponent`, etc.
- `Tui::*` — shared TUI/visual primitives (`Tui::CheckboxComponent`,
  `Tui::FramedPanelComponent`, etc.).

Never create parallel namespaces (`App::*`, `Domain::*`, plain top-level
component names). Refactor a canonical primitive rather than forking.

### ViewComponents are kings

Every visible HTML element wraps in a ViewComponent — even when used once.
Every panel becomes a `Screen::<screen>::*PanelComponent`. Forking a component
to support a new use case is never allowed; refactor the canonical (add a
kwarg, extract a variant) instead. See `CLAUDE.md` → "ViewComponents are
kings".

### Every ViewComponent ships with a spec

A new VC without `spec/components/<path>/<name>_component_spec.rb` is
incomplete. This overrides the iteration-defers-specs rule for VC creation
specifically — VC + spec land together.

### No Capybara / no system specs

pito does not run system specs. The `.rspec` exclusion is permanent. Coverage
comes from request specs, model specs, service specs, job specs, ViewComponent
specs, helper specs, validator specs, MCP tool specs, and lib specs. Routing
specs only when route logic is non-trivial. Critical-journey coverage lives in
request specs (multi-step request flows), not in Capybara.

### 6-gate audit on every dispatch landing

Master enforces the 6-gate audit (see `CLAUDE.md` → "Master dispatch
presentation checklist"). Implementation agents self-check against the same
gates before reporting: agent success, specs passing for new behavior, VC used
+ spec written for UI changes, no design-rule violation, Turbo + cable
discipline preserved, namespace taxonomy respected.

### Brand capitalization in copy and code

Slack, Discord, YouTube, Voyage AI, PostgreSQL, Meilisearch, OAuth, Git stay
capitalized in user-visible copy and identifiers where applicable. pito renders
lowercase everywhere in copy — including sentence-start. Locales, flash
messages, panel headings —
all respect this.

### Yes / no boundary

Every boolean crossing an external boundary (URL params, JSON, MCP I/O, CLI
args, Rust wire format) is a `"yes"` / `"no"` string. Internal storage stays
Boolean. Convert at the boundary.

### Migrations: run them

When this agent creates `db/migrate/*.rb`, it MUST run `bin/rails db:migrate`
against the dev DB before reporting. Test DB migrates automatically via RSpec;
dev DB does not. Verify with `bin/rails db:migrate:status` that no `down` rows
remain.

### Spec invocation

`bin/test <files>` for targeted verification of the specs this agent just
wrote. Do NOT run `bin/test failed` or `bin/test all` — those are the
architect's pre-commit pass. Agents do not run the full suite.

### External links

External `<a>` tags carry `target="_blank" rel="noopener noreferrer"`.
`BracketedLinkComponent` emits this pair automatically for absolute http(s)
hrefs — prefer the component over raw `<a>` tags everywhere.

### No JS confirm dialogs

No `alert` / `confirm` / `prompt` / `data-turbo-confirm`. Confirmation flows go
through the action confirmation framework (`shared/_action_screen.html.erb` +
`DeletionsController` / `SyncsController` / `Confirmable` concern). Carve-out:
`beforeunload` via the `unsaved-form` Stimulus controller is allowed (browser
native, not a JS interrupt).

## Pointers

- `CLAUDE.md` — hard rules, namespace policy, terminology, 6-gate audit.
- `docs/architecture.md` — topology, models, action bus, cable channels.
- `docs/design.md` — visual contract, mode model, bracketed-link convention.

## File scope

`app/`, `lib/`, `config/`, `db/migrate/`, `Gemfile`, `bin/`,
`.github/workflows/`. Specs under `spec/`. Never touch `docs/`, `extras/`.

## Out of scope

- Committing or pushing.
- Updating docs under `docs/` — route through pito-docs.
- Writing in `extras/cli/` or `extras/website/`.
