# Design

> All visual picks live in `tmp/*.html` demos. Each rule below cites the
> demo where the pick was made, when applicable. Demos are gitignored
> and persist locally as the source of truth.

## Goal

Replicate the vim / nvim / terminal experience in the browser. Excel-sheet
density: number-heavy, minimal whitespace, minimal decoration. ASCII /
unicode charts where possible. White space is a premium.

Keyboard-only. Mouse activity triggers an "invalid input" dialog.

Flat navigation over nested submenus — number-heavy dashboards beat
multi-layer menus.

## Typography

- Font family: system monospace stack
  (`ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas,
   monospace`)
- Base size: **13px**
- Line-height: **1**
- Default weight: 400 (normal)
- **Bold is earned, not attributed.** Only the section identifier in TST,
  the focused panel title, and a small set of explicit headings get bold.
- Italic reserved for **hints** (`type "clear" to remove`).
- `tabular-nums` (`font-variant-numeric: tabular-nums`) for any numeric
  cell.

## Colors

Dracula-derived palette. Exact hex values live in `app/lib/pito/theme.rb`
and export to CSS custom properties + Rust `theme.rs` via
`lib/tasks/pito_theme.rake`.

- Text: high-contrast against bg
- Muted: `var(--color-muted)` for de-emphasized prose + inactive UI
- Borders: section-accent-tinted hairline (1px)
- Background: panel bg + sub-panel bg with subtle delta
- **Red `#cc0000`** is ONLY for destructive flows. One exception: the
  rating heat bar's bad-zone color stop (`--color-rating-bad`).

## Screen accents

Three screens, three accents (canonical picks from
`tmp/dracula-swatches-v2.html` § B — Section mapping):

| Screen | Accent | Hex | Token |
|---|---|---|---|
| `/` home (dashboard + system) | Dracula Purple | `#bd93f9` | `--accent-home` |
| `/videos` (channels + videos) | Dracula Red | `#ff5555` | `--accent-videos` |
| `/games` (catalog + bundles + footage) | Pale Cobalt | `#7eb6ff` | `--accent-games` |

**Recipe for each screen's chrome:**

- Panel bg: `color-mix(in srgb, <accent> 4%, #282a36)`
- Panel border (focused): `color-mix(in srgb, <accent> 35%, #282a36)`
- Panel title + action color: pure accent hex
- Focus tint on rows / actions: `color-mix(in srgb, <accent> 18%, transparent)`

Exact values: `Pito::Theme::Sections.accent(:home | :videos | :games)`.

**Note on red:** `#ff5555` is the videos screen accent AND looks similar
to the destructive token `#cc0000`. They are NOT the same token. Videos
screen uses `--accent-videos = #ff5555` (Dracula Red — informational,
section identity). Destructive actions still use `--color-danger`
(`#cc0000` light / `#ff5555` dark — value coincides in dark theme but
the semantic is different). On `/videos`, destructive actions are still
gated by `Tui::ConfirmationDialogComponent` so users never mistake an
accent-colored region for a destructive action.

Notes:

- **Omnisearch** (the `:` / everywhere search overlay) is NOT a screen
  — it's a tool. It inherits the home accent regardless of where invoked.
- **Calendar** is a panel inside Home (`Pito::CalendarPanelComponent`).
  When rendered elsewhere (e.g., a lighter-weight calendar variant on a
  game detail screen), it keeps the home accent.
- **Notifications** are a panel inside Home
  (`Pito::NotificationsPanelComponent`). Full detail there. Short form
  accessible via leader menu from any screen.

## Layout chrome

- **TST (Top Status Bar)** — fixed, 22px tall. Components inside:
  - `Tui::AppVersionComponent` — version label
  - `Tui::BreadcrumbComponent` — `<screen> <panel>` or
    `<screen> <panel>:(<sub-panel>)` when sub-panel focused
  - `Tui::SyncIndicatorComponent` — ● synced / ◐ syncing (amber)
  - `Tui::SidekiqStatsComponent` — `b<busy> e<enqueued> r<retry>`
  - `Tui::DateTimeComponent` — live clock
- **BST (Bottom Status Bar)** — fixed, 22px tall. Components inside:
  - mode lozenge (NORMAL / INSERT)
  - sections list — one entry per top-level screen (4 entries)
  - `? help` hint — `?` white, `help` muted, NOT italic
  - `: command` hint — `:` white, `command` muted, NOT italic

Demo: `tmp/demo-status-bar.html`.

## Screens, panels, sub-panels

- **Screen** — corresponds to a URL (`/`, `/videos`, `/games`).
  A screen is a ViewComponent composed of panels.
- **Panel** — a top-level grouping inside a screen
  (`Pito::SecurityPanelComponent` on Home; `Screen::Videos::EditPanelComponent`
  on Videos; etc.). A panel is a ViewComponent composed of sub-panels.
- **Sub-panel** — a section within a panel
  (`Pito::Stack::MeilisearchSubPanelComponent`). A sub-panel composes
  leaf elements: text, inputs, tables, charts, images.

**Home panels are NOT under `Screen::Home::*`** — they live directly
under `Pito::*` since Home is the dashboard + system-monitoring surface
governed by the `Pito::*` namespace, not a separate `Home::*` domain.

Panels carry their **title in the top border** (V4 frame),
section-accent border when focused, muted border otherwise.

A panel may carry an **indicator** (e.g., `connected` / `writable` /
`disconnected`) and one or more **actions** (e.g., `[reindex]`) in the
top-border right cluster.

Demo: `tmp/demo-panel-title.html` (V4 corner-flush picked).

### Panel VC contract (locked per CLAUDE.md)

Every panel VC owns:

- `focusables` method — ordered array of `{key:, style:}` (Ruby contract;
  spec-lockable)
- `CABLE_CHANNEL` constant — `"pito:settings:security"` (canonical
  per channel grammar)
- `keybinds` method — panel-local keybinds (extensions / overrides to
  the global map); resolved through i18n so the TUI consumes the same
- Sub-panel composition — explicit `<%= render Screen::<...>::SubPanelComponent.new(...) %>`
- Data fetched in `initialize` / `before_render` via domain / screen
  services

When you read a panel VC, you should see what data it pulls, where it
broadcasts to, and how it's interacted with — all in one file.

## Dialogs

`<dialog>` element. Top-border title left, top-border `[Esc] to close`
right. Backdrop dim. Dismisses ONLY on `[Esc]` — backdrop click
intentionally captured and ignored. `border-radius: 0`.

Canonical dialog components:

- `Tui::ConfirmationDialogComponent` — destructive confirmations (single
  primary action, no `[cancel]`)
- `Tui::HelpOverlayComponent` — `?` opens this
- `Tui::AlertDialogComponent` — message-only (used by mouse guard)
- `Tui::CommandPaletteComponent` — `:` opens this (V6: vim-line at
  bottom + inline suggestion list above)

Demo: `tmp/demo-command-palette.html` (V6 picked).

## Actions

Every clickable / activatable element renders as `[ label ]`.
Section-accent color. No bold. `cursor: pointer` (suppressed when the
mouse guard is active — cursor is hidden then).

- `BracketedLinkComponent` — `<a>` / `<button type=submit>` shapes
- `Tui::ActionButtonComponent` — bracketed button wired to the action bus

Destructive actions always route through a confirmation dialog. No hover
effects. No focus rings (focus signal = color tint).

## Tables

`.tui-table` grammar:

- **Column alignment: text = left, number / date = right** (header AND
  cells)
- Minimal whitespace
- Sortable headers with arrow indicators (active = solid underline
  section-accent; idle = muted)
- Sort state reflected in URL (`?sessions_sort=device&sessions_dir=asc`)
- No zebra rows
- Hairline `<thead>` bottom border

Sessions table (Home → security panel) is the canonical sortable table.

KV-tables (lighter variant) used in stack sub-panels.

Demo: `tmp/demo-sortable-arrows.html` (V4 picked = solid underline).

## Chips

`Tui::ChipComponent` — colored label, no brackets. Variants: `neutral`
/ `info` / `success` / `warn` / `danger` / `current`.

`current` variant marks the current session in the sessions table
(`[this]`).

Demo: `tmp/demo-chips.html` (V2 picked = colored label, no brackets).

## Checkboxes

`Tui::CheckboxComponent` — `[ ]` and `[x]` glyphs with optional label.

In **INSERT mode**, SPACE on a focused checkbox toggles it. In NORMAL
mode, SPACE opens the leader menu (no checkbox effect).

## Hints

`Tui::HintComponent` — italic, muted, left-aligned. Sits under the row
it explains.

BST hints (`? help`, `: command`) use a different style: NOT italic;
`?` / `:` white; `help` / `command` muted.

## Charts and progress

- `Tui::SparklineComponent` — `▁▂▃▅▇` unicode bars
- `Tui::ProgressBarComponent` — filled `▰▱`-style bar, section-accent aware
- `Tui::SegmentedBarComponent` — Voyage embedding progress (10 segments)
- `Tui::ShadedDensityComponent` — `░▒▓█` fill
- `Tui::HeatmapComponent` — day × hour grid
- `Tui::BarChartComponent` — horizontal bars
- `Tui::PyramidComponent` — demographic split
- `Tui::TreemapComponent` — proportional tiles
- `Tui::ReindexProgressComponent` — `[=------]` animated 9-char width

**HMS (Heat Map Score)** — fixed-color heat bar with hard stops. Used
for recommendations (`Pito::Recommendation::HmsScorer`). Rename from
the legacy `RHM` is pending; will land when we revisit the component.

**TTB (Time To Beat)** — game-screen-specific dynamic heat bar showing
4 metrics in hours: footage / main / extra / completionist.

Demo: `tmp/demo-charts.html`.

## Mode model

- **NORMAL** (default)
  - j / k / ArrowDown / ArrowUp — next / prev focusable
  - Tab / Shift-Tab — next / prev top-level panel
  - Ctrl-h / Ctrl-j / Ctrl-k / Ctrl-l — directional panel move
  - `s` — cycle next sortable column
  - `S` — reverse sort direction
  - `i` — enter INSERT mode
  - SPACE — open leader menu
  - `:` — open command palette
  - `?` — open help dialog
  - Enter — fire the focused action
- **INSERT**
  - Text input editable
  - SPACE — toggle focused checkbox
  - Esc — return to NORMAL

The mode lozenge in BST shows the current mode.

Input focus auto-enters INSERT.

## Keybindings

Shared between web and TUI. **One exception:** `q` quits the TUI; web
has no equivalent.

All other keys (j / k / h / l / Tab / Shift-Tab / Ctrl-h/j/k/l / i /
Esc / SPACE / `?` / `:` / `s` / `S` / Enter) behave identically across
both surfaces.

Leader-prefixed (SPACE → `<key>`) opens the leader menu (which-key style).

Key labels live in `config/locales/keybindings/en.yml`.

Per-panel keybinds live in the panel's VC `keybinds` method, exported
to i18n for TUI sharing.

## Focusables (the cursor model)

Each panel exposes an ordered Ruby array of focusables via its `#focusables`
method. The cursor controller (`tui_cursor_controller.js`) reads
`data-tui-focusable` + `data-tui-focusable-style` attrs and cycles them
with j/k.

Per-style visuals — one `--focus-tint-bg` + `--focus-tint-border` across
all styles via `color-mix(in srgb, var(--section-accent) 18%,
transparent)`:

- `:row` — whole `<tr>` tinted
- `:action` — just the `[label]` link tinted
- `:checkbox_label` — checkbox + label cluster tinted
- `:input` — input border tinted (no full background)

## Mouse guard

Keyboard-only. Real mouse activity (click, select, movement,
viewport-enter) triggers `Tui::AlertDialogComponent` with copy
"mouse interaction forbidden — type ? for help or : for command".

The browser cursor is hidden via `cursor: none !important`.

Real mouse activity filtered by `isTrusted === true` AND `detail >= 1`
AND `pointerType === "mouse"` — so keyboard-fired clicks (Enter on a
focused `[action]`) and programmatic Stimulus `.click()` calls pass
through.

Auto-dismiss on `mouseleave` (cursor exits viewport).

Every action and feature must be operable via keyboard. If a feature
cannot be reached via the keybinding tree, it's a bug.

## Terminology

Use these nouns; never the alternatives:

| Use this | Not this |
|---|---|
| screen | page |
| panel | pane |
| sub-panel | section |
| dialog | modal |
| action | button, link |
| hint | caption, text |

"Page" remains permitted only for paginated result navigation
("page 2 of 5").

## Brand capitalization

Slack, Discord, YouTube, Voyage AI, Meilisearch, PostgreSQL, Redis,
Chrome, Firefox, Safari, Linux, macOS, Windows, Android, iOS.

Non-brand words stay lowercase. All copy via i18n
(`config/locales/**.yml`).

## Visual density rules

- `border-radius: 0` everywhere — no rounded corners
- No hover effects (no color swap, bg shift, transform)
- `line-height: 1` everywhere
- Flat navigation over nested submenus
- ASCII / unicode glyphs over icons / emojis (emojis NOT in code; only
  in chat between user and Claude)
- Tabular numbers (`font-variant-numeric: tabular-nums`)
- White space costs — every panel earns its breathing room

## i18n discipline

All user-visible copy lives in `config/locales/**.yml`. The same YAML
feeds the TUI Rust client. No hardcoded English strings.

Key namespacing:

- `tui.*` for shared TUI / web copy (palette commands, mode labels,
  keybindings)
- `<screen>.*` for screen-specific copy (`settings.*`, `videos.*`,
  `games.*`, `home.*`)
- `actions.*` for confirmation dialog copy

## Demo references

Each visual pick lives in a `tmp/<name>.html` demo. Demo files are
gitignored — they persist locally as the visual reference for future
rewrites.

Currently-relevant demos:

- `tmp/demo-status-bar.html` — TST + BST shape
- `tmp/demo-command-palette.html` — `:` palette V6
- `tmp/demo-chips.html` — chip variants (V2 picked)
- `tmp/demo-charts.html` — chart catalog
- `tmp/demo-sortable-arrows.html` — sortable indicator (V4 picked)
- `tmp/demo-panel-title.html` — V4 corner-flush title
- `tmp/demo-settings-bg-variants.html` — body bg tint per section
