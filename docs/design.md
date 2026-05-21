# Design System

## Terminology

Locked 2026-05-20. The five nouns below are the canonical vocabulary for pito's
UI surfaces. Use them exclusively in design.md, agent prompts, specs, and code
copy. Drift (pane / modal / button / caption / page used as nouns referring to
one of these) is a bug to fix, not a stylistic choice.

| Use this   | Not this                  | Example                                |
| ---------- | ------------------------- | -------------------------------------- |
| **panel**  | pane                      | "security" panel in /settings          |
| **screen** | page                      | /settings or /games (the URL itself)   |
| **dialog** | modal                     | the help dialog (`?` overlay)          |
| **action** | link, url, button         | `[revoke]`, `[update]`, `[help]`       |
| **hint**   | text, caption             | "type \"clear\" to remove"             |

**Screen (not page).** pito's top-level surfaces (`/settings`, `/games`,
`/channels`, `/home`, `/videos`, `/calendar`, `/notifications`) are called
**screens**, never **pages**. This aligns with the TUI/Ratatui vocabulary that
the `pito` CLI uses. The Top Status Bar carries the current **screen name**, not
a page title. The term "page" is reserved for paginated result navigation (e.g.
"page 2 of 5"); it does NOT refer to a top-level surface.

**Dialog (not modal).** Every overlay that interrupts the screen — help
overlay, webhook help, about, confirmation, deletion confirmation, TOTP code
entry, command palette, search "everywhere" — is called a **dialog**. The
term "modal" is retired in user-facing copy, docs, and new code. Existing
class names (`omnisearch-modal`, `confirm-modal`, `webhook-help-modal`,
`notifications-modal`, `totp-modal`, `about-modal`) may stay until a
coordinated rename; new components should use `*-dialog` naming.

**Panel (not pane).** The subdivided regions inside a screen — "security",
"notifications", "stack", "time zone" inside `/settings`; tile lattices inside
`/games`; the channel sidebar; the workspace columns — are called **panels**.
Existing CSS tokens and class names (`--color-pane-bg`, `.pito-pane`,
`pane-row`) may stay until a coordinated rename; new components, copy, and
docs use `panel`.

**Action (not link, url, or button).** Every clickable element rendered in
pito's bracketed grammar — `[revoke]`, `[update]`, `[help]`, `[close]`,
`[cancel]`, `[ add channel ]` — is an **action**. Refer to them as actions in
copy, specs, and dispatch prompts; the `<a>` / `<button>` HTML element choice
is an implementation detail. Chart legends, bracketed nav items, and submit
controls are all actions.

**Hint (not text or caption).** Helper copy under an input, an empty-state
explainer below a chip row, the muted italic explainer next to a toggle, the
"type \"clear\" to remove" line under a destructive input — all called
**hints**. The `.form-hint` and `.caption` CSS utilities (see the "Form hints
and captions" subsection below) keep their existing class names until a
coordinated rename; new copy and docs use "hint".

## Density and decoration

Every pito screen targets Excel-sheet density. Tabular data, dense rows, tight
padding (8px vertical / 12px horizontal max for panel content, 6px between
chrome and content). Decoration appears ONLY when it carries signal: section
accent border identifies the screen, danger color warns the user, status chip
colors encode meaning, focus outline shows the cursor. Anything that's "nice to
look at" without signaling something is removed.

**Border-radius is always 0.** No exceptions. Buttons, panels, chips, dialogs,
modals, inputs, hover targets — every element renders with sharp 90° corners.
Rounding is web-design language; pito's TUI aesthetic requires square corners.
If you find `border-radius: 2px` (or any non-zero value) in CSS, it's a bug to
fix, not a design choice.

## Typography

- **Font:**
  `"BitstromWera Nerd Font Mono", ui-monospace, Menlo, Consolas, monospace`.
  Packed into `app/assets/fonts/` and declared via `@font-face`. Nerd Font
  variant — includes the full glyph set for status icons and inline
  sparklines drawn as text.
- **Base size:** 13px
- **Line-height:** `1` — HARD RULE, no exceptions for body text. Default body /
  table / chip / link / status bar / form label / panel content all use
  `line-height: 1`. Input fields and textareas MAY use `1.2` if the caret feels
  cramped, never higher. NEVER `1.4` / `1.5` / `1.6` anywhere in the app. The
  reason: pito targets Excel-sheet density — line-height > 1 wastes vertical
  real estate, and the monospace grid should read like a TUI row.
- **Headings:** all heading levels (h1 / h2 / h3 / h4 / h5 / h6) render at
  the base 13px size. Visual hierarchy comes from `font-weight: bold` +
  `font-style` + sparse Nerd Font glyphs + section accent color. No size
  differentiation per level — locked Beta 4 (see Visual density and hygiene
  section).
- **Footer:** 11px

### Heading 4

`<h4>` is **not italic by default.** The global `h4` rule sets weight only —
italic is opt-in via class. This is rule 6 of the §10 design refresh.

- `h4.h4-emphasis` — opt-in italic for decorative `<h4>` (admin screens,
  dashboard summaries, sidebars).
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
`<h4>` (admin screens, dashboards, summaries) flows through `.h4-emphasis` if
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
| `--color-bg`         | #ffffff | Screen background          |
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
| `--color-bg`         | #282a36 | Screen background (Dracula bg)       |
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
- **Exception — rating quality spectrum.** The `RatingHeatBarComponent` may use
  red (`var(--color-rating-bad)`, `#cc0000` light / `#ff5555` dark) as the low
  end of the quality gradient. Red here encodes semantic quality information
  ("bad" tier), not a destructive-action signal. This carve-out is restricted to
  the heat bar's bad-zone color stop and the `--color-rating-bad` token's
  surface area; it does NOT extend to other charts, indicators, or decorative
  elements. User-approved 2026-05-17.
- **Exception — trend-down indicators.** The `▼` glyph in trend-direction
  renders (subs/views/watch-hours on `Channels::IdCardComponent`, future video
  and analytics metric surfaces) uses `var(--color-trend-down)`, aliased to
  `var(--color-danger)` (`#cc0000` light / `#ff5555` dark). This is the SECOND
  allowed non-destructive use of red, restricted to `--color-trend-down`'s
  render surfaces. See `### Trend indicators` for the full glyph + color family.
  User-approved 2026-05-19.
- Charts use the `--color-chart-N` palette. If more colors are needed, extend
  with non-red colors.
- All inline styles must use CSS variables, not hex values, for theme
  compatibility.

### Section accent palette

Each top-level section binds the `--section-accent` token to a fixed hue so
navigation, headers, and section-scoped chrome carry a consistent identity. The
palette is locked; do not introduce new sections without a paired user decision
captured here.

| Section            | Token              | Hex       | Source                          |
| ------------------ | ------------------ | --------- | ------------------------------- |
| Home / Dashboard   | `--section-accent` | `#bd93f9` | Dracula Purple                  |
| Channels + Videos  | `--section-accent` | `#ff5555` | Dracula Red                     |
| Projects + Games   | `--section-accent` | `#7eb6ff` | Pale Cobalt (Dracula-compatible) |
| Settings           | `--section-accent` | `#ffb86c` | Dracula Orange                  |

Locked 2026-05-19 after `tmp/dracula-swatches-v2.html` Section B side-by-side
review. The Projects + Games hue (Pale Cobalt `#7eb6ff`) is the variant-B
winner; future agents reference this table — not the CSS — as the canonical
source.

## Visual density and hygiene

pito follows a compact, numbers-heavy, TUI-faithful visual philosophy locked
2026-05-20 during the Beta 4 exploratory pivot. These rules govern every layout
decision and every ViewComponent design.

### Compact density

- White space is a premium. Every empty pixel must earn its place by serving a
  real readability purpose — not for breathing room "by default." Padding
  budgets are tight. Default to ZERO margin/padding and add only when content
  collides or visual grouping demands it.
- Sections, panels, and cards prefer hairline separators (1px borders) over
  background-tinted blocks for grouping. Hairlines + spacing carry the visual
  hierarchy; backgrounds are reserved for section-accent tinting at the body
  level.
- Numerical data is the headline. Tables, sparklines, percentages, ASCII bars,
  and inline metrics dominate the canvas. Decorative chrome is the exception.

### Numbers-heavy

- Prefer dense tabular layouts (right-aligned numbers via
  `font-variant-numeric: tabular-nums`) over prose summaries.
- Sparklines (`▁▂▃▅▇`) and ASCII progress bars (`▓░`) carry trend / state
  information inline next to numbers wherever possible.
- Status pill / chip text stays terse: `[active]`, `[this]`, `[ip]` — no
  multi-word labels in chips.

### No emojis (durable artifacts and UI)

- Emojis are NEVER allowed in code, ViewComponent output, ERB templates,
  design.md, ADRs, CLAUDE.md, commit messages, or persistent UI surfaces.
- Emojis ARE allowed in master-agent + subagent communication (status updates,
  dispatch announcements, end-of-turn summaries) because that surface is
  ephemeral chat — see `feedback_emojis_in_communication.md`.
- Unicode glyphs that are NOT emojis (box-drawing `╭─╮│╰╯`, sparkline blocks
  `▁▂▃▅▇`, ASCII bars `▓░`, arrows `▲ ▼`, dots `● ○`, brackets, triangles,
  etc.) are universally accepted — they are TUI primitives, not emojis.

### Sparse Nerd Font icons — must earn their place

- pito ships BitstromWera Nerd Font Mono (per ADR 0016). Nerd Font provides
  3,600+ icon glyphs.
- Sparse use ONLY. A Nerd Font icon earns its place by carrying unambiguous
  functional meaning that text alone cannot convey concisely (e.g. powerline
  triangle separator `` U+E0B0 for structural rendering, status state glyphs
  `●` `◐` `✗` for sync indicators).
- A Nerd Font icon does NOT earn its place by being decorative, by duplicating
  an adjacent text label, or by adding visual interest.
- When in doubt: drop the icon. Letter codes (`b12 e33 r3`) beat icon prefixes
  (`▶ b12 ⏳ e33 ↻ r3`) for compact density.

### Single font size

- 13px base, monospace (BitstromWera Nerd Font Mono).
- No `h1` / `h2` / `h3` size differentiation. Visual hierarchy comes from
  color (section accent) + `font-style` (italic / bold-italic) + Nerd Font
  glyphs (sparse) + position, with `font-weight` as the LAST resort — see
  §"Bold has to be earned" below.
- Locks the character grid. Every line aligns to the same baseline.

### Bold has to be earned

**Bold has to be earned, not attributed.** Default font-weight is 400
everywhere. Bold (600+) is reserved for narrow, deliberate cases where it
carries unique signal — a section name that needs identity beyond color, a
label that must read as different from siblings even at a glance. Color,
italic, glyph, and position carry hierarchy before weight does. Defaulting to
bold for headings, links, buttons, badges, etc. is a bug — strip it.

### Lowercase non-brand text

- All UI labels render lowercase: `home`, `channels`, `games`, `settings`,
  `synced`, `disconnected`, `normal`, `help`, `command`, etc.
- EXCEPTION: brand names stay capitalized — `YouTube`, `Slack`, `Discord`,
  `Sidekiq`, `Voyage AI`, `Meilisearch`, `Redis`, `PostgreSQL`, `Rails`,
  `Hotwire`, `Stimulus`, etc. Per
  `feedback_brand_names_always_capitalized.md`.

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
- **Active (current screen):** renders
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

**Muted bracketed always bold (2026-05-17 lock).** Even though the global
`.text-muted` utility sets `font-weight: 400`, the muted bracketed-link variant
(`BracketedMutedLinkComponent`, CSS class `.bracketed-muted-link`) stays bold
(700) to match the rest of the bracketed-link family. The bracketed identity is
preserved visually whether the link is active or muted — only the color shifts.
The CSS scopes the bold rule to bracketed surfaces
(`a.bracketed.bracketed-muted-link` and the defensive `a.bracketed.text-muted`
arm) so `.text-muted` standalone keeps its `font-weight: 400` per the
`### Muted text and weight` rule.

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

**`:strong` variant — filled high-visibility chip (2026-05-17 lock).**
Background: the canonical positive green (`--color-success`, same token as the
`▲ connected` indicator). Text: white (`#ffffff`). Reserved for chips that
emphasize "this is the active / current / yours" identity. First call site: the
`[this]` chip in the /settings sessions table marking the current session row.
Other green chips (e.g. `▲ connected` status indicators, recorded / owned chips,
neutral `:positive`) stay as-is — they're informational, not identity-
emphasizing. Use `:strong` only when the chip is calling out the user's own
current item among siblings; over-using it dilutes the emphasis.

### Filter chips

- **Canonical component:** `FilterChipComponent`
  (`app/components/filter_chip_component.rb`) — the generic URL-toggling
  bracketed `[ ]` / `[x]` chip used everywhere chip filters appear (`/games`
  filter row, `/notifications` time windows, `/channels` time and calendar
  filters).
- **Reuse rule (locked 2026-05-19, user):** every chip surface in the app uses
  `FilterChipComponent` or composes it. **No bespoke chip markup.** No
  hand-rolled `<a class="filter-chip">` or `<span class="filter-chip">` in
  views, partials, or ViewComponent templates. A new surface needing chips
  passes `param:` / `value:` / `csv:` / `path:` into `FilterChipComponent` and
  is done.
- **Specialized variants:** when a chip surface needs domain-specific logic
  (cascade implications, token universes, custom Stimulus controllers), wrap or
  extend `FilterChipComponent` — see `Games::FilterChipComponent` for the
  canonical wrapping pattern. Wrap, do not reimplement.
- **Inert visual mode:** for layout-iteration surfaces where chips should render
  without URL behavior (early-wave mocked layouts), use `FilterChipComponent`
  with throw-away `param:` values; the controller ignores unread params and the
  chip behavior remains consistent with /games. There is no `inert:` flag —
  wired-but-unread params do the job.

### Platform Chips

Platform tags render as filled status-badge style pills in the platform's brand
color — `PS`, `Switch`, `Steam`. They sit in tile footers and on game detail
screens as a compact at-a-glance signal of where a game ships.

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
- `:md` — 14px, used on the detail-screen LEFT pane

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

### Shelves

- **Canonical component:** `ShelfComponent` (top-level, no namespace,
  `app/components/shelf_component.{rb,html.erb}`) — the universal
  horizontal-scroll tile row primitive. Renamed from `Games::ShelfComponent` on
  2026-05-19 when /channels and future /videos shelf surfaces locked the shelf
  as a domain-agnostic primitive.
- **Usage:** `ShelfComponent.new(heading: nil_or_string, ...)`. `heading:`
  defaults to `nil` for headless shelves (e.g., /channels ID-card row sits
  directly under the title chrome with no heading). When `heading:` is a string,
  the component renders the heading wrapper above the scrollable row.
- **Row inline style:**
  `display: flex; gap: 6px; overflow-x: auto; padding-bottom: 6px;` — locked.
  Every shelf in the app carries this exact row shape so scroll behavior is
  uniform.
- **Encapsulated scrollbar (locked 2026-05-19):** the slim scrollbar styling
  lives INSIDE the shelf component via a scoped class
  `.shelf-row::-webkit-scrollbar` (and `::-webkit-scrollbar-thumb`,
  `scrollbar-width: thin`, `scrollbar-color` for Firefox). The global
  `::-webkit-scrollbar` rule in `app/assets/tailwind/application.css:722-754`
  remains the app-wide default for screen-level scrolls; the shelf overrides via
  the scoped class so the shelf's scrollbar is a documented property of the
  component itself rather than a leaky global inheritance.
- **Reuse rule (locked 2026-05-19, user):** every shelf surface uses
  `ShelfComponent`. **No parallel `<Domain>::ShelfComponent` reimplementations**
  — refactor `ShelfComponent` for new use cases instead of forking. The previous
  `Games::ShelfComponent` rename + heading-optional refactor was driven by this
  rule. Future use cases (notifications, videos, search results) follow the same
  pattern.
- **Callers:**
  - `/games` letter shelves (alphabetical groupings)
  - `/games` genre sub-shelves (under the outer genre shelf)
  - `/games` bundle shelf
  - `/channels` ID-card shelf (headless)
  - Future: /videos shelves, notifications, etc.

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

### Omnisearch modal

The `/games` omnisearch modal renders results in up to three top-to-bottom
sections, in this fixed order:

1. **games** — local Game rows from the install's Postgres / Meilisearch corpus.
2. **bundles** — local Bundle rows (`:games_search` mode only).
3. **on IGDB** — remote IGDB hits, populated on every dispatch and deduped
   against the local games section by `igdb_id` (see
   `docs/architecture.md > Games omnisearch` for the dispatch contract).

The user sees any given game in exactly ONE section. When the local install has
already imported an IGDB row, that row appears in **games** and is filtered out
of **on IGDB**. When it hasn't, the row appears in **on IGDB** only. This
guarantees the three-section model never feels like a duplicate list — every row
is either a local entity (importable already in the library) or a remote entity
(importable via `[add]`).

Section headings render in the same muted typographic style as other modal
section headings; empty sections collapse entirely (no "no results" stub unless
ALL sections are empty, in which case the modal renders a single muted line).
The IGDB-unavailable case renders an upstream-error sentence in place of the
**on IGDB** hit list, leaving the local sections untouched.

Dismiss control is `[close]` per the
[Modal dismiss labels](#modal-dismiss-labels--close-vs-cancel) rubric — the
modal is informational (the user is browsing, not deciding), so dismissing
doesn't decline anything.

### Confirm Modal pattern

For destructive actions where the full action-screen pattern is too heavy — the
common case being a single-record delete from a detail screen — use the in-screen
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
(`/deletions/:type/:ids`) remains the primary path. The in-screen modal is a
per-record convenience layered on top, not a replacement.

### Modal dismiss labels — `[close]` vs `[cancel]`

The dismiss button copy distinguishes the modal's SEMANTIC PURPOSE. Both use the
SAME muted styling — only the LABEL differs.

| label      | use when                                                                                                                                               | examples                                                                                                        |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `[close]`  | Informational / display modal. No decision pending. Dismissing doesn't "decline" anything — the user is just viewing content.                          | Bundle modal (showing games in a bundle), `[help]` for Discord webhook setup, search-placeholder modal          |
| `[cancel]` | Confirmation / decision dialog. User is being asked to confirm OR back out of a (usually destructive) action. Dismissing = "no, don't do that action". | Delete confirm on `/games/:id`, reindex Meilisearch confirm, session-revoke confirm, any "are you sure?" dialog |

**Quick decision rubric for implementers:**

> "Would dismissing this modal mean the user DECIDED something?"
>
> - Yes → `[cancel]`
> - No (just looking at info) → `[close]`

Both render via the same pattern:

```html
<button
  type="button"
  class="bracketed text-muted"
  data-action="...modal#close"
>
  [<span class="bl">close OR cancel</span>]
</button>
```

`ConfirmModalComponent` defaults to `cancel_label: "cancel"`; custom
informational modals use `[close]`.

### Modal footer alignment

- **Modal footer buttons are LEFT-aligned.** `[close]`, `[cancel]`, and primary
  action buttons all sit on the left edge of the footer row. No right-aligned
  footer buttons anywhere in the app. Locked 2026-05-19.

The shared `.modal-footer` and `.confirm-modal-actions` rules use
`display: flex` with no `justify-content` override, so flex children naturally
left-align. Do NOT add `margin-left: auto` to push a button right.

### Modal border-radius

**Locked 2026-05-20, user — supersedes the prior 2px convention.** Every
`<dialog>` surface in the app — confirmation modals (`confirm-modal`),
settings modals (`settings-modal`), wide modals (`wide-modal`), omnisearch
modals (`omnisearch-modal`, `everywhere-modal`), and the about modal — uses
`border-radius: 0`. The omnisearch input field inside an omnisearch modal also
uses `border-radius: 0`, matching the global form-input radius. The rule is
enforced on the base `dialog { border-radius: 0 }` CSS selector so every named
modal class inherits it; per-modal overrides MUST use 0 or omit the property.
No non-zero radius values are permitted on modal chrome — see §"Density and
decoration" for the universal radius-always-0 rule.

### Dialog behavior (universal contract)

Every dialog in pito follows the same shape:

- Rendered as native `<dialog>` element (no Stimulus-driven `<div>` overlays).
- **No backdrop darken** — the dialog renders over the existing screen
  content without dimming the surrounding context. The screen stays readable.
- **Dismiss hint in top-right** — every dialog shows `[Esc to close]` in the
  top-right corner of the dialog header. No exceptions. No `[close]` button
  at the bottom; the Esc hint at the top is the canonical dismiss.
- **One dismiss target only** — never duplicate the close affordance (no
  top-AND-bottom close buttons).
- **Border-radius: 0** — sharp corners per the design rule.
- **Border: 1px hairline** in the section accent color (or
  `var(--color-border)` for global dialogs like the help overlay).
- **Behavior matches the help dialog** (`Tui::HelpOverlayComponent`) —
  canonical reference for all new dialogs.
- **ESC always dismisses** — bound at the dialog level, no Stimulus required
  for that key.

### Modal K-V content — `<dl>` grid (no colons)

Modal content that pairs labels with values (version + revision, key + value
metadata, simple "fact list" surfaces) renders as a `<dl>` definition list laid
out on a 2-column CSS Grid. **No colons after labels** — the visual grid already
communicates the K-V relationship; colons add noise. Locked 2026-05-19;
canonical implementation in `AboutModalComponent`.

```erb
<div style="display: flex; justify-content: center;">
  <dl style="display: grid;
             grid-template-columns: auto auto;
             column-gap: 8px;
             row-gap: 4px;
             margin: 0;">
    <dt class="text-muted" style="text-align: right;">version</dt>
    <dd style="margin: 0; text-align: left;">1.2.3</dd>
    <dt class="text-muted" style="text-align: right;">revision</dt>
    <dd style="margin: 0; text-align: left;">[abc1234]</dd>
  </dl>
</div>
```

**Centered variant (canonical, About modal).**
`grid-template-columns: auto auto` keeps both columns sized to content; labels
right-aligned + values left-aligned puts the gap at the dl's horizontal middle.
Wrap in a `display: flex; justify-content: center;` parent so the
intrinsic-width grid centers under whatever heading sits above it.

**Full-width variant.** When the modal needs the value column to take all
remaining space (long URLs, long titles, multi-word descriptors), use
`grid-template-columns: auto 1fr` instead — label column hugs content, value
column expands. Drop the centering wrapper.

- `<dt>` carries `.text-muted` for the label's secondary visual weight.
- `<dd>` zeros its default browser margin (`margin: 0`) so row-gap is the only
  vertical rhythm.
- The grid alignment is the K-V semantic — no `: ` punctuation, no parenthesized
  formatting, no inline `<strong>`.

**When to use.** Informational modals (about, version, simple metadata
displays). Multi-row attribute panels on detail screens MAY adopt the same shape
when the existing `.detail-table` pattern feels too heavy.

**When NOT to use.** Forms (use `FormFieldComponent`), tables of records (use
`<table>`), narrative prose (use paragraphs).

### Bracketed labels: minimum text

Bracketed-link labels carry **the verb only** when context makes the noun
obvious. Trust the user to know what kind of row they're looking at — the screen
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
  to Slack docs must not yank the user out of the settings screen they were
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

The muted lead paragraph that sits under each screen H1 splits one sentence per
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

Apply on every settings detail screen and every `new` / `show` / `edit` screen that
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

### Universal contract (locked 2026-05-20)

Every table in pito follows these rules:

1. **String/text columns align LEFT.** Header label AND every cell in
   the column.
2. **Number / date / time columns align RIGHT.** Header label AND every
   cell.
3. **Header alignment matches cell alignment.** No mixed alignments
   within a column. A right-aligned `size` column has a right-aligned
   `size` header label.
4. **Use `Formatting::` services for transformed values.** Numbers
   (with delimiters), dates (relative or absolute), durations, file
   sizes, etc. all go through `Formatting::*` services. Inline
   string-juggling in views/components is a smell — extract to a
   service.

**Sortable columns** (when present) show:

- A single arrow glyph on the header (`▲` asc / `▼` desc) when the
  column is the active sort, rendered in `var(--section-accent)` at
  font-weight 400
- No glyph when the column is sortable but not currently active —
  inactive sortable headers carry the default muted header color
- The active glyph + the column header label both inherit the section
  accent color (the `<th>` color cascades to the inner `<a>` via
  `color: inherit`)
- Keyboard (locked 2026-05-20, FB-110):
  - `s` (NORMAL mode, no modifier) — cycle to the NEXT sortable
    column inside the currently focused panel. With no active sort,
    the first sortable column becomes active.
  - `S` (Shift + s, NORMAL mode) — reverse the direction of the
    currently active sort column. No-op when no column is active.
  - Both keys are scoped to `[data-tui-cursor-focused="yes"]` —
    when no panel is focused, or when a `<dialog>` is open, or in
    INSERT mode (typing in an input / textarea / contenteditable
    host or under `data-tui-mode="insert"`), the keys fall through
    to their native behavior. The handler lives in
    `app/javascript/controllers/sortable_keys_controller.js`.

**ViewComponent contract:** every table is a `Tui::TableComponent` (or
a domain-specific component like `Sessions::TableComponent`). Tables
are never inline `<table>` in views — always wrapped in a component.
Each component ships with a passing spec.

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

### Trend indicators

- **Glyphs (locked 2026-05-19, user):**
  - **Up:** `▲` (U+25B2 BLACK UP-POINTING TRIANGLE) in `var(--color-trend-up)` —
    `#2e7d32` light, `#5cb85c` dark.
  - **Steady:** `–` (U+2013 EN DASH) in `var(--color-trend-steady)` — aliased to
    `var(--color-muted)`.
  - **Down:** `▼` (U+25BC BLACK DOWN-POINTING TRIANGLE) in
    `var(--color-trend-down)` — aliased to `var(--color-danger)`.
- **Glyph family parity:** `▲` and `▼` are the SAME glyphs used by sortable
  table headers (`th.sortable::after`,
  `app/assets/tailwind/application.css:983-1023`). Reuse them across every
  trend-direction surface (channel ID cards, video metric rows, any future
  analytics widget) so the up/down vocabulary stays consistent across the app.
- **Sizing:** body font-size (13px monospace per the project default); no
  special sizing. Active sortable arrows bump to 13px from a 10px inactive stack
  at `application.css:1015` — match active-arrow weight inside trend cells.
- **Down-trend red is the SECOND authorized exception to the destructive-only
  red rule.** The first is the rating heat bar (`RatingHeatBarComponent`, see
  the §"Colors" red-restriction note with `--color-rating-bad`). Trend-down red
  is restricted to `--color-trend-down` and its rendering surfaces — no other
  decorative use. New trend-direction tokens that want red must route through
  `--color-trend-down`.
- **Component:** trend rendering happens inside data components
  (`Channels::IdCardComponent`, future video / analytics surfaces). No dedicated
  `TrendComponent` exists yet — if more than three callers form, extract one.

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

In user-facing copy — view labels, screen text, table headers, button text,
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
- **Inputs:** full width, 1px solid border (`--color-input-border`), 0
  border-radius (per §"Density and decoration" universal rule)
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

### Channel avatars

- **Source asset shape:** YouTube Data API returns SQUARE thumbnails via
  `snippet.thumbnails.{default,medium,high}` (88 × 88, 240 × 240, 800 × 800 px
  JPG/PNG). YouTube.com renders them rounded via CSS; the asset itself is
  square.
- **Pito render (locked 2026-05-19, user — reverses earlier 2px-square rule):**
  `border-radius: 50%`. Renders the avatar as a full circle, hiding YouTube's
  opaque-white corner padding so circular creator logos (uploaded with
  transparency, flattened by YouTube to white-cornered JPEG — see "Verified
  empirically" bullet below) display correctly. Matches YouTube.com's own
  rendering treatment. Trade-off accepted: creators who uploaded square artwork
  get their corners clipped; circular-logo creators are visually dominant on
  YouTube so this is the better default.
- **Placeholder (no `avatar_url` yet — pre-sync state):** a 1px bordered empty
  CIRCLE at the same dimensions, `border-radius: 50%`, with a 1px edge in the
  surface-appropriate border token (chip-row avatars use `--color-border`; ID
  card avatars use `--color-cover-border`). No initials, no glyph; the empty
  circle is the pre-sync state.
- **Applies to:** every channel-avatar render surface — `/channels` avatar
  shelf, `/channels/:id` legacy detail (until Wave B removes it), the OAuth
  multi-channel picker modal (when it lands in Wave B), and any future
  channel-avatar surface. The circular treatment is uniform across every
  channel-avatar render — chip-row, ID card, detail screen, picker modal — so the
  visual vocabulary stays consistent with YouTube.com's own avatar rendering.
- **Sizing rule (avatar shelf specifically):** avatar tile height = 2 × chip
  text line-height + the inter-row gap. See `Games::FilterRowComponent` for the
  canonical line-height and gap. The avatar is square so width = height. Pito's
  `Channels::AvatarShelfComponent` is the reference implementation.
- **Verified empirically 2026-05-19** — six well-known channels (MrBeast, NASA,
  Veritasium, Google, GoogleDevelopers, LinusTechTips) plus the user's own
  channel `UCAUaMYX8qxmEmbBybLNr0jw` were probed directly. Every avatar URL
  returns `https://yt3.googleusercontent.com/<id>=s<NN>-c-k-c0x00ffffff-no-rj`
  with `content-type: image/jpeg`,
  `content-disposition: ...channels4_profile.jpg`, JPEG 800×800, 3-channel sRGB
  (no alpha plane). All four corners read `srgb(255,255,255)`. The `c0x00ffffff`
  URL fragment is literally a YouTube-server-side opaque-white background fill.
  **Transparent-corner uploads are flattened to white at YouTube's pipeline.**
  The user's own channel — uploaded as a circular avatar with PNG transparency —
  comes through as the same JPEG-white-cornered shape. No alpha handling needed
  in Pito's render path.
- **No more 2px-radius for channel avatars.** Any agent reading this subsection
  and applying `border-radius: 2px` to a channel avatar is using stale guidance
  — flag and fix. The 2px convention is itself superseded everywhere else by
  the universal radius-always-0 rule (see §"Density and decoration"); only the
  `border-radius: 50%` circle treatment for channel avatars remains a deliberate
  exception because it encodes a circular SHAPE, not corner rounding.

### Channel ID card

The per-channel summary tile rendered in the /channels ID-card shelf below the
title+chips hairline. Component: `Channels::IdCardComponent`
(`app/components/channels/id_card_component.{rb,html.erb}`). Locked 2026-05-19
after several iterations; the dimensions below diverge intentionally from the
prior ISO/IEC 7810 ID-1 (1.586:1) sketch.

**Outer card.**

- **Dimensions:** **158 px tall × 314 px wide** (landscape). The width is a 25%
  widening of the prior ISO ID-1 footprint at the same height; the extra 63 px
  flow entirely into the right column.
- **Border:** 1px `var(--color-cover-border)`, `border-radius: 0` — same
  framed-thumbnail convention as /games tiles and the /channels avatar shelf's
  per-avatar border. Per §"Density and decoration" universal radius-always-0
  rule.
- **Background:** `var(--color-channel-id-card-bg)` — theme-aware token,
  `#eef0f3` light, `#2f3142` dark. Values copied from the Discord pane's
  `--color-pane-bg-a` tone for surface parity, but the token is **independent**
  so future tweaks decouple.

**Two-column body.** Below a full-width name row + horizontal hairline, the body
splits into:

- **Left column — 125 px fixed (`flex-shrink: 0`).** Avatar + handle. Extends
  through the full body height; the in-body footer hairline and footer live in
  the right column only.
- **Right column — 189 px flex (auto-expand).** Three-row stat grid + footer.

**Avatar (inside card).**

- **Size:** 105 px square (`width: 105px; height: 105px`, `aspect-ratio: 1/1`,
  `flex-shrink: 0`).
- **Shape:** `border-radius: 50%` — full circle, per the §"Channel avatars" rule
  above. Empty pre-sync placeholder uses the same circle with a 1px
  `var(--color-cover-border)` edge.
- **Vertical centering:** `margin-top: 3px` nudges the avatar to visually center
  within its left-column budget (avatar tile + 8 px gap + handle row).

**Name row (top of card).**

- 13 px body font, `font-weight: 700`.
- `padding: 6px 8px` (6 px vertical / 8 px horizontal) — gives the title visible
  breathing room from the card border and the hairline below it.
- CSS ellipsis truncation:
  `white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%`
  — long channel names ellipsize, short names render in full.

**Stat grid (right column).**

- 3-column CSS Grid: `grid-template-columns: 1fr auto auto` — number / unit /
  arrow, in that left-to-right order (locked; flips an earlier
  `arrow / number / unit` sketch).
- Number cell: `justify-self: end` so the three number right edges align at the
  same x against the unit label. `font-variant-numeric: tabular-nums` keeps
  digit widths consistent across rows.
- Unit cell: `justify-self: start` so the three unit left edges align.
- Arrow cell: `justify-self: end`, sitting at the card's right edge with ~6 px
  right padding (via the right-column padding).
- Stat font-size: 13 px (body default).
- Column gap: 6 px.

**Trend arrows.** Use the §"Trend indicators" glyph + color family (`▲ / – / ▼`,
`--color-trend-up|steady|down`).

**Footer (right column only).**

- Hairline (`border-top: 1px solid var(--color-border)`) and footer copy live
  inside the right-column wrapper, so the left column extends down through where
  the footer would otherwise have spanned full-width.
- Footer content: a single `[YouTube Studio]` `BracketedLinkComponent` link
  pointing to `https://studio.youtube.com/channel/<youtube_channel_id>`. The
  brand-names-capitalized rule supplies the "YouTube Studio" copy (not
  `[studio]`).
- `BracketedLinkComponent`'s auto-external detection emits
  `target="_blank" rel="noopener noreferrer"` automatically.

**Inert this phase.** No Stimulus controllers, no actions other than the two
external `<a>` tags (handle + Studio). Wave A1 ships with `Channels::MockData`
feeding the component; Wave B swaps the data source for real `Channel` /
analytics records.

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
renders the dialog itself, and the screen never interrupts a user action
mid-click. The action-confirmation framework (`ConfirmModalComponent`,
`shared/_action_screen.html.erb`, `DeletionsController` / `SyncsController`)
covers in-screen destructive intent; it cannot cover off-screen navigation, tab
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
container so it reads as separate from the screen background. Reserved for **"save
this now" / one-time-reveal surfaces** — content the user must capture because
it cannot be re-shown.

**Visual properties.**

- 1px `var(--color-border)` border
- `var(--color-pane-bg)` background tint
- 0 `border-radius` (per §"Density and decoration" universal rule)
- 16px inner padding
- 16px vertical outer margin (`margin: 16px 0`)

```css
.framed-block {
  margin: 16px 0;
  padding: 16px;
  border: 1px solid var(--color-border);
  background: var(--color-pane-bg);
  border-radius: 0;
}
```

**When to use.**

- Highlighted content blocks where the visual frame helps the user register
  "this is important / save this / one-time view".
- OAuth applications post-create screen — wraps the `client_id` + `client_secret`
  credentials list (the secret is shown exactly once and cannot be retrieved
  later).
- Future: API token plaintext displays, secret-shown-once flows, game cover-art
  reveals, any other capture-now surface.

**When NOT to use.**

- Every block on a screen. The frame is signal — overusing it degrades the signal
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
  screens also use it.
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
Single-pane surfaces inherit the screen background (no zebra). Apply the same
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

- Full width for data-heavy screens (videos), constrained for sparse screens
  (channels: 900px, forms: 480px)
- No shadows, gradients, rounded corners
- No icon fonts — HTML entities only (▲ ▼ ◀ ▶ − + ×)
- Header: fixed, 32px height, `(n)` keycap theme toggle on right
- Multi-column: flex-wrap with min-width for responsive stacking
- Dashboard: 2-column flex layout with 400px min-width per column

## Layout chrome (TST + BST + content)

Locked 2026-05-20 (FB-88). The top status bar (`<header>` wrapping
`Tui::TopStatusBarComponent`) and the bottom status bar
(`Tui::BottomStatusBarComponent` / `.bsb-bar`) are always present at viewport
top and bottom respectively. The content `<main>` block always fills the
exact viewport height between them — there is no awkward dead space between
the last panel and the BST.

- **TST is sticky at viewport top** (`<header>` uses `position: sticky;
  top: 0`).
- **BST is fixed at viewport bottom** (`.bsb-bar` uses `position: fixed;
  bottom: 0; left: 0; right: 0`). Was `sticky` until FB-88; `fixed` is the
  lock so the bar paints at the literal viewport bottom on short pages too.
- **Both chrome bars are ~22px tall** (4px padding-top + 13px line + 4px
  padding-bottom + 1px border, per FB-76).
- **Content area fills `100vh - 44px`** via `main { min-height: calc(100vh
  - 44px) }`.
- **Content has `padding-bottom: 22px`** (BST height) so the last content
  row never sits hidden behind the fixed BST.
- **Last panel per column grows** to absorb leftover vertical space within
  multi-column screen layouts (`.settings-panes--v3`'s last-child rule is
  the canonical example: notifications stays content-sized, security grows
  to reach the BST; in the right column the lone stack panel grows to fill
  the column track).
- **Overflow scrolls INSIDE the panel** when content exceeds available
  height. Intermediate state: `overflow: auto` exposes the themed
  scrollbar. End state (FB-12 / FB-61): sub-cursor j/k drives scroll
  within the panel and the mouse scrollbar is hidden.

TUI parity: Ratatui's standard layout (`Constraint::Length` for TST + BST
rows, `Constraint::Min` for the content middle row) replicates this 1:1.
The web layout is the visual counterpart to the future Rust client's
top-level pane geometry.

### Cable-per-panel (cross-ref to architecture.md)

UI updates are panel-scoped. Channel naming is `pito:<screen>:<panel>`
(with `pito:<screen>:<panel>:<sub-panel>` for sub-panels and
`pito:status_bar` for the cross-screen TST channel). Every `<form>` is
Turbo by default; controllers respond with `head :no_content` /
`render turbo_stream:` / `turbo_frame` — never `redirect_to` inside a
panel-scoped action. See `docs/architecture.md` →
"Turbo-everywhere + cable-per-panel" for the full operational contract.

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

The saved-views row sits at the top of every list screen that supports saving a
workspace URL. Phase 4 §9.3 promoted the row to a **horizontal scroll layout at
every breakpoint** — desktop and mobile alike. The row no longer wraps onto a
second line; it scrolls horizontally and clips overflow with a fading edge cue.

- `.saved-views-list` — flex row, `flex-wrap: nowrap`, `overflow-x: auto`,
  scroll-snap optional. Outer container.
- `.saved-views-row` — the inner item track. Each saved-view label sits in this
  row as a `[label]` bracketed link plus a separator dot.

This rule is global — it overrides any per-screen styling that previously allowed
the row to wrap. The component (`SavedViewsSectionComponent`) emits both
classes; screens that compose saved-views inline must use the same shape.

### Horizontal scrollbars

pito uses a themed horizontal scrollbar in place of the browser default for any
container that scrolls horizontally. The convention:

- **Thickness**: 6px on both axes, sitewide. The unsuffixed
  `::-webkit-scrollbar` rule applies to vertical scrollbars (body, modals,
  textareas) as well as horizontal — the OS default vertical bar is themed away
  too. Firefox uses `scrollbar-width: thin` on `html` for both axes.
- **Track**: `var(--color-bg)` — blends with the screen background.
- **Thumb**: `var(--color-muted)` — visible but subtle.
- **Thumb hover**: `var(--color-text)` — clearly indicates interactivity.
- **Thumb border-radius**: 0 (per §"Density and decoration" universal rule).

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

## Brand assets

Locked 2026-05-19 — the legacy `public/Pito.png` logo was retired in favor of a
multi-size favicon set + Android-Chrome PWA icons. A second favicon iteration
landed the same day, refining the logo design while keeping every path below
unchanged. **Every brand-render surface in the Rails app routes through one of
the paths below — no other logo files live in `public/`, and no surface
references `/Pito.png` anymore.**

### Canonical asset paths (`public/`)

| Asset                         | Path                           | Native size |
| ----------------------------- | ------------------------------ | ----------- |
| Favicon (browser tab, small)  | `/favicon-16x16.png`           | 16 × 16     |
| Favicon (browser tab, hi-dpi) | `/favicon-32x32.png`           | 32 × 32     |
| Favicon (legacy `.ico` slot)  | `/favicon-32x32.png` (via 301) | 32 × 32     |
| Favicon (taskbar / bookmark)  | `/favicon-48x48.png`           | 48 × 48     |
| Favicon (header logo source)  | `/favicon-64x64.png`           | 64 × 64     |
| Favicon (Windows tile)        | `/favicon-96x96.png`           | 96 × 96     |
| Favicon (About modal source)  | `/favicon-128x128.png`         | 128 × 128   |
| Favicon (manifest medium)     | `/android-chrome-192x192.png`  | 192 × 192   |
| Favicon (general hi-dpi)      | `/favicon-256x256.png`         | 256 × 256   |
| Favicon (manifest large)      | `/android-chrome-512x512.png`  | 512 × 512   |
| Apple touch icon              | `/apple-touch-icon.png`        | 180 × 180   |

### Surface-by-surface usage

| Surface                               | Asset                         | Display size      |
| ------------------------------------- | ----------------------------- | ----------------- |
| Header logo (`layouts/application`)   | `/favicon-64x64.png`          | 14 px             |
| Footer logo (`layouts/application`)   | `/favicon-64x64.png`          | 10 px             |
| `AboutModalComponent` logo            | `/favicon-128x128.png`        | 64 × 64           |
| `og:image` (social card / Open Graph) | `/android-chrome-512x512.png` | native            |
| OAuth `logo_uri` (RFC 7591 extension) | `/android-chrome-192x192.png` | native            |
| MCP `logo_uri` (RFC 9728 extension)   | `/android-chrome-192x192.png` | native            |
| `/favicon.ico` request                | 301 → `/favicon-32x32.png`    | 32 × 32           |
| `manifest.json` icon entries          | 192 + 512 px android-chrome   | per manifest spec |

The header + footer logos source from the 64 px asset and downscale via inline
CSS — 64 px gives ~4× density on a 14-16 px render, comfortable for retina. The
About modal sources from the 128 px asset for ~2× density on its 64-px render.

### Logo render conventions

- **Favicon-as-logo surfaces use `border-radius: 0`** — square brand assets,
  sharp corners per §"Density and decoration". They are NOT circular avatars;
  the 50% radius rule from §"Channel avatars" applies to YouTube channel
  artwork only.
- **`alt="pito"`** on every `<img>` tag — lowercase, matches the brand treatment
  in copy.
- **External-link wrappers** (footer logo → pitomd.com) follow the §"External
  links — new tab convention" attribute pair.

### Astro landing page (`extras/website/`) — dark only

The Astro-rendered landing site at `extras/website/` ships with a **single dark
theme** — no light theme code, no theme toggle. Locked 2026-05-19. Enforced by
`<meta name="color-scheme" content="dark">` in `Base.astro`, which overrides the
visitor's system preference; the body background never flashes white during
load.

| Token (Astro `:root`) | Value     | Rails analogue                |
| --------------------- | --------- | ----------------------------- |
| `--bg`                | `#0f0f10` | Near-black, project-specific  |
| `--fg`                | `#f8f8f2` | `--color-text` (dark Dracula) |
| `--muted`             | `#8a8a93` | Project-specific muted gray   |
| `--link`              | `#bd93f9` | `--color-link` (dark Dracula) |

The Astro tree is independent of the Rails build, but the design language
overlaps deliberately:

- **Monospace stack** identical to the Rails app's font rule (§"Typography").
- **K-V grid pattern** for project metadata blocks mirrors the Rails §"Modal K-V
  content" subsection.
- **Palette parity** on `--fg` and `--link` with the Rails dark theme so the
  marketing surface reads as the same brand.

Astro-side changes do NOT propagate to the Rails CSS, and Rails palette
extensions do NOT auto-flow to Astro. Cross-surface drift is acceptable so long
as the four shared tokens above stay close — when the Rails dark palette shifts,
the Astro site is a manual follow-up sweep, not a build dependency.

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
  rendered in the tile — they belong on the game detail screen, not the shelf.
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
