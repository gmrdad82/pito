# TUI — Rust client surface

> Skeleton — to fill in fresh after the doc walk.

## Process model

(placeholder — single `pito` binary at `extras/cli/`. Default (no args)
launches the TUI. Subcommands: `pito footage`, `pito help`, `pito version`.)

## Surface contract

(placeholder — Ratatui-based. Screens map 1:1 to web `app/views/*`.
Layout chrome (TST + content + BST) matches the web's grammar exactly.)

## Cable subscription

(placeholder — TUI subscribes to the same `pito:*` cable channels as the
web client. Payloads identical. Bridge via Rails MCP/web Puma WebSocket.)

## Screen export

(placeholder — `lib/tasks/pito_tui_export.rake` reads ViewComponent specs +
`Pito::Theme` + i18n YAMLs + design.md locks → emits per-screen TOML at
`extras/cli/src/screens/specs/<screen>.toml` that the Rust client consumes
at compile time via `include_str!` + serde-deserialized `ScreenSpec`.)

## Theme export

(placeholder — `lib/tasks/pito_theme.rake` emits `extras/cli/src/theme.rs`
from `Pito::Theme::SEMANTIC` tokens.)

## Cross-stack parity tests

(placeholder — for each pure formatter / cell-producer
(`Tui::SegmentedBarComponent`, `Tui::ShadedDensityComponent`, sparkline
helpers, `Formatting::*`), Rust has equivalent functions with the same
name + input/output. Fixtures captured at rake export time.)

## Authentication

(placeholder — local OAuth via `pito` browser-flow + token cached in
`~/.config/pito/credentials.toml`. Bearer in WebSocket subscribe.)

## Wire format

(placeholder — yes/no for external booleans. JSON over WebSocket.
Channel-payload envelope: `{ kind, payload, ts }`.)
