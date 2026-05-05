# pito-rails — project-specific extensions

Project-scoped overrides for the Rails-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rails.md`.

## Pito specifics

- Stack: Rails 8.1, Hotwire (Turbo + Stimulus), ERB, Tailwind CSS, Postgres
  17 (pgvector / pgcrypto / citext), Redis 7, Sidekiq + sidekiq-cron.
- Test runner: `bundle exec rspec`. Lint: `bundle exec rubocop`. Security
  smoke: `bundle exec brakeman -q`.
- Every change must include RSpec specs alongside.
- Hard rules live in `CLAUDE.md` — bracketed `[label]` link convention,
  bulk-as-foundation URLs, `yes`/`no` strings at external boundaries,
  no JS `alert`/`confirm`/`prompt`/`data-turbo-confirm` (carve-out:
  `unsaved-form` Stimulus controller for `beforeunload`).
- View components live under `app/components/` (ViewComponent). Helpers
  hold logic only — see the `ViewComponents and decorators` memory note.
- Modal pattern: `ConfirmModalComponent` for in-page confirms, action
  pages (`/deletions/`, `/syncs/`) for destructive flows. Both use the
  shared `.modal-footer` class for the hairline-separated action row.
- Notes editor: `field-sizing: content` on the textarea, no JS autogrow,
  counter in normal flow inside the right pane (see `app/views/notes/show.html.erb`).

## File scope

`app/`, `lib/`, `config/`, `db/migrate/` (when no DBA agent is involved),
`Gemfile`, `bin/`, `.github/workflows/`. Specs under `spec/`. Never touch
`docs/`, `extras/`, `.claude-config/` (deprecated).

## Out of scope

- Committing or pushing.
- Updating documentation under `docs/` — route through pito-docs.
- Writing in `extras/cli/`, `extras/website/` — those go to pito-rust /
  pito-astro respectively.
