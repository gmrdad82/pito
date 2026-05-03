# pito-sh Build Plan

## Iteration 1 — Testable TUI Dashboard (current)

- Cargo project init with ratatui, crossterm, tokio, serde, anyhow, thiserror
- Module structure: main, app, ui (mod, dashboard, channels, help), theme, keys
- Dashboard screen: 2x2 chart grid with fake sparkline data (views, subscribers,
  watch time, likes)
- Channels screen: placeholder table with hardcoded data
- Help overlay: keyboard shortcut reference
- Theme system: Dracula dark + light mode, toggle with `n`
- Keyboard navigation: `g d`/`g c` screen switching, `?` help, `q`/`:q`/Ctrl+C
  quit
- Header/footer bars with contextual hints

## Iteration 2 — API Client & Auth

- Token-based auth flow (login, persist token)
- HTTP client module (reqwest)
- API response types (serde models)
- Replace hardcoded data with real API calls
- Error handling & offline state display

## Iteration 3 — Videos Screen & Lists

- Videos table with sorting/filtering
- j/k navigation within lists
- `/` search/filter
- Scrollable content with viewport tracking

## Iteration 4 — Saved Views & Configuration

- Saved views screen (`g s`)
- Config file (~/.config/pito-sh/config.toml)
- Persistent preferences (theme, default view)

## Iteration 5 — Polish & Release

- Loading states & spinners
- Error toasts / status messages
- Clipboard support
- Packaging (cargo-dist, AUR)
- CI/CD pipeline
