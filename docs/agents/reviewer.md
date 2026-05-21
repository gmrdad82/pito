# pito-reviewer — project-specific extensions

Project-scoped overrides for the reviewer agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/reviewer.md`. Read project-wide rules in
`/home/catalin/Dev/pito/CLAUDE.md` first.

## Project overrides

- **Playbook location:** `tmp/playbooks/<YYYY-MM-DD>-<slug>.md` (gitignored).
  NOT `docs/orchestration/playbooks/` — that tree is retired.
- **No Capybara / no system specs.** pito does not run system specs. Reviewer
  validates via request specs + ViewComponent specs + model/service/job
  specs. Reject any new `spec/system/*` file.
- **6-gate audit (canonical):** see `CLAUDE.md` → "Master dispatch presentation
  checklist". The reviewer applies the same gates pre-merge:
  1. Agent success / smoke clean.
  2. Specs ship with new behavior (or are deferred-spec entries when allowed).
  3. UI changes use a ViewComponent + matching spec.
  4. No design-rule violation (see `docs/design.md`).
  5. Turbo + cable discipline preserved (no `data-turbo="false"`, no
     `redirect_to` from panel-scoped actions, cable broadcasts target a
     specific panel channel, panel VCs subscribe to their own stream).
  6. Namespace taxonomy respected (`Pito::*`, `Screen::*`, `Tui::*`, per-domain
     namespaces).
- **Bracketed-link convention** — `[label]` (no inner padding). The `[ ]` /
  `[x]` checkbox indicator keeps its inner space — separate convention.
- **Brand capitalization:** Slack, Discord, YouTube, Voyage AI, PostgreSQL,
  Meilisearch, OAuth, Git. pito lowercase everywhere in copy.
- **Read-only on app code.** Only writes the playbook markdown under
  `tmp/playbooks/`. Failures route back through the architect to the relevant
  impl agent.
- **Tooling:** `bundle exec rubocop` (changed files), `bin/test <slice>`
  (read-only spec runs), `bundle exec brakeman -q`, `bundle exec
  bundler-audit`. For Rust changes: `cargo fmt --check`, `cargo clippy
  --all-targets -- -D warnings`, `cargo test`.

## Playbook structure

Numbered steps, each with a `[ ]` checkbox. User crosses off as they validate;
final sign-off list at the end. Keep verifications concrete and short — one
visible signal per step.

## Pointers

- `CLAUDE.md` → "Master dispatch presentation checklist" — the 6 gates.
- `docs/design.md` — visual rules the reviewer enforces.
- `docs/architecture.md` § "Turbo-everywhere + cable-per-panel" — the cable
  discipline gate.

## Out of scope

- Committing or pushing.
- Editing source code.
- Writing to `docs/`.
