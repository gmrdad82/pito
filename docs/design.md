# Design System

## Typography

- **Font:** `ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`
- **Base size:** 13px, line-height 1.4
- **Headings:** h1 18px, h2 14px, h3 13px — all bold
- **Footer:** 11px

## Colors

All colors are defined as CSS custom properties in `app/assets/tailwind/application.css`. Components and views must use `var(--color-xxx)` — never hardcode hex values in inline styles or templates.

### Light Theme (`:root`)

| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | #ffffff | Page background |
| `--color-bg-alt` | #fafafa | Alternating table rows |
| `--color-bg-hover` | #f0f0f0 | Row hover |
| `--color-bg-header` | #f4f4f4 | Table headers |
| `--color-text` | #1a1a1a | Body text |
| `--color-text-bold` | #1a1a1a | Headings, active nav |
| `--color-link` | #0000cc | Links, actions, buttons |
| `--color-link-hover` | #0000ff | Link hover |
| `--color-danger` | #cc0000 | Destructive actions only |
| `--color-muted` | #555555 | Secondary text, timestamps |
| `--color-border` | #dddddd | Table borders, dividers |
| `--color-success` | #2e7d32 | Positive indicators |

### Dark Theme (`[data-theme="dark"]`) — Dracula-inspired

| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | #282a36 | Page background (Dracula background) |
| `--color-bg-alt` | #21222c | Alternating rows (darker) |
| `--color-bg-hover` | #44475a | Row hover (Dracula current line) |
| `--color-bg-header` | #343746 | Table headers |
| `--color-text` | #f8f8f2 | Body text (Dracula foreground) |
| `--color-text-bold` | #f8f8f2 | Headings, active nav |
| `--color-link` | #bd93f9 | Links, actions (Dracula purple) |
| `--color-link-hover` | #d4b8ff | Link hover (lighter purple) |
| `--color-danger` | #ff5555 | Destructive actions (Dracula red) |
| `--color-muted` | #6272a4 | Secondary text (Dracula comment) |
| `--color-border` | #44475a | Borders (Dracula current line) |
| `--color-success` | #50fa7b | Positive indicators (Dracula green) |

### Chart Colors

Chart colors adapt to the theme via `--color-chart-N` CSS variables:

| Slot | Light | Dark | Dracula name |
|------|-------|------|-------------|
| `--color-chart-1` | #0000cc (blue) | #bd93f9 (purple) | Purple |
| `--color-chart-2` | #2e7d32 (green) | #50fa7b (green) | Green |
| `--color-chart-3` | #8b5cf6 (purple) | #ff79c6 (pink) | Pink |
| `--color-chart-4` | #d97706 (amber) | #ffb86c (orange) | Orange |
| `--color-chart-5` | #0891b2 (cyan) | #8be9fd (cyan) | Cyan |

Chart grid lines: `--color-chart-grid` (#eeeeee light, #44475a dark)
Tooltip: `--color-tooltip-bg` / `--color-tooltip-text` adapt per theme.

### Color Rules

- **Red is reserved for destructive/dangerous operations only.** Never use red in charts, indicators, or decorative elements. Red signals "this action is irreversible or harmful."
- Charts use the `--color-chart-N` palette. If more colors are needed, extend with non-red colors.
- All inline styles must use CSS variables, not hex values, for theme compatibility.

## Dark Mode

- Toggle button in navbar: `[ dark ]` / `[ light ]` — shows the opposite of current theme
- Three-value AppSetting: `light`, `dark`, `auto` (match system)
- Priority: localStorage > server AppSetting > system preference
- Flash prevention: inline `<script>` in `<head>` applies theme before body renders
- Theme controller: `app/javascript/controllers/theme_controller.js` (Stimulus)
- Chart recoloring: `window.recolorCharts()` called after theme toggle, reads CSS vars
- Server persistence: `PATCH /settings/theme` via fetch

## Interactive Elements

### Bracketed Links / Buttons

All clickable elements use the `[ label ]` convention:
- **Linked:** `<a class="bracketed">[ <span class="bl">label</span> ]</a>` — theme link color, bold
- **Active (current page):** `<span style="font-weight: bold; color: var(--color-text-bold);">[ label ]</span>` — bold, not a link
- **Destructive:** adds `text-danger` class (danger color)
- **Labels:** use the shortest clear verb — `[ save ]` not `[ save view ]`, `[ delete ]` not `[ delete saved view ]`

### Cursor

- All clickable elements must show `cursor: pointer` — links, buttons, submit buttons, chart legends, checkboxes
- Non-interactive elements use default cursor

### Chart Legends

- Legends use bracketed label style: `[ likes ]`, `[ comments ]`
- **Active (visible):** bold, colored in the dataset's chart color, `cursor: pointer`
- **Hidden (toggled off):** bold, bracketed, muted color (`--color-muted`), `cursor: pointer`
- No color boxes/swatches — the colored text itself indicates the series
- Clicking toggles dataset visibility (Chart.js default behavior)
- Font weight set globally via `Chart.defaults.plugins.legend.labels.font`

## Charts

- **Animation:** disabled (snappy rendering)
- **Font:** same monospace as site, 11px
- **Line width:** 1.5px, point radius 0 (hover radius 8)
- **Legend:** bottom position, bracketed labels (see above)
- **Crosshair:** vertical dashed hairline on hover with colored dots at intersections (line charts only, opt-out with `plugins: { crosshair: false }`)
- **Synced crosshair:** charts in the same `data-sync-group` share hover position. Dashboard syncs daily views, views by channel, and daily engagement.
- **Tooltip:** shows all datasets at hovered x position (`interaction.mode: "index"`)
- **Colors:** never red. Use `--color-chart-N` variables. JS `recolorCharts()` applies them after render and on theme toggle.
- **Grid lines:** use `--color-chart-grid` for theme adaptation
- **Tooltip styling:** uses `--color-tooltip-bg` and `--color-tooltip-text`

## Layout

- Full width for data-heavy pages (videos), constrained for sparse pages (channels: 900px, forms: 480px)
- No shadows, gradients, rounded corners
- No icon fonts — HTML entities only (▲ ▼ ◀ ▶ − + ×)
- Header: fixed, 32px height, theme toggle on right
- Multi-column: flex-wrap with min-width for responsive stacking
- Dashboard: 2-column flex layout with 400px min-width per column

## Aesthetic

Craigslist / 2000s tool aesthetic with modern build. Dense, information-rich, no decoration. Every pixel serves a purpose. Dark mode inspired by Dracula theme.
