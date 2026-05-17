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
- **Exception — failure-state banners.** Red is permitted for failure-state
  banners (e.g., the `needs_reauth` Google identity banner introduced in Phase
  7). Failure states are conceptually adjacent to destructive/dangerous outcomes
  — they signal "something is wrong and your action is required to recover."
  This carve-out is intentional and bounded; it does NOT extend to neutral
  status indicators, decorative emphasis, or chart series. Originating decision:
  `docs/plans/beta/07-google-oauth-youtube-foundation/specs/7c-settings-youtube-ui.md`.
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

**2026-05-10 tightening.** The convention is `[label]` — no inner padding
spaces. This is a deliberate tightening from the prior `[ label ]` shape; the
goal is minimum length and terser visual weight. Every bracketed link, button,
chart legend, and saved-view label across web, MCP, and the `pito` CLI follows
the no-inner-spaces rule. Examples below already reflect the tightened form.

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

### Badges

Compact inline status / count primitives. Two families:

- **Badges** — bordered pills, neutral / muted / colored variants. Base
  component: `StatusBadgeComponent` (will rename to `BadgeComponent` in the next
  consolidation pass — see follow-up). Variants are CSS modifiers on
  `.status-badge`: `--info`, `--neutral`, `--success`, `--yes`, `--warn`,
  `--urgent`, `--no`, `--all_day`. The muted family (`--info` / `--neutral` /
  `--no` / `--all_day`) uses `var(--color-badge-muted-bg)` filled background;
  active family (`--success` / `--yes`) uses colored border + colored text on
  transparent background.
- **Chips** — filled pills with brand color background + white text. Reserved
  for PS / Switch / Steam platform identification — see `### Platform Chips` for
  the locked palette.

**Naming convention.** Components in this family drop the `Status` prefix going
forward (`ActiveBadgeComponent`, `YesNoBadgeComponent`, `TooltipBadgeComponent`
already do). The base `StatusBadgeComponent` and `StatusTbdBadgeComponent`
survive their legacy names pending a consolidation rename.

**Choose a badge, never a styled text span.** When you need an inline status /
count primitive, use `StatusBadgeComponent.new(label:, kind:)` — not an ad-hoc
`<span class="text-muted">(<count>)</span>`. The component carries the borders,
padding, and theme-aware tokens; text spans drift from the system.

### Platform Chips

Platform tags render as filled status-badge style pills in the platform's brand
color — `PS`, `Switch`, `Steam`. They sit in tile footers and on game detail
pages as a compact at-a-glance signal of where a game ships.

Render shape: background = brand color, text = contrasting white. **NO visible
`[ ]` brackets in the rendered HTML.** The `[ ]` notation used in chat, spec
docs, and prose is a stand-in for the visual badge; the DOM output carries no
literal brackets. Pattern matches the existing `.status-badge` family (see
`StatusTbdBadgeComponent`).

**Locked colors — single set for BOTH themes.** No theme-scoped overrides; the
brand color reads on both light and dark backgrounds and is treated as a fixed
visual token.

| slug     | label    | hex       |
| -------- | -------- | --------- |
| `ps`     | `PS`     | `#003791` |
| `switch` | `Switch` | `#E60012` |
| `steam`  | `Steam`  | `#00ADEE` |

**Generation collapse.** The PS chip covers BOTH PS5 (IGDB 167) AND PS4 (IGDB
48). The Switch chip covers BOTH Switch 2 (IGDB 508) AND Switch gen 1 (IGDB
130). Steam covers the PC family per the filter-token / DB-slug collapse table
below. This collapse happens at the `Platform::IGDB_ID_TO_CANONICAL_SLUG`
mapping in `app/models/platform.rb` — the family chip absorbs all generations of
the same brand at the model layer, so by the time the view renders chips there
is no per-generation slug to display.

**Xbox excluded.** No Xbox chip renders for Xbox / Xbox 360 / Xbox One / Series
X|S games. User-locked 2026-05-17.

Two size variants:

- `:sm` — 12px, used in tile footers on shelf surfaces
- `:md` — 14px, used on the detail-page LEFT pane

When chips iterate, render them as separate badges with a small gap — no extra
separator (dot, pipe, comma) goes between them.

Layout / spacing:

- Adjacent chips in a horizontal layout: `gap: 2px` (tight).
- Chip group spacing from preceding text on the same row (e.g., the year prefix
  in a tile caption row): `gap: 4px` (breath) — slightly more than the
  inter-chip gap so the group reads as one cluster.
- Wrap the chips in a `display: inline-flex; gap: 2px` container; apply the
  `gap: 4px` separation on the parent row (column gap or margin), not on the
  chip container itself.

Replaces the prior PNG platform-logo pipeline (decommissioned 2026-05-17).

- **Component:** `Platforms::ChipComponent.new(slug:, size:)`

**Tile overlay placement (2026-05-17).** In a tile context, chips render as an
**absolute overlay on the cover image**, anchored to the cover's bottom-right
corner — the chip container touches both the right edge and the bottom edge of
the cover border. The container carries a solid background color matching the
cover border token (`var(--color-cover-border)`, the same token wrapping the
cover image in `Games::CoverComponent`) so the overlay reads as a flush
extension of the cover frame, not a floating element. Inner spacing between
adjacent chips inside the overlay container stays `gap: 2px` per the tightness
rule above.

**Filter token → DB slug collapse.** Platform CHIP tokens (`ps`, `switch`,
`steam`) intentionally map to MORE than one underlying IGDB platform slug at the
filter layer:

| chip token | matches IGDB platform slugs                  | rationale                                                                                                                                               |
| ---------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ps`       | `ps5`, `ps4--1`                              | both PlayStation generations — the PS family chip covers PS5 and PS4 back-catalog                                                                       |
| `switch`   | `switch`, `switch-2`                         | both Switch generations — the Switch family chip covers Switch 2 and Switch gen 1 back-catalog                                                          |
| `steam`    | `win`, `linux`, `mac`, `dos`, `web`, `steam` | PC family per `PC_STORE_IGDB_IDS` (6/3/14/13/92) plus the dedicated Steam store — same set the chip-display helper collapses for `pc_store_slugs(game)` |

The mapping lives at the FILTER layer (`Games::Filter` `TOKEN_TO_PLATFORM_SLUGS`
constant) AND mirrors the chip-display collapse at
`app/helpers/platform_logos_helper.rb`. When adding a new platform chip, update
BOTH places.

### Filter semantics

The `/games` filter chips combine across **four orthogonal axes** — lifecycle
(`released` / `scheduled`), ownership (`owned` / `wishlist`), engagement
(`played`), and platform (`ps` / `switch` / `steam`) — with within-axis OR,
cross-axis AND, per-platform binding when the platform axis intersects with
ownership or engagement, and bidirectional cascade in the UI (checking a child
auto-checks parents; unchecking a parent re-validates and may auto-uncheck
dependent children). The full rule set (implies / mutex, worked cascade
walkthrough, per-platform binding, worked URL examples) is captured in ADR 0013
(`docs/decisions/0013-games-filter-semantics.md`).

### Rating Heat Bar

A 200×14 px horizontal bar visualizing a synthesized 0..100 score for a game.

The score is the vote-weighted average of IGDB's `igdb_rating`,
`aggregated_rating`, and `total_rating` — sources whose corresponding `*_count`
is zero are excluded from the average.

Fill color tracks the existing `--color-rating-<tier>` token (`excellent`,
`good`, `fair`, `meh`, `poor`, `bad`) so the bar auto-themes via Light / Dark
without per-surface overrides.

The numeric label sits right-aligned over the fill with a `var(--color-bg)`
plate behind it for legibility against any tier color.

When no score is available, the bar renders at 0% fill, 0.5 opacity, with an
em-dash label.

- **Component:** `Games::RatingHeatBarComponent.new(game:)`

### Status TBD Badge

A bracketed inline badge — `[TBD]` — in bright orange `#ff8800`, weight 600,
monospace, `white-space: nowrap`. Marks "we'll get to this later" placeholders
across the app: footage rows, the videos empty state, the search placeholder
modal.

Non-interactive — `cursor: default`. The badge is a label, never a link.

- **Component:** `StatusTbdBadgeComponent.new` — takes no arguments

### Composite overflow badge

The `+N` "more games" badge baked into bundle composite covers (visible on
bundles with more games than the layout can show — e.g., the 9-grid overflow at
N≥10 cell case).

- Font: `Cascadia Code Bold 32` via libvips/Pango (matches the web app's
  `## Typography` #1 monospace preference).
- Size: 32pt — half the original 64pt; sized for the 98×130 px composite tile
  without overwhelming the artwork.
- Background: muted gray pill (#dfe2e7 fill, #444 text) — mirrors the
  `StatusBadgeComponent kind: :neutral` shape from `### Badges`.
- Padding: 4 px horizontal, 2 px vertical around the text inside the pill.
- Source: `app/services/composite/layout/nine_grid_with_overflow.rb` `TEXT_FONT`
  constant.

The badge is BAKED into the JPEG at composite-build time — themes do NOT swap it
at render time. Light-theme palette is used since covers are heterogeneous and
light gray reads against most artwork. If a dark-theme variant is needed later,
the composite job would need to emit a second JPEG and the consumer view would
switch sources.

### Confirm Modal pattern

For destructive actions where the full action-screen pattern is too heavy — the
common case being a single-record delete from a detail page — use the in-page
`<dialog>` confirm modal instead.

The trigger is a `[delete]` bracketed link wired to a Stimulus modal-trigger
controller; the modal itself is rendered by the existing `ConfirmModalComponent`
and uses the native `<dialog>` element opened via `.showModal()`. The
`confirm-modal` Stimulus controller handles Escape and click-outside dismissal.

Trigger anatomy:

```html
<a
  data-controller="modal-trigger"
  data-action="click->modal-trigger#open"
  data-modal-trigger-target-id-value="confirm-delete-game-42"
  >[delete]</a
>
```

Modal buttons:

- `[delete]` (danger color) — submits a DELETE to the resource
- `[cancel]` (muted) — closes the dialog via `confirm-modal#close`

**Hard rule.** Never use `data-turbo-confirm`, JS `confirm()`, or `alert()`. The
native `<dialog>` element IS the confirmation UI.

For bulk destructive actions, the action-screen framework
(`/deletions/:type/:ids`) remains the primary path. The in-page modal is a
per-record convenience layered on top, not a replacement.

### Bracketed labels: minimum text

Bracketed-link labels carry **the verb only** when context makes the noun
obvious. Trust the user to know what kind of row they're looking at — the page
heading, breadcrumb, and table headers already supply the context.

**Yes:**

- On `/settings/oauth_applications`: each row's destructive action is
  `[revoke]`, not `[revoke application]`
- On `/settings/sessions`: each row's destructive action is `[revoke]`
- On `/settings/tokens`: `[new]`, `[create]`, `[revoke]`
- On `/settings/youtube`: `[connect]`, `[reconnect]`

**No:**

- `[revoke application]`, `[delete channel]`, `[edit token]` — the noun is
  redundant when the surrounding context is unambiguous.

**Carve-out:** if a row hosts multiple action verbs targeting different nouns,
keep the noun on each (`[edit channel]` and `[edit playlist]` could appear in
the same row — disambiguation needed).

This principle helps the `pito` CLI maintain visual parity — terminal real
estate is precious; verbose labels burn cells. Mirror this on every keymap that
surfaces a label.

### External links — new tab convention

Every link that points to a website **outside the pito app** (anything not
served by `app.pitomd.com` / `mcp.pitomd.com` / a relative path) MUST open in a
new tab. Use the exact attribute combination:

```html
<a href="https://example.com" target="_blank" rel="noopener noreferrer">…</a>
```

Why the pairing:

- `target="_blank"` keeps the user's pito tab put. A `[help]` modal that links
  to Slack docs must not yank the user out of the settings page they were
  configuring.
- `rel="noopener"` prevents the new tab from reaching back into `window.opener`
  (a tabnabbing / cross-window scripting vector).
- `rel="noreferrer"` additionally suppresses the `Referer` header so the
  destination site never learns which pito URL sent the user.

Both `rel` tokens together — `noopener noreferrer` — are the project standard.
Do not ship `rel="noopener"` alone; do not ship `target="_blank"` alone.

**Internal links stay default.** Links pointing inside pito (`/settings/...`,
`/channels/...`, fragment anchors, `mailto:` and `tel:` schemes) render same-tab
so Turbo navigation, back-button history, and breadcrumb continuity keep
working.

**Where the rule applies:**

- `BracketedLinkComponent` callers — **automatic.** As of 2026-05-16 the
  component auto-detects external hrefs (absolute `http://` or `https://` URLs)
  and emits `target="_blank"` plus `rel="noopener noreferrer"` itself. Callers
  do NOT pass `target:` / `rel:` for external links — the component handles it.
  Internal hrefs (relative paths, `#fragments`, `mailto:`, `tel:`) stay default.
  Explicit caller-supplied `target:` / `rel:` still win when present, so the
  rare override (force same-tab on an external URL, or force a popup on an
  internal one) is one keyword away. This is the preferred path for every
  clickable link in the app.
- Markdown sources rendered into views (webhook help guides, future settings
  help guides) — render with
  `render_markdown(@markdown, target_external_links: true)`; the helper
  post-processes anchors via Nokogiri to inject the pair on every absolute
  `http://` or `https://` href.
- Raw `<a href="http...">` tags in ERB — **avoid.** Prefer
  `BracketedLinkComponent` so detection is automatic and the bracketed visual
  convention stays consistent. If a raw anchor is unavoidable (e.g. semantic
  markup outside a clickable label), write the
  `target="_blank" rel="noopener noreferrer"` pair by hand.
- Stimulus / JS-driven anchor mutation — same attributes when setting `href`.

**Note editor preview is the explicit carve-out.** Notes are private scratch
space, and the live-preview parity with `marked.js` (which doesn't rewrite
anchors) matters more than new-tab behavior on internal scratch. The note
preview path therefore does NOT pass `target_external_links: true`.

If you are adding a new surface that renders user-supplied or author-supplied
markdown containing outbound URLs, flip the flag on at the call site. If you are
adding a new ERB view, write the attributes by hand. There is no automatic
rewrite of view-layer ERB.

### Lead paragraphs — one sentence per line

The muted lead paragraph that sits under each page H1 splits one sentence per
line — never a chunky body of text. Use `<br>` between sentences inside one
`<p class="text-muted">` so the existing margin styling holds and the sentences
read as a stack rather than wrapped paragraph prose.

```erb
<h1>Add channel</h1>
<p class="text-muted">
  Paste a YouTube channel URL.<br>
  Pito locks the URL after create.<br>
  Only the star and connected flags stay editable.
</p>
```

Apply on every settings detail page and every `new` / `show` / `edit` page that
has explanatory prose under the heading. The convention is intentional: each
sentence reads as its own atomic claim, and the user can scan the stanza without
parsing wrap behavior.

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

## Copy

### URL casing

In user-facing copy — view labels, page text, table headers, button text,
tooltips, error messages, breadcrumb labels — write `URL` always uppercase.
Never `url`, `Url`, `Urls`, etc. The full word is always uppercased; embedded
forms like `URLs` (plural) keep the all-caps. Mixed-case forms are not allowed
in user copy.

This rule is for user copy only. Routes, Rails URL helpers, database column
names, Ruby method / variable / symbol identifiers, JSON keys, HTML data
attribute keys, and Stimulus controller action names follow standard snake_case
/ kebab-case conventions and remain lowercase as Rails / web standards dictate.

Mnemonic: a user reading `url` thinks of the technical lowercase identifier;
`URL` is the noun in English. pito surfaces the noun.

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

### Unsaved-changes navigation guard

Forms whose loss would cost the user real typed content opt into a navigation
guard via the `unsaved-form` Stimulus controller. The controller composes
alongside whatever feature controllers the form already needs — multiple values
are space-separated, order is irrelevant.

```erb
<%= form_with(model: @note,
              url: note_path(@note),
              method: :patch,
              data: { controller: "markdown-editor unsaved-form" }) do |f| %>
```

**Behavior.** On `connect`, the controller serializes every named
input/textarea/select/checkbox into a snapshot string. Every `input` and
`change` event inside the form re-serializes and flips an internal `_dirty` flag
if the result diverges from the snapshot. On `beforeunload`, if dirty, the
handler calls `event.preventDefault()` AND assigns `event.returnValue = ""` —
both are required (preventDefault for the HTML Living Standard / current
Chromium, returnValue for legacy WebKit). On `submit`, `_dirty` is cleared
before the navigation fires so a successful redirect doesn't re-trigger the
prompt.

**Carve-out from the no-JS-confirms rule.** This is THE documented exception to
the "no `alert` / `confirm` / `prompt` / `data-turbo-confirm`" hard rule (see
`CLAUDE.md` → Hard rules). The browser-native "Leave site?" dialog raised by
`beforeunload` is structurally different from `window.confirm()` — the browser
renders the dialog itself, and the page never interrupts a user action
mid-click. The action-confirmation framework (`ConfirmModalComponent`,
`shared/_action_screen.html.erb`, `DeletionsController` / `SyncsController`)
covers in-page destructive intent; it cannot cover off-page navigation, tab
close, or reload, which is the gap this controller fills.

**When to apply.** Any form where losing typed input would be costly —
substantial free-form text fields, markdown editors, multi-line note bodies,
future settings sections with rich text. Do NOT apply to short single-field
forms (search box, channel-add URL field, simple toggles); the friction of the
leave-site dialog outweighs the value of the small amount of input that would be
lost.

Currently wired on:

- `app/views/notes/show.html.erb` — note editor (markdown body textarea).

Consider when these land: any future bulk-edit forms; future settings sections
that grow into long-form input; any future composition surface (drafts,
multi-paragraph descriptions, project-level prose fields).

**Browser-text caveat.** The dialog string is browser-controlled. The empty
string we assign to `returnValue` is ignored by Chromium and Firefox; older
WebKit may still surface it. Don't try to customize it — there is no portable
way to.

## Framed blocks

The `.framed-block` class wraps a region in a visually distinct bordered, tinted
container so it reads as separate from the page background. Reserved for **"save
this now" / one-time-reveal surfaces** — content the user must capture because
it cannot be re-shown.

**Visual properties.**

- 1px `var(--color-border)` border
- `var(--color-pane-bg)` background tint
- 4px `border-radius`
- 16px inner padding
- 16px vertical outer margin (`margin: 16px 0`)

```css
.framed-block {
  margin: 16px 0;
  padding: 16px;
  border: 1px solid var(--color-border);
  background: var(--color-pane-bg);
  border-radius: 4px;
}
```

**When to use.**

- Highlighted content blocks where the visual frame helps the user register
  "this is important / save this / one-time view".
- OAuth applications post-create page — wraps the `client_id` + `client_secret`
  credentials list (the secret is shown exactly once and cannot be retrieved
  later).
- Future: API token plaintext displays, secret-shown-once flows, game cover-art
  reveals, any other capture-now surface.

**When NOT to use.**

- Every block on a page. The frame is signal — overusing it degrades the signal
  so nothing reads as important.
- Routine read-only detail panels (use a plain `.detail-table` instead).
- Decorative grouping. Frames mark capture-now content, not visual hierarchy.

**Long-value buffer.** Inside a framed block, a `.code-block` row reserves
`padding-right: 4px` on its inner `<code>` so long wrapping values
(`client_secret` is 64 characters) don't run flush with the frame's right edge.
Scoped to `.framed-block .code-block code` so the global `.code-block` behavior
is unchanged elsewhere.

## Panes (Multi-item View)

### Pane primitives

Three primitives, all driven by `--color-pane-bg-a` with zebra
`:nth-child(even)` swap on multi-pane rows:

- `.pane` — fixed-width workspace column (`flex: 0 0 452px`). Used inside
  `.pane-row` for the channels / videos workspace and the settings index grid.
  Background `--color-pane-bg-a`; even-indexed siblings swap to the alternate
  tone for the zebra.
- `.pane.pane--standalone` — full-width single-column container with the same
  pane background but no fixed width. Used for full-width data-display surfaces:
  oauth_applications create / show / revoke, doorkeeper authorizations new /
  show / error, settings/tokens create / revoke, settings/sessions revoke. Form
  pages also use it.
- `.pane--wide` — fixed 904px workspace double-column variant.

`.framed-block` is now orphaned; `pane--standalone` replaced it. New work
reaches for `pane--standalone` instead of resurrecting `framed-block`.

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
  mobile arrows hidden inside the snap row (reorder via the `[panes]` dialog
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
  row as a `[label]` bracketed link plus a separator dot.

This rule is global — it overrides any per-page styling that previously allowed
the row to wrap. The component (`SavedViewsSectionComponent`) emits both
classes; pages that compose saved-views inline must use the same shape.

### Horizontal scrollbars

pito uses a themed horizontal scrollbar in place of the browser default for any
container that scrolls horizontally. The convention:

- **Thickness**: 6px on both axes, sitewide. The unsuffixed
  `::-webkit-scrollbar` rule applies to vertical scrollbars (body, modals,
  textareas) as well as horizontal — the OS default vertical bar is themed away
  too. Firefox uses `scrollbar-width: thin` on `html` for both axes.
- **Track**: `var(--color-bg)` — blends with the page background.
- **Thumb**: `var(--color-muted)` — visible but subtle.
- **Thumb hover**: `var(--color-text)` — clearly indicates interactivity.
- **Thumb border-radius**: 3px.

Implementation in `app/assets/tailwind/application.css`:

- **Webkit / Blink** (Chrome, Brave, Safari): styled globally via
  `::-webkit-scrollbar:horizontal` so every horizontal scrollbar app-wide picks
  up the theme automatically. Vertical scrollbars (body, modals, textareas) keep
  the browser default.
- **Firefox**:
  `scrollbar-width: thin; scrollbar-color: var(--color-muted) var(--color-bg)`
  applied per-container (Firefox has no `:horizontal` pseudo). Currently applied
  to `.pane-strip`, `.saved-views-list`, `.markdown-preview pre`, and the mobile
  `<table>` rule.
- **Mobile iOS Safari**: ignores both — uses the native overlay scrollbar
  (acceptable; matches mobile expectations).

For new horizontal-scroll containers, add the `.themed-scroll-x` utility class
to opt into Firefox theming. Webkit theming is already automatic. Where a
container overflows in only one axis, scope the rule to that axis
(`::-webkit-scrollbar:horizontal`); where it overflows in both, applying the
theming to both is acceptable for consistency.

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

### Cover Sizes

Two `Games::CoverComponent` variants exist at the component level. Source of
truth: `app/components/games/cover_component.rb` DIMENSIONS constant +
`docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
§"Locked decisions" item 1.

| variant  | dimensions   | usage                                                                                                                                                                                                              |
| -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `:shelf` | 98 × 130 px  | used by **genre shelf** via `Games::CoverComponent.new(variant: :shelf)` (see `_genre_sub_shelf.html.erb`). 65% of `:grid` baseline; explicitly calculated per plan.md to balance density vs cover-art legibility. |
| `:grid`  | 150 × 200 px | the all-games grid baseline. Surface that used to consume it (grid display mode) was removed in spec 05; the variant lives on for `/games/:id` detail rendering.                                                   |

**Inline 150 × 200 renders that bypass `CoverComponent`:**

- **Letter shelf cover** — inline-rendered at 150 × 200 px in
  `app/views/games/_tile.html.erb` (hardcoded `img` dimensions). The `_tile`
  partial does accept a `:shelf` variant flag, but that flag only affects the
  caption font size — the cover itself is 150 × 200, matching the `:grid`
  variant dimensions.
- **Bundle shelf cover** — inline-rendered at 150 × 200 px in
  `_bundle_for_shelf_tile.html.erb`. The composite is built at a 600 × 800
  canvas by `Bundles::CompositeRebuildQueue` and displayed scaled to 150 × 200.

No `:small` variant. **Inconsistency flagged:** the letter + bundle shelf covers
render at the `:grid` size (150 × 200) but do not route through
`Games::CoverComponent.new(variant: :grid)` — they inline the `img` tag with
hardcoded dimensions. Wave F refactor candidate: centralize through
`CoverComponent` so the DIMENSIONS constant is the single source of truth for
every surface.

### Shelves

The `/games` index renders horizontally-scrolling shelves. Three shelf kinds,
each with its OWN tile size + content tier. The rich tile is reserved for the
letter shelves; genre and bundle shelves are visually denser, art-only browse
surfaces.

- **Letter shelves — 150 × 200 cover + rich caption + chip overlay.** One row
  per starting letter (A–Z, 0–9). Each tile is the medium-tier rich tile
  (`_tile.html.erb`): cover inline-rendered at 150 × 200 px with platform chips
  overlaid on the cover's bottom-right corner (per
  `### Platform Chips > Tile overlay placement`), and a caption row below the
  cover containing the title only. Release year and other release info are NOT
  rendered in the tile — they belong on the game detail page, not the shelf.
  This is the "game listing" surface — the only shelf kind that uses the rich
  tile.
- **Genre shelves — 98 × 130 bare cover (no caption, no chips).** One row per
  primary genre. Every game with that `primary_genre` renders as an individual
  bare cover via `Games::CoverComponent.new(variant: :shelf)`, sorted
  alphabetically by title. Not a composite, not a rich tile, not a Netflix-
  style merged image — just a horizontal scroll of N bare covers at the `:shelf`
  dimensions.
- **Bundle shelf — 150 × 200 composite cover (no caption, no chips).** A single
  row labeled "bundles" containing every bundle. One composite cover per bundle
  inline-rendered at 150 × 200 px. The cover art IS the bundle's compound
  (composite) image built by `Bundles::CompositeRebuildQueue` at a 600 × 800
  canvas and displayed scaled to 150 × 200. No title, no chips below.

The shelf kinds split into two cover-dimension groups: letter + bundle render at
150 × 200 (matching the `:grid` variant size but inline, not through
`CoverComponent`); genre renders at 98 × 130 via the `:shelf` variant. See
`### Cover Sizes` above for the centralization follow-up.

**Shelf heading count badge.** Each shelf heading (letter name, genre name,
"bundles") displays the game count alongside the heading as a **muted badge** —
`StatusBadgeComponent.new(label: count.to_s, kind: :neutral)` — not as
parenthesized text `(2)`. The badge is the filled muted-bg pill from the
`### Badges` family. An earlier `MutedCountBadgeComponent` built during the same
session rendered plain text inside parentheses; it was the wrong shape and is
slated for deletion in the next code dispatch in favour of the canonical
`StatusBadgeComponent`.
