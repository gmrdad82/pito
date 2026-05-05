# pito-rust — project-specific extensions

Project-scoped overrides for the Rust agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rust.md`.

## Pito specifics

- Crate path: `extras/cli/`. Single binary: `pito`.
- Default mode (no args): Ratatui TUI. Subcommands styled after the `claude`
  binary — `pito footage`, `pito help`, `pito version`, future surfaces.
- TUI uses Ratatui + the JSON / ActionCable client layer.
- Subcommands use clap-derive plus per-subcommand modules.
- Footage import client at `extras/cli/src/footage/` — JSON API hits
  `/api/projects/<id>/footages.json`.
- Browser-only flows (e.g. video uploads) get recorded under `docs/decisions/`
  rather than implemented.
- Gates: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`. CI runs from `extras/cli/` working directory.

## File scope

`extras/cli/` only. Never touch `app/`, `docs/`, `extras/website/`,
`.claude-config/`.

## Out of scope

- Committing or pushing.
- Modifying the Rails app, the website, or any documentation.
