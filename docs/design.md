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
- **Bold is earned, not attributed.** Only the screen identifier in TST,
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
- Borders: screen-accent-tinted hairline (1px)
- Background: panel bg + sub-panel bg with subtle delta
- **Red `#cc0000`** is ONLY for destructive flows. One exception: the
  rating heat bar's bad-zone color stop (`--color-rating-bad`).

## Screen accents

Three screens, three accents (canonical picks from
`tmp/dracula-swatches-v2.html` § B — Screen mapping):

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

**Section background recipe (canonical):** every screen's background is
`color-mix(in srgb, <section accent hex> 4%, #282a36)`, with the focused
border at 35% and the focus tint at 18% of the same accent. Exported by
`Pito::Theme::Sections` into `_theme.css` and the Rust client's
`extras/cli/src/theme.rs`. The `settings` value is a frozen historical
override (`#34333b`) preserved via `USER_LOCKED_BG`.

Exact values: `Pito::Theme::Sections.accent(:home | :videos | :games)`.

**Note on red:** `#ff5555` is the videos screen accent AND looks similar
to the destructive token `#cc0000`. They are NOT the same token. Videos
screen uses `--accent-videos = #ff5555` (Dracula Red — informational,
screen identity). Destructive actions still use `--color-danger`
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
  - screens list — one entry per top-level screen (4 entries)
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
screen-accent border when focused, muted border otherwise.

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
Screen-accent color. No bold. `cursor: pointer` (suppressed when the
mouse guard is active — cursor is hidden then).

- `BracketedLinkComponent` — `<a>` / `<button type=submit>` shapes
- `Tui::ActionButtonComponent` — bracketed button wired to the action bus
- `Tui::ActionComponent` — generic bracketed action for forms and local Stimulus
  wiring. Kwargs: `label:`, `as:` (`:submit` / `:button` / `:link`, default
  `:button`), `href:` (when `as: :link`), `data:` (hash of Stimulus attrs),
  `destructive:` (bool, adds `.text-danger`). Does NOT require an ActionRegistry
  entry — use for auth forms, copy triggers, any non-bus action.

Destructive actions always route through a confirmation dialog. No hover
effects. No focus rings (focus signal = color tint).

### Actions are always section accent color (locked 2026-05-24)

Every bracketed action — `[reindex]`, `[resync]`, `[schedule]`, `[month]`,
`[update]`, `[help]`, `[ ] sync` / `[x] sync` / `[-] sync` / `[!] sync`,
the reindex progress slot — paints in `var(--section-accent)`. Idle,
active, hovered, or otherwise: actions speak the section's accent voice.
Non-action chrome (titles, hints, delimiters, muted labels) keeps its own
token.

One exception: the `[!] sync` disconnected state renders in red
`var(--color-danger)`.

### Bracket-to-space rule on TST chrome (locked 2026-05-24)

Where a non-action label sits in an actions slot adjacent to a bracketed
action, use a literal space pair around the label instead of brackets —
`month [schedule]` not `[month] [schedule]`. Brackets mean "this is an
action"; bare labels with surrounding spaces are static chrome. Avoids
a color rainbow across multiple bracketed items and keeps the
"brackets = action" reading unambiguous.

When the mode flips (e.g. user activates `[schedule]`), labels swap roles:
`[month] schedule` — `[month]` becomes the bracketed action, `schedule`
becomes the static label.

## Tables

`.tui-table` grammar:

- **Column alignment: text = left, number / date = right** (header AND
  cells)
- Minimal whitespace
- Sortable headers with arrow indicators (active = solid underline
  screen-accent; idle = muted)
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
it explains. Kwargs: `text:`, `severity:` (`:muted` default / `:danger` for
error messages — adds `.text-danger` to render in `var(--color-danger)`).

BST hints (`? help`, `: command`) use a different style: NOT italic;
`?` / `:` white; `help` / `command` muted.

## Code blocks

`Tui::CodeComponent` — bordered monospace command display. Uses the existing
`.code-block` + `.code-block code` CSS rules. Kwargs: `text:` (required),
`copyable:` (bool, default `false`), `copied_message:` (label flashed after
copy, default `"copied!"`), `copy_label:` (action label, default `"copy"`).
When `copyable: true`, composes `Tui::ActionComponent` wired to the
`clipboard-copy` Stimulus controller. No new CSS classes.

## Segmented code inputs

`Tui::TotpCodeComponent` — unified segmented-box input replacing the former
`TotpCodeInputComponent` (6-digit) and `Pito::BackupCodeInputComponent`
(8-char). Kwargs: `field:`, `mode:` (`:digits` 6-numeric / `:backup`
8-alphanumeric, default `:digits`), `autofocus:`, `hidden:`, `data:` (extra
data attrs on the wrapper). Stimulus controller: `tui-totp-code`
(tui_totp_code_controller.js). Mode `:digits` auto-submits on full entry;
mode `:backup` does not. Both modes share identical UX (distribute paste,
arrow nav, backspace step, hidden field sync).

## Charts and progress

- `Tui::SparklineComponent` — `▁▂▃▅▇` unicode bars
- `Tui::ProgressBarComponent` — filled `▰▱`-style bar, screen-accent aware
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

## Transitions

The project ships **exactly 2 transition effects** plus 1 continuous
decoration. Web and TUI share names, tokens, and shape — same canonical
contract on both surfaces.

### The 2 canonical effects

- **`scramble-settle`** — content transitions (text, numbers, words).
  When a value changes A → B, each character position cycles through
  3–5 random characters for ~200ms (staggered per-character), then
  settles on the B character. Web: JS `setInterval` ticks updating each
  cell's text. TUI: same pattern via Ratatui's per-frame redraw.
- **`color-crossfade`** — color transitions. Animates the `color` CSS
  property from color A to color B over 300ms ease-out. Web: CSS
  transition on `color`. TUI: per-frame ANSI color interpolation
  between the two named colors via the Ratatui truecolor path.

### The shimmer decoration (not a transition)

- **`shimmer`** — used ONLY on `Tui::SyncIndicatorComponent` while in
  the `syncing` state. CSS gradient sweep across text via
  `background-clip: text` + animated `background-position`. TUI parity:
  per-character truecolor foregrounds interpolating between muted +
  accent over a moving offset. Continuous, not state-driven; stops the
  moment `syncing` flips off.

### Token contract

| Token | Value | Scope |
|---|---|---|
| scramble-settle duration | 200ms | per-character window |
| scramble-settle stagger | 30ms | between adjacent characters |
| scramble-settle frame | ~30ms | between scramble ticks |
| color-crossfade duration | 300ms | full transition |
| color-crossfade easing | ease-out | |
| shimmer cycle | 1.6s linear infinite | |
| shimmer gradient | muted 0%, muted 40%, accent 50%, muted 60%, muted 100% | |
| debounce | 80ms | collapse rapid value changes |

Tokens exported by `Pito::Transitions::Tokens` (see
`docs/architecture.md` § Canonical namespace taxonomy) into CSS custom
properties + Rust `theme.rs`. Single source of truth.

### Reduced motion

`prefers-reduced-motion: reduce` skips all animations — content swaps
instantly, colors swap instantly, shimmer does not run. Single global
gate at the controller level (`tui_transition_controller.js`); no
per-VC opt-out, no per-effect override.

### Composition

An element may opt into both effects simultaneously. Canonical example:
`Tui::SidekiqStatsComponent` runs `scramble-settle` on the number
while a `color-crossfade` re-tints the color when a threshold crosses.
The two effects compose cleanly because they target different CSS
properties (text content vs. `color`).

### TUI parity

Web + TUI use the same effect names, same tokens, same shape. The
Ratatui client reads tokens from the exported `theme.rs` and runs the
same per-frame logic. New effects require an explicit registry entry in
`Pito::Transitions::Effects` AND a parity spec — no silent additions.

### How VCs opt in

VCs do NOT type raw data-attrs. They include `Tui::Transitionable` and
call its helper to emit the canonical data-attr set consumed by the
single Stimulus controller `tui_transition_controller.js`.

Demo reference: `tmp/cable-vc-transitions-v2.html` — visual lock for
all 3 cable VCs (sync indicator, date time, sidekiq stats) using the
2 effects + the shimmer decoration.

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

### Spatial Ctrl-hjkl navigation (locked 2026-05-23)

When the user presses Ctrl-h / Ctrl-j / Ctrl-k / Ctrl-l, the
`tui_cursor_controller` picks the next panel based on each panel's
`getBoundingClientRect()`. The algorithm is **purely geometric** — it
does not look at DOM order, panel index, sub-panel structure, or any
other domain hint. The 4 steps:

1. **Direction gate.** A candidate panel must lie in the requested
   direction relative to the focused panel's center:
   - Ctrl-h (left):  `candidate.center.x < focused.center.x`
   - Ctrl-l (right): `candidate.center.x > focused.center.x`
   - Ctrl-k (up):    `candidate.center.y < focused.center.y`
   - Ctrl-j (down):  `candidate.center.y > focused.center.y`

   A 1-pixel epsilon (`> 1` / `< -1`) defends against floating-point
   noise on perfectly co-linear centers.

2. **Score each surviving candidate.**
   - `primary`   = absolute distance along the direction axis
   - `secondary` = absolute distance along the orthogonal axis
   - `score = primary * 3 + secondary`
   - Lower score wins.

3. **Tiebreak by DOM order.** If two candidates score identically, the
   one that appears first in `panelTargets` (document order) wins.

4. **No edge wrap.** If no candidate survives the direction gate, the
   focus stays put — vim convention; the user can mash Ctrl-j at the
   bottom edge without falling off.

The **3:1 primary weighting** ensures the IMMEDIATE next row/column
always wins over a far-away panel with better orthogonal alignment.
Worked example (Home screen, 8 panels):

- From `games-releases` (row 1, col 3), Ctrl-j must reach `calendar`
  (row 2, ~60% column) — even though `notifications-settings`
  (row 3, right column) is almost perfectly column-aligned. Calendar
  is in the next row; primary*3 dominates.
- From `notifications-settings` (row 3 right), Ctrl-k reaches
  `calendar` (row 2 right). Symmetric with the down case.
- From `calendar` (row 2 right), Ctrl-k reaches `games-releases`
  (row 1 col 3) — DOM-order tiebreaks against `latest-videos` since
  both row-1 panels are equidistant by primary.

**Same algorithm runs in Ratatui** (TUI parity): panel `Rect`
positions are fed through the same scoring formula. New screens
inherit correct spatial nav for free — no per-screen hardcoding.

Truth table + Ruby port live in
`spec/javascript/tui_cursor_spatial_nav_spec.rb`.

## Focusables (the cursor model)

Each panel exposes an ordered Ruby array of focusables via its `#focusables`
method. The cursor controller (`tui_cursor_controller.js`) reads
`data-tui-focusable` + `data-tui-focusable-style` attrs and cycles them
with j/k.

Per-style visuals — one `--focus-tint-bg` + `--focus-tint-border` across
all styles via `color-mix(in srgb, var(--screen-accent) 18%,
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
Sidekiq, Chrome, Firefox, Safari, Linux, macOS, Windows, Android, iOS.

Non-brand words stay lowercase. All copy via i18n
(`config/locales/**.yml`).

**Proper nouns inside formatted strings are capitalized.** Weekday
abbreviations Sun–Sat and month abbreviations Jan–Dec are proper nouns
and always Title Case. Everything else in UI copy stays lowercase:
screen labels, action labels, mode words, sync states, breadcrumb
segments, headings.

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
- `tmp/demo-settings-bg-variants.html` — body bg tint per screen
- `tmp/cable-vc-transitions-v2.html` — `scramble-settle` +
  `color-crossfade` + `shimmer` visual lock (see § Transitions)
