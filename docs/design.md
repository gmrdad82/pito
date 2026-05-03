# Design System

## Typography

- **Font:**
  `ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`
- **Base size:** 13px, line-height 1.4
- **Headings:** h1 18px, h2 14px, h3 13px — all bold
- **Footer:** 11px

## Colors

All colors are defined as CSS custom properties in
`app/assets/tailwind/application.css`. Components and views must use
`var(--color-xxx)` — never hardcode hex values in inline styles or templates.

### Light Theme (`:root`)

| Token                | Value   | Usage                      |
| -------------------- | ------- | -------------------------- |
| `--color-bg`         | #ffffff | Page background            |
| `--color-bg-alt`     | #fafafa | Alternating table rows     |
| `--color-bg-hover`   | #f0f0f0 | Row hover                  |
| `--color-bg-header`  | #f4f4f4 | Table headers              |
| `--color-text`       | #1a1a1a | Body text                  |
| `--color-text-bold`  | #1a1a1a | Headings, active nav       |
| `--color-link`       | #0000cc | Links, actions, buttons    |
| `--color-link-hover` | #0000ff | Link hover                 |
| `--color-danger`     | #cc0000 | Destructive actions only   |
| `--color-muted`      | #555555 | Secondary text, timestamps |
| `--color-border`     | #dddddd | Table borders, dividers    |
| `--color-success`    | #2e7d32 | Positive indicators        |

### Dark Theme (`[data-theme="dark"]`) — Dracula-inspired

| Token                | Value   | Usage                                |
| -------------------- | ------- | ------------------------------------ |
| `--color-bg`         | #282a36 | Page background (Dracula background) |
| `--color-bg-alt`     | #21222c | Alternating rows (darker)            |
| `--color-bg-hover`   | #44475a | Row hover (Dracula current line)     |
| `--color-bg-header`  | #343746 | Table headers                        |
| `--color-text`       | #f8f8f2 | Body text (Dracula foreground)       |
| `--color-text-bold`  | #f8f8f2 | Headings, active nav                 |
| `--color-link`       | #bd93f9 | Links, actions (Dracula purple)      |
| `--color-link-hover` | #d4b8ff | Link hover (lighter purple)          |
| `--color-danger`     | #ff5555 | Destructive actions (Dracula red)    |
| `--color-muted`      | #6272a4 | Secondary text (Dracula comment)     |
| `--color-border`     | #44475a | Borders (Dracula current line)       |
| `--color-success`    | #50fa7b | Positive indicators (Dracula green)  |

### Chart Colors

Chart colors adapt to the theme via `--color-chart-N` CSS variables:

| Slot              | Light            | Dark             | Dracula name |
| ----------------- | ---------------- | ---------------- | ------------ |
| `--color-chart-1` | #0000cc (blue)   | #bd93f9 (purple) | Purple       |
| `--color-chart-2` | #2e7d32 (green)  | #50fa7b (green)  | Green        |
| `--color-chart-3` | #8b5cf6 (purple) | #ff79c6 (pink)   | Pink         |
| `--color-chart-4` | #d97706 (amber)  | #ffb86c (orange) | Orange       |
| `--color-chart-5` | #0891b2 (cyan)   | #8be9fd (cyan)   | Cyan         |

Chart grid lines: `--color-chart-grid` (#eeeeee light, #44475a dark) Tooltip:
`--color-tooltip-bg` / `--color-tooltip-text` adapt per theme.

### Color Rules

- **Red is reserved for destructive/dangerous operations only.** Never use red
  in charts, indicators, or decorative elements. Red signals "this action is
  irreversible or harmful."
- Charts use the `--color-chart-N` palette. If more colors are needed, extend
  with non-red colors.
- All inline styles must use CSS variables, not hex values, for theme
  compatibility.

## Dark Mode

- Toggle: `(n)` keycap in navbar — Dracula bg color in light mode, white in dark
  mode
- Keyboard shortcut: press `n` to toggle (disabled in inputs/textareas)
- Three-value AppSetting: `light`, `dark`, `auto` (match system)
- Priority: localStorage > server AppSetting > system preference
- Flash prevention: inline `<script>` in `<head>` applies theme before body
  renders
- Theme controller: `app/javascript/controllers/theme_controller.js` (Stimulus)
- Chart recoloring: `window.recolorCharts()` called after theme toggle, reads
  CSS vars
- Server persistence: `PATCH /settings/theme` via fetch

## Keyboard Shortcuts

- `n` — toggle dark/light theme
- `/` — focus search input
- `?` — show keyboard shortcuts dialog
- All shortcuts disabled when typing in inputs, textareas, selects, or
  contenteditable

## Interactive Elements

### Bracketed Links / Buttons

All clickable elements use the `[label]` convention (no spaces inside brackets):

- **Component:** `BracketedLinkComponent` — use this instead of inline HTML
- **Linked:** renders `<a class="bracketed">[<span class="bl">label</span>]</a>`
  — theme link color, bold
- **Active (current page):** renders
  `<span style="font-weight: bold;">[label]</span>` — bold, not a link
- **Destructive:** adds `text-danger` class (danger color)
- **Labels:** use the shortest clear verb — `[save]` not `[save view]`,
  `[delete]` not `[delete saved view]`
- **Separator dots:** use `<span class="text-muted">&middot;</span>` between
  adjacent bracketed links

### Keycaps

Keyboard shortcut indicators use `(key)` style via `.keycap` CSS class:

- Parentheses generated via `::before`/`::after` pseudo-elements
- Bold, link-colored, pointer cursor
- Theme toggle keycap uses theme-aware colors (`.keycap-theme`)

### Checkboxes

Markdown-style checkboxes via `CheckboxComponent`:

- Unchecked: `[ ]`, Checked: `[x]`, Indeterminate: `[-]`
- Hidden native `<input>`, styled via `.md-check-indicator::before`
- Optional muted label via `.md-check-label`

### Cursor

- All clickable elements must show `cursor: pointer` — links, buttons, submit
  buttons, chart legends, checkboxes
- Non-interactive elements use default cursor

### Chart Legends

- Legends use bracketed label style: `[likes]`, `[chats]`
- **Active (visible):** bold, colored in the dataset's chart color,
  `cursor: pointer`
- **Hidden (toggled off):** bold, bracketed, muted color (`--color-muted`),
  `cursor: pointer`
- No color boxes/swatches — the colored text itself indicates the series
- Clicking toggles dataset visibility (Chart.js default behavior)

## Tables

### Column Headers

Short labels for compact display:

| Data                                        | Header    |
| ------------------------------------------- | --------- |
| subscribers                                 | subs      |
| connected/OAuth                             | OAuth     |
| comments                                    | chats     |
| watch time                                  | watch     |
| privacy status                              | state     |
| published date                              | date      |
| duration                                    | length    |
| title, channel, views, likes, trend, videos | unchanged |

### Sortable Headers

- **Component:** `SortableHeaderComponent` — renders `<th>` with sort data
  attributes
- Sort arrows (▲▼) positioned absolutely at the right edge of the cell, touching
  the column separator
- Active sort shows single arrow (▲ or ▼)
- Tables use `width: auto` — no unnecessary whitespace

### Table Layout

- `border-collapse: collapse`, 13px font
- `width: auto` — tables hug their content
- Header background: `--color-bg-header`
- Alternating row colors: `--color-bg-alt`
- Hover: `--color-bg-hover`
- `white-space: nowrap` on all cells

## Forms

### Form Fields

- **Component:** `FormFieldComponent` — handles label, input, and per-field
  error display
- Supports types: `:text_field`, `:text_area`, `:select`, `:collection_select`
- **Labels:** bold, block display, 2px bottom margin
- **Inputs:** full width, 1px solid border (`--color-input-border`), 2px
  border-radius
- **Error state:** red border (`--color-danger`) on invalid field, red error
  text below (12px)
- **Flash error:** "couldn't create" or "couldn't update" depending on context
- Form partials (`_form.html.erb`) shared between new and edit views
- Form container: `max-width: 480px`
- Submit + cancel: flex row with 6px gap — `[save]` button + `[cancel]` link

### Flash Messages

- Simple, non-formal language
- Success: "channel created.", "video updated.", "settings saved."
- Error: "couldn't create — check the fields below.", "couldn't update — check
  the fields below."
- Notices: blue-tinted background, errors: red-tinted background

## Panes (Multi-item View)

### Desktop

- Side-by-side flex layout with 2px solid vertical dividers
- Reorder arrows: ◀ ▶ positioned at divider edges

### Mobile

- Stacked vertically with 1px hairline separator, 20px gap
- Reorder arrows: ▼ (upper pane, tip down) and ▲ (lower pane, tip up) — centered
  horizontally, tip-to-tip on the hairline
- Desktop arrows (◀ ▶) hidden on mobile, mobile arrows (▲ ▼) hidden on desktop

## Layout

- Full width for data-heavy pages (videos), constrained for sparse pages
  (channels: 900px, forms: 480px)
- No shadows, gradients, rounded corners
- No icon fonts — HTML entities only (▲ ▼ ◀ ▶ − + ×)
- Header: fixed, 32px height, `(n)` keycap theme toggle on right
- Multi-column: flex-wrap with min-width for responsive stacking
- Dashboard: 2-column flex layout with 400px min-width per column

## Mobile Responsiveness

- `.hide-mobile` — hidden below 768px (home nav link, search button, copyright
  text)
- `.show-mobile` — shown only below 768px
- Search input shrinks to 180px on mobile
- Tables get horizontal scroll
- Panes stack vertically with reorder arrows adapted
- Dashboard charts go full width

## ViewComponents

All reusable UI elements are ViewComponents with specs:

| Component                    | Purpose                                            |
| ---------------------------- | -------------------------------------------------- |
| `BracketedLinkComponent`     | `[label]` links and active states                  |
| `BreadcrumbComponent`        | Breadcrumb navigation with `/` separators          |
| `CheckboxComponent`          | Markdown-style `[ ]`/`[x]`/`[-]` checkboxes        |
| `ChartToolbarComponent`      | Range selector (7d, 30d, 90d, 1y, all)             |
| `FormFieldComponent`         | Form fields with labels, inputs, and error display |
| `SavedViewsSectionComponent` | Saved views dialog trigger and list                |
| `SortableHeaderComponent`    | Table `<th>` with sort arrows and data attributes  |
| `StatusIndicatorComponent`   | Trend indicators (▲ ▼ —)                           |

## Aesthetic

Craigslist / 2000s tool aesthetic with modern build. Dense, information-rich, no
decoration. Every pixel serves a purpose. Dark mode inspired by Dracula theme.
