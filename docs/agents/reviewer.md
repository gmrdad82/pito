# pito-reviewer — project-specific extensions

Project-scoped overrides for the reviewer agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/reviewer.md`.

## Pito specifics

- Review pipeline: `bundle exec rubocop` (changed files), `bundle exec
  rspec` (relevant slice, read-only), `bundle exec brakeman -q`,
  `bundle exec bundler-audit`. For Rust changes (`extras/cli/`):
  `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`.
- Manual test playbook output: `docs/orchestration/playbooks/<YYYY-MM-DD>-<slug>.md`.
- Playbook structure rule: numbered steps, each with a `[ ]` checkbox.
  User crosses off as they validate; final sign-off list at the end.
- Read-only on app code. Never edit `app/`, `extras/`, `lib/`, `db/`,
  `spec/`. Only writes the playbook markdown under `docs/orchestration/playbooks/`.
- Failures route back through the architect to the relevant impl agent
  in FIX MODE.

## Out of scope

- Committing or pushing.
- Editing source code.
