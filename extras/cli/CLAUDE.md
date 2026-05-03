# extras/cli

This directory is the Rust `pito` CLI binary — a unified TUI + subcommand
surface (footage import, future subcommands). Project rules and orchestration
live at `../../CLAUDE.md`. Agent definitions are at
`../../.claude-config/agents/`.

This directory is the file scope for the `cli-impl` agent.

The crate is `pito` (binary name `pito`). Default invocation (`pito` with no
args) launches the TUI — current behavior. Subcommand pattern follows the
`claude` binary: `pito help`, `pito version`, `pito footage <args>`.
