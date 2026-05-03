# Session Log

## 2026-04-30 — Iteration 1: TUI Dashboard Bootstrap

Bootstrapped the pito-sh Rust TUI application from scratch.

### What was built

- Cargo project with dependencies: ratatui 0.29, crossterm 0.28, tokio, serde,
  anyhow, thiserror
- Full event loop with terminal setup/teardown (alternate screen, raw mode)
- Application state machine with screen enum (Dashboard, Channels) and overlay
  (Help)
- Dashboard screen: 2x2 grid of Braille-marker charts showing fake 12-month data
  for views, subscribers, watch time, and likes
- Channels screen: placeholder table with hardcoded channel stats
- Help overlay: centered popup listing all keyboard shortcuts
- Theme module: Dracula dark palette + light mode alternative, toggleable with
  `n`
- Key handler: supports `g` prefix combos (g d, g c), colon prefix (:q), Ctrl+C,
  `?` for help, `q` for back/quit
- Header bar with active screen indicator and shortcut hints
- Footer bar with key state feedback

### Design decisions

- Used crossterm sync event reading (no async needed yet — no network calls)
- Braille markers for chart density in small terminal areas
- Theme as a simple struct passed by value (cheap to copy, 10 Color fields)
- KeyState enum for multi-key sequences (g prefix, colon prefix)

### Next steps

- Wire up real API client in iteration 2
- Add videos screen and list navigation
