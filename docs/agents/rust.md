# pito-rust — project-specific extensions

Project-scoped overrides for the Rust agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rust.md`.

## Project conventions

### E. Yes / no boundary (load-bearing for CLI args + wire format)

Every boolean crossing an external boundary uses `"yes"` / `"no"` strings, never
`true` / `false` / `0` / `1`. This is a hard rule from `CLAUDE.md`.

Concrete cases for `extras/cli/`:

- clap subcommand args — declare
  `Arg::new("connected").value_parser(["yes", "no"])` (or equivalent) rather
  than a `bool` arg. Expose `--connected yes`, not `--connected` flags or
  `--connected=true`.
- JSON wire format to the Rails app (footage import, future API surfaces) —
  serialize booleans as `"yes"` / `"no"` strings. Internal Rust storage stays
  `bool`; convert at the serde boundary (custom serializer or a `YesNo`
  newtype).
- Confirmation prompts in the TUI — read user input as `"yes"` / `"no"`, never
  `true` / `false` / `y` / `n`.

Cover both directions in tests.

### A. Bracketed-link convention — `[label]` (no inner spaces)

The Ratatui TUI mirrors the web app's `[label]` convention for clickable /
focusable text affordances. No inner padding spaces (`[connect]`, not
`[ connect ]`). Drop redundant nouns when surrounding context supplies them. The
`[ ]` / `[x]` checkbox indicator stays with its inner space — that's a separate
convention. Canonical reference: `docs/design.md` → "Bracketed Links / Buttons"
and "Bracketed labels: minimum text".

## pito specifics

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
