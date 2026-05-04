# Design System

## Typography

- **Font:**
  `ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`
- **Base size:** 13px, line-height 1.4
- **Headings:** h1 18px, h2 14px, h3 13px — all bold
- **Footer:** 11px

### Heading 4

`<h4>` is **not italic by default.** The global `h4` rule sets weight only —
italic is opt-in via class. This is rule 6 of the §10 design refresh.

- `h4.h4-emphasis` — opt-in italic for decorative `<h4>` (admin pages, dashboard
  summaries, sidebars).
- `h4.h4-content` — opt-in marker for user-content `<h4>`. Forces
  `font-style: normal` and `color: var(--color-text)` so user-authored headings
  never inherit a muted or italic style from a surrounding context.

```css
h4.h4-emphasis {
  font-style: italic;
}

h4.h4-content {
  font-style: normal;
  color: var(--color-text);
}
```

### Muted text and weight

`.text-muted` carries an explicit `font-weight: 400` so descendants of bold
containers do not inherit weight. The `.text-muted-bold` utility is the bold
variant — same muted color, weight 700. (Rule 3 of the §10 refresh.)

```css
.text-muted {
  color: var(--color-muted);
  font-weight: 400;
}

.text-muted-bold {
  color: var(--color-muted);
  font-weight: 700;
}
```

### Form hints and captions

`.form-hint` and `.caption` share one visual rule — muted color, italic — but
carry separate names for semantic clarity. Use `.form-hint` for helper text
adjacent to a form input; use `.caption` for empty-state copy, summary captions,
and metric labels. (Rule 4 of the §10 refresh.)

```css
.form-hint,
.caption {
  color: var(--color-muted);
  font-style: italic;
}
```

**Punctuation.** Every hint and caption ends with a `.` (or `?` / `!` if the
sentence calls for it). Single-word labels (`theme`, `engine`, `name`), heading
text, and bracketed-link button labels are NOT statements — they stay
punctuation-free. Numeric stats (`5 selected`, `(123ms)`) and placeholder glyphs
(`—`, `--`) are also not sentences. The lint spec at
`spec/lint/punctuation_spec.rb` catches drift on every test run by walking every
ERB template under `app/views/` and `app/components/` and asserting each
`.form-hint` / `.caption` text ends with sentence-terminating punctuation.

### Content Rules

User content is **never muted, never italic.** The global `h4` italic rule was
removed because it leaked into user-authored markdown. User content `<h4>` flows
through `.h4-content` (forces normal weight + default text color). Decorative
`<h4>` (admin pages, dashboards, summaries) flows through `.h4-emphasis` if
italic is intentional. The default bare `<h4>` is non-italic.

This rule generalises: utility classes that imply muted-or-italic styling
(`.text-muted`, `.form-hint`, `.caption`) belong on chrome (helper text,
captions, timestamps, secondary labels) — never wrapped around user-typed prose,
note bodies, descriptions, or anything an end user authored.

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
  `<span class="bracketed-active">[label]</span>` — bold, not a link, text in
  `var(--color-text-bold)`. Component cleanup #2 of the §10 refresh replaced the
  previous inline `style="font-weight: bold;"` with the `.bracketed-active`
  utility so theme switches reach the active label.
- **Destructive:** adds `text-danger` class (danger color)

```css
.bracketed-active {
  font-weight: 700;
  color: var(--color-text-bold);
}
```

- **Labels:** use the shortest clear verb — `[save]` not `[save view]`,
  `[delete]` not `[delete saved view]`
- **Separator dots:** use `<span class="text-muted">&middot;</span>` between
  adjacent bracketed links

### Keycaps

Keyboard shortcut indicators use `(key)` style via `.keycap` CSS class:

- Parentheses generated via `::before`/`::after` pseudo-elements
- Bold, **purple** (`--color-keycap` — `#6f42c1` in light, `#bd93f9` in dark),
  pointer cursor — distinct from link blue so shortcuts don't compete with
  action links visually
- Hover lifts to `--color-keycap-hover`
- Theme toggle keycap opts into theme-aware bg-tone colors (`.keycap-theme`) on
  the navbar `(n)` toggle specifically; all other keycaps fall through to
  `--color-keycap`

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

### Header / body weight contrast

Rule 7 of the §10 design refresh inverts the conventional table weight pattern:
**headers are muted + bold, body cells are default text + regular weight.** This
makes the data row the visual focus of the table and the column labels recede
into chrome. The selectors are scoped to `thead th` / `tbody td` so any custom
`<th>` inside a `<tbody>` (rare, but happens for row headers) is not pulled
muted by accident.

```css
thead th {
  color: var(--color-muted);
  font-weight: 700;
}

tbody td {
  color: var(--color-text);
  font-weight: 400;
}
```

## Numbers

All user-facing numbers are formatted with comma-separated thousands and
dot-decimal — `123,456,789` and `1,234.5`. This applies app-wide: counts,
durations in tables, dashboard subtitles, indexed-document tallies, chart axis
labels (where Chartkick options allow), every place a raw integer or float
renders as text.

**Rendering:** use Rails' `number_with_delimiter` helper. Default locale
delimiter is `,` and separator is `.`, which matches the rule.

```erb
<%= number_with_delimiter(@video_count) %>
<td class="num"><%= number_with_delimiter(video.total_views) %></td>
```

**Layout:** numeric `<td>` cells use `class="num"` for right-aligned tabular
numerals (`text-align: right; font-variant-numeric: tabular-nums`). The
formatting rule and the layout rule are independent — `.num` aligns the column,
`number_with_delimiter` formats the value. Both apply together for table cells;
only `number_with_delimiter` applies for inline prose.

**Anti-pattern:** rendering raw `<%= count %>` for a value the user reads.
Always wrap with the helper. Counts that ALWAYS fit in two digits (e.g. "max
panes: 5", "rows per page: 20") may render raw — but if there's any chance the
value crosses 1,000, format it.

**Charts.** Chartkick calls pass `thousands: ","` so axis labels AND tooltips
render with the same comma-separator convention. `decimal: "."` is the default;
only set it explicitly if a future chart configures a non-default locale.
Chartkick pushes the format into Chart.js's tick callback + tooltip label
callback automatically — no per-chart Chart.js plumbing needed.

```erb
<%= line_chart @daily_views, thousands: "," %>
<%= bar_chart top_videos, thousands: "," %>
```

Apply to every Chartkick chart in the app — dashboard, future per-channel
charts, future per-project metrics. Lint coverage: a future spec or RuboCop cop
should reject `bar_chart` / `line_chart` / `column_chart` / `area_chart` /
`pie_chart` calls in ERB without a `thousands:` option, mirroring the
`number_with_delimiter` lint spec at `spec/lint/numeric_formatting_spec.rb`.

## Forms

### Form Fields

- **Component:** `FormFieldComponent` — handles label, input, and per-field
  error display
- Supports types: `:text_field`, `:text_area`, `:select`, `:collection_select`
- **Labels:** bold, block display, 2px bottom margin — emit via the
  `.form-label` utility (component cleanup #3 of the §10 refresh) instead of an
  inline `style=` attribute. `FormFieldComponent` writes `class: "form-label"`
  on the rendered `<label>`.
- **Inputs:** full width, 1px solid border (`--color-input-border`), 2px
  border-radius
- **Error state:** red border (`--color-danger`) on invalid field, red error
  text below (12px). The error-state inline `border-color` on the input is
  intentionally preserved — errors are not hints and don't share the muted
  treatment.
- **Flash error:** "couldn't create" or "couldn't update" depending on context
- Form partials (`_form.html.erb`) shared between new and edit views
- Form container: `max-width: 480px`
- Submit + cancel: flex row with 6px gap — `[save]` button + `[cancel]` link

```css
.form-label {
  display: block;
  margin-bottom: 2px;
  font-weight: 700;
}
```

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

**Pane sizing.** Every `.pane-wrapper` is a fixed 454px wide on desktop
(`flex: 0 0 454px`). When the viewport can't fit pane-count × 454px, the
`.pane-container` engages horizontal scroll. On mobile (≤768px) the pane width
drops to `88vw` with `scroll-snap-type: x mandatory`, one pane per viewport.

**Pane zebra.** Multi-pane surfaces alternate background colours via
`.pane-container > .pane-wrapper:nth-child(even) { background-color: var(--color-bg-alt); }`.
Single-pane surfaces inherit the page background (no zebra). Apply the same
`.pane-container` parent wherever a multi-pane layout is used — settings,
project show, channels/videos saved-views — so the zebra rule fires
automatically.

### Mobile

Phase 4 §9.2 replaced the original column-stack behavior with a **horizontal
scroll-snap carousel.** The previous "stack panes vertically below 768px" rule
is gone — on mobile the panes stay in a horizontal row and the row scrolls
horizontally, snapping one pane at a time into view.

- Each pane gets `min-width: 88vw` and `flex: 0 0 88vw` so a sliver of the next
  pane peeks in at the right edge as a scroll affordance.
- The pane row gets `scroll-snap-type: x mandatory`; each pane gets
  `scroll-snap-align: start`.
- Pure CSS — no Stimulus controller. Native scroll-snap on iOS Safari, Android
  Chrome, and desktop browsers is sufficient.
- Reorder arrows still adapt per breakpoint — desktop ◀ ▶ at the divider edges,
  mobile arrows hidden inside the snap row (reorder via the `[ panes ]` dialog
  instead).

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
- Panes scroll horizontally with `scroll-snap-type: x mandatory` (see Panes →
  Mobile above; Phase 4 §9.2 retired the previous vertical-stack rule)
- Saved-views lists scroll horizontally on every breakpoint (see Saved Views
  below)
- Dashboard charts go full width

## Saved Views

The saved-views row sits at the top of every list page that supports saving a
workspace URL. Phase 4 §9.3 promoted the row to a **horizontal scroll layout at
every breakpoint** — desktop and mobile alike. The row no longer wraps onto a
second line; it scrolls horizontally and clips overflow with a fading edge cue.

- `.saved-views-list` — flex row, `flex-wrap: nowrap`, `overflow-x: auto`,
  scroll-snap optional. Outer container.
- `.saved-views-row` — the inner item track. Each saved-view label sits in this
  row as a `[ label ]` bracketed link plus a separator dot.

This rule is global — it overrides any per-page styling that previously allowed
the row to wrap. The component (`SavedViewsSectionComponent`) emits both
classes; pages that compose saved-views inline must use the same shape.

## Dashboard Charts

Chart colors **never** use inline hex literals. The dashboard reads its palette
from `ApplicationHelper#chart_palette(count)` which slices the
`ApplicationHelper::CHART_PALETTE` constant — the same source the CSS
`--color-chart-N` variables track. Add a chart, call `chart_palette(N)`; do not
hardcode hex values in the view.

The §10 design refresh migrated four chart-call hex literals in
`app/views/dashboard/index.html.erb` to `chart_palette(N)`. Future dashboard
chart additions follow the same convention so a theme switch or palette
extension lands in one place.

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
