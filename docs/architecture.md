# pito — architecture

## Static UI baseline (Plan 1)

Plan 1 delivers the static visual chassis — no wiring, no real data, no Stimulus, no Action Cable.

### Production routes

| Path | Controller#action | Description |
|---|---|---|
| `/` | `terminal#show` | Chat shell with hardcoded sample messages. Main pito interface. |
| `/start` | `start_screens#show` | Start screen for unauthenticated entry. Centered chatbox, ASCII logo, tip line. |

### Review-only routes (removed in Plan 2+)

| Path | Controller#action | Description |
|---|---|---|
| `/_ui/palettes` | `_ui/palettes#show` | Static preview of slash and Ctrl+P command palettes. |
| `/_ui/sidebar` | `_ui/sidebar#show` | Static preview of the game-detail sidebar as a right-edge overlay. |

These review routes exist only for visual inspection during development. In Plan 2+, palettes and sidebar become interaction-driven overlays and the `/_ui/*` routes are removed.

### UI stack

- **CSS**: Tailwind v4 via `tailwindcss-rails` (standalone CLI, zero Node.js). Theme tokens as CSS custom properties under `[data-theme="tokyo-night"]`.
- **Components**: `view_component` gem. Namespace: `Pito::*`. All visual primitives build on `Pito::Segment::Component` (bar+gap+content pattern).
- **i18n**: All user-facing copy in `config/locales/pito/<area>/en.yml`. Sample message bodies under `config/locales/pito/sample/en.yml` — replaced when real data is wired.
- **JS**: None in Plan 1. Turbo + Stimulus + importmap-rails available but unused.

### Component tree

```
Pito::Segment::Component          — bar+gap+content layout primitive
Pito::Cursor::Component           — inverted-character cursor

Pito::Shell::ChatboxComponent     — input area (uses Segment + Cursor)
Pito::Shell::MiniStatusComponent  — connection/auth status bar
Pito::Shell::PostCommandDotsComponent — animated comet dots
Pito::Shell::InProgressComponent  — spinner + shimmer verb

Pito::Event::UserMessageComponent     — user chat message
Pito::Event::AssistantTextComponent   — assistant response
Pito::Event::ThoughtComponent         — "Thought:" prefix + duration
Pito::Event::ToolOutputComponent      — expandable command output
Pito::Event::StatusFooterComponent    — mode · agent · duration

Pito::StartScreen::Component     — full-viewport start screen

Pito::Palette::Slash::Component        — /-prefixed command palette
Pito::Palette::CtrlP::Component        — centered modal command palette
Pito::Palette::CtrlP::SectionComponent — section inside Ctrl+P

Pito::Sidebar::Component         — fixed right-edge overlay panel
Pito::Sidebar::SectionComponent  — labeled section inside sidebar
```

### Sample data

Hardcoded sample content lives in `lib/pito/sample/`. Files are marked `# SAMPLE` and will be replaced when Plan 2+ wires real data:

- `lib/pito/sample/chat_shell.rb` — 17 events across 4 exchanges
- `lib/pito/sample/game_detail.rb` — Hollow Knight detail with 6 sections
