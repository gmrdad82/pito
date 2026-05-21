# pito-rust — project-specific extensions

Project-scoped overrides for the Rust agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/rust.md`. Read project-wide rules in
`~/Dev/pito/CLAUDE.md` first.

## Project overrides

- **Canonical reference:** `docs/tui.md` is the source of truth for the CLI —
  parity contract with the web app, screen export plan, theme export, action
  dispatcher wire format. Read it first.
- **100% web parity is the goal.** Every screen, panel, action, and visual
  affordance the web app surfaces is reachable from the TUI. Screens are
  derived from ViewComponent specs + `Pito::Theme` + i18n + `docs/design.md`
  via a rake task that emits TOML screen specs the Rust client consumes.
- **Crate path:** `extras/cli/`. Single binary: `pito`. Default mode (no
  args): Ratatui TUI. Subcommands (`pito footage`, `pito help`, `pito
  version`, etc.) styled after the `claude` binary.
- **Yes / no boundary (hard rule).** All external booleans use `"yes"` /
  `"no"` strings:
  - clap args: `Arg::new("connected").value_parser(["yes", "no"])`.
  - JSON wire format to Rails: serialize as `"yes"` / `"no"`; convert at the
    serde boundary.
  - TUI confirmation prompts: read input as `"yes"` / `"no"`, never `y` / `n`.
- **Bracketed-link convention:** mirror the web app's `[label]` form for
  clickable / focusable TUI affordances. `[ ]` / `[x]` checkbox indicator
  keeps its inner space.
- **Gates:** `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`. Run from `extras/cli/` working directory.

## Pointers

- `docs/tui.md` — canonical CLI parity and architecture.
- `docs/design.md` — visual contract the TUI mirrors.
- `docs/architecture.md` § "Action bus" — `Pito::ActionDispatcher` wire
  format the Rust client calls.

## File scope

`extras/cli/` only. Never touch `app/`, `docs/`, `extras/website/`.

## Out of scope

- Committing or pushing.
- Modifying the Rails app, the website, or documentation.
