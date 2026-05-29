# pito — follow-ups (Plan 2+)

These are explicitly NOT in Plan 1. They live in subsequent plans.

## Interaction & UI

- Stimulus controllers (autoscroll, slash palette toggle on `/`, TAB channel cycling, Ctrl+P modal open/close, sidebar toggle, theme switcher, expand/collapse on tool-output cards)
- Theme switcher UI + additional theme variants (Catppuccin, Gruvbox, etc.)
- Removing the `/_ui/*` review routes once palettes and sidebar are wired as interaction-driven overlays
- Tip dictionary (rotating tips on start screen — replaces the placeholder string)

## Streaming & real-time

- Action Cable channels + Turbo Streams for message streaming

## Command system

- Command router + handler registry (`lib/pito/command/router.rb`)

## Data & persistence

- Persistence layer (Session, Message models — Plan 0 P7 covers schema)
- Real data sources (channels, videos, games)
- Voyage.AI recommendation pipeline

## Authentication

- Authentication (`/authenticate <code>` command + TOTP flow, `before_action :require_login`)
- YouTube OAuth flow (handled by `omniauth-google-oauth2` from Plan 0 P14)

## Content & rendering

- Markdown rendering of streamed content (defer; ASCII suffices today)

## Testing & tooling

- Component spec coverage (RSpec component tests via `view_component/test_helpers`)
- Lookbook (deferred; possibly never per Plan 0 lock)

---

## Plan 2 — Slash Core (explicitly NOT in scope)

- The Chat branch of `ChatController#create` (Plan 3).
- Chat parser, registry, handlers, refinement turn model (Plan 3).
- Real domain handlers: `/publish`, `/schedule`, `/connect`, `/authenticate`, `/config` (later plans, one per domain).
- The actual confirmation flow — a real handler that triggers, accepts `/confirm`/`/cancel`, completes the action. (Later plan.)
- Multi-conversation routing: `current_conversation` becomes per-tab/per-URL; new-session creation; session picker. (Later plan.)
- Ctrl+K (or Ctrl+P) command palette UI (later plan; palette components exist as static visuals from Plan 1).
- Slash command autocomplete / suggestions while typing.
- Syntax highlighting of the input.
- History navigation (↑/↓ through previous inputs).
- Multi-step dialogs with masked input (e.g. `/authenticate` with 6 TOTP boxes).
- Real OAuth flow for `/connect`.
- Per-handler authorization checks.
- Rate limiting on `POST /chat`.
- Localization beyond English.
