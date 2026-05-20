# ADR 0016 — TUI design system and cable-first architecture (Beta 4 foundation)

## Status

Proposed — locked 2026-05-20 after exploratory discussion. Phase F1
dispatches gated on indicator pick.

## Context

After delivering ADR 0015 (theme system mathematical L1-L4 architecture) +
TTB v4 / RHM 7-band gradients + section accent fix + Astro Dracula
alignment, the user proposed a fundamental direction shift: make pito feel
like a TUI — interactive markdown / terminal app in the browser — to
enable Ratatui Rust client 1:1 feature parity. The session-long visual
refinements (Dracula palette, monospace, bracket links, `=` filler
characters, hard-stop gradients, drop zebra / pane-bg / borders) had
already pushed roughly 80% of the way toward this aesthetic; this ADR
formalizes the direction and locks scope decisions so Beta 4 can dispatch
against a fixed target.

The shift is not a rewrite. ADR 0015's theme architecture stays canonical;
RHM and TTB are explicitly untouchable. What changes is the visual grammar
(box-drawing borders, ASCII separators, Unicode block sparklines, vim-style
status bar, hjkl + arrow navigation) and the data flow (cable populates
reserved cells, no client-side rerender churn). Both shifts pay forward
into Ratatui parity.

## Decision

### Font: BitstromWera Nerd Font Mono (locked, bundled)

- 4 weights (Regular / Bold / Oblique / BoldOblique) self-hosted in
  `app/assets/fonts/` + `extras/website/public/fonts/`
- Nerd Font icon library available (3,600+ glyphs) for TUI-specific
  indicators
- `@font-face` declarations at the top of `application.css` +
  `global.css` (Astro)
- Body `font-family` prepended; existing fallback chain preserved

### Scope: desktop-only

- No mobile responsiveness target
- `body { min-width: 80ch }` recommended (TUI-readable floor)
- A static screen for mobile is acceptable
- This unlocks: ASCII box-drawing layouts, fixed character grids, no
  flex-box gymnastics

### Architecture: cable-first hybrid

- **First paint:** server returns layout shell with **reserved
  dimensions** + placeholder cells (`———`, `…`, or empty space)
- **Cable populates** the inner content of each cell without resizing
- **CLS guarantee = 0** via `min-width`, `min-height`, `aspect-ratio`,
  fixed character-grid sizes
- Single ActionCable channel per "panel" (one panel = one ViewComponent
  subscription)
- Ratatui Rust client uses the same cable streams — true 1:1 parity from
  day one
- TUI redraw feel: boxes drawn, then "wake up" with data

### Width and tiling — full viewport with TUI-readable floor

pito uses the entire viewport on wide screens (no max-width cap) while
guaranteeing a minimum width for TUI readability. Achieved via:

- `body { min-width: 80ch; width: 100vw; }` — no `max-width`
- Pane-based CSS Grid: `.pito-workspace { display: grid;
  grid-template-columns: repeat(auto-fit, minmax(60ch, 1fr)); }`
- Each panel declares its own `min-width` (typically 40-60ch)
- Panels tile horizontally when space allows; stack vertically on
  narrow screens — mirrors tmux/i3/Ratatui native behavior

Effect: 80ch → 1 column; 160ch → 2 columns; 240ch (4K) → 3 columns. Pure
CSS, no JS, no media queries. The TUI feel scales with viewport.

Panels can opt-OUT of tiling via `grid-column: 1 / -1` for surfaces that
benefit from the full row (e.g. wide analytic tables).

Status bar at bottom always spans full viewport via `position: sticky;
bottom: 0; width: 100%`.

### Specs mode: written as we go (suspends defer-specs rule)

The "Defer specs during iteration" feedback memory is SUSPENDED for Beta
4. Every dispatch includes RSpec for the ViewComponents / Stimulus
controllers / cable channels it adds. The existing deferred-specs
playbook (`docs/orchestration/playbooks/deferred-specs-2026-05-19.md`)
becomes the catalog of backlog items consumed by the consolidation pass.

### Visual primitives — ViewComponent-centric

Beta 4 builds a coherent TUI primitives library. Each component owns its
ERB template + class + spec; modes / variants are constructor arguments,
not template branches.

- `TuiFramedPanelComponent` — box-drawing borders (`╭─╮│╰╯`) with
  optional title
- `TuiStatusBarComponent` — fixed-bottom status bar (mode / section /
  time / hints)
- `TuiCursorIndicatorComponent` + `tui-cursor` Stimulus controller —
  hjkl + arrows + visible cursor marker (`>` prefix or inverted bg)
- `TuiIndicatorComponent` — animated busy indicator with TWO LOCKED VARIANTS:
  - `variant: :bounce_equals` (6-frame `=--- -=-- --=- ---= --=- -=--`)
    for ROW / LINE / HORIZONTAL contexts wider than ~10ch — full-width
    panel headers waiting for content, single-row status indicators,
    long horizontal strips
  - `variant: :braille` (10-frame `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏`) for SQUARE /
    RECTANGLE / BOX / CELL / SMALL-SPACE contexts — centered in cover
    images during composite regen, in the status bar / footer, inline
    alongside text in tight cells, replacing `[x]` during per-row bulk
    operations, in buttons during submit
  - Both support `start_offset:` prop for staggered instances so multiple
    indicators on a page don't sync up visually
- `TuiChipComponent` — inline tag (`[ip]`, `[active]`, `[this]`,
  `[admin]`) with variants: `:neutral` / `:info` (cyan) / `:success`
  (green) / `:warn` (orange) / `:danger` (pink) / `:current` (subtle
  inverse)
- `TuiCheckboxComponent` — extracted primitive for `[x]` / `[ ]`
  rendering. Used directly OR wrapped by `FilterChipComponent` (URL-param
  toggle), session selectors, webhook toggles, bundle multi-select
  pickers
- `TuiSparklineComponent` — Unicode block sparkline (`▁▂▃▅▇`)
- `TuiProgressBarComponent` — ▓░ characters
- `TuiTableComponent` — hairline + spacing model (image 60 style)
- `TuiBarChartComponent` — horizontal bars (image 63 style)
- `TuiHeatmapComponent` — day × hour cell grid (image 64 style)
- `TuiPyramidComponent` — demographic split (image 62 style)
- `TuiTreemapComponent` — proportional tiles (image 64 style; or simpler
  bar-list alternative if TUI parity is tough)
- `TuiModeIndicatorComponent` — vim-style mode display in status bar
- `TuiHelpOverlayComponent` — `?` modal listing all keybindings

All components have isolated RSpec specs (`ViewComponent::TestCase`).

### Visual conventions — single font size + strikethrough rule

- **Single font size everywhere.** Base 13px, monospace (BitstromWera
  Nerd Font Mono). No `h1` / `h2` / `h3` size differentiation. Section
  headers use bold weight, not larger size. Visual hierarchy comes from:
  `font-weight` (regular 400 / bold 700) + `font-style` (normal / italic
  / bold-italic) + Nerd Font glyphs + color. Locks the character grid.

- **Destructive action pattern (universal):** `[x]` checkbox selects
  rows + confirmation dialog confirms + cable removes. ONE pattern for
  every destructive flow. `TuiCheckboxComponent` renders the checkbox;
  the existing `_action_screen.html.erb` + `DeletionsController` /
  `SyncsController` confirmation framework renders the dialog.

- **Strikethrough — transient deletion animation ONLY.** Strikethrough
  text is reserved for the brief moment after the user confirms a
  destructive action and BEFORE cable removes the row from the panel.
  Pure visual transient feedback. Strikethrough is NEVER a primary
  selection indicator — `[x]` checkbox is the only selection marker.

- **Tabular numbers right-aligned, labels left-aligned.** Standard TUI
  data alignment. Use `font-variant-numeric: tabular-nums` for any cell
  rendering numbers — guarantees character-grid alignment across rows.

### Per-row destructive flow — braille replaces `[x]`, strikethrough marks transient deletion

The universal `[x]` + confirmation-dialog pattern (locked above) has a
specific per-row flow during bulk destructive operations:

1. User selects multiple rows with `[x]` checkboxes
2. User triggers bulk action (revoke / delete / sync / etc.)
3. Confirmation dialog (via the `_action_screen.html.erb` framework)
4. User confirms → cable starts the operation per row
5. Each affected row's `[x]` is REPLACED by a `TuiIndicatorComponent`
   `variant: :braille` instance (centered in the same checkbox cell —
   1 character, fits perfectly)
6. Optionally during the destructive transient: row text gets
   strikethrough applied (the only place strikethrough is allowed —
   pure visual feedback that the row is being removed)
7. Cable broadcasts the removal → Turbo Stream removes the row from the
   panel → next row's braille → ... → completion

This gives the user clear per-row status: pending rows still show
braille, completed rows are gone from the panel, failures (if any)
surface a row-level error indicator (separately specced — likely a
status chip).

Same flow applies for bulk sync, bulk import, any cable-driven
multi-record operation. Strikethrough is reserved EXCLUSIVELY for this
transient deletion window between confirm and cable removal.

### Component scope locks

- **TTB (`TimeToBeatComponent`)** — game detail page ONLY. No
  generalization. The 14-stop dynamic gradient + multi-tick machinery
  stays specific to ttb_main / ttb_extras / ttb_completionist / footage
  semantics. YAGNI: extract a base only if a SECOND use case appears.

- **RHM (`RatingHeatBarComponent`)** — game detail + channel affinity on
  `/games/:id`. The 7-tier hard-stop gradient is general-purpose for any
  0-100 score. Channel affinity (Voyage similarity score on recommended
  channel ID cards) gets the same RHM treatment as game ratings — strong
  visual coherence.

### /settings revamp decisions — Phase F3 scope

User-driven walkthrough captured these decisions for Phase F3:

| Section          | Decision                                                                                                                                                                                                                                                                            |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Profile          | CUT entirely. Replaced by Rake tasks: `pito:user:rename` + `pito:user:password_set`. Controllers + routes + views + specs deleted in F3.                                                                                                                                            |
| Discord + Slack  | UNIFIED into single Notifications panel. Each integration keeps its own webhook URL input (encrypted via ActiveRecord encryption + obfuscated via `Formatting::WebhookUrlMask`). The `[x] all` + `[x] daily digest` toggles become SHARED across both integrations.                  |
| Sessions         | KEEP. Redesign requirements: (1) current session marked via `TuiChipComponent variant: :current`; (2) bulk multi-select via `TuiCheckboxComponent` rows + bulk revoke action; (3) confirmation dialog via existing framework.                                                        |
| Stack            | KEEP all data. Visual redesign: 2-column tile on wide screens; each subsystem (Postgres / Meilisearch / Redis / Voyage / assets / notes) gets status chip via `TuiChipComponent`; metrics in tabular-nums; hairline separators; [reindex] action in danger pink.                     |

The mandatory-2FA gate (per CLAUDE.md hard rule — post-session redirect
to /settings/security/totp until TOTP enrolled) is UNTOUCHED.
Browser-only gate; API tokens + MCP bearer surfaces exempt by design.

### Compound cover art — recompute flow (cable-driven)

Bundle composite covers (multiple games stitched into one image) keep
the existing compositor. The lifecycle:

1. User adds / removes a game from a bundle
2. Backend enqueues a composite recompute Sidekiq job
3. Web UI immediately overlays the cover with `TuiIndicatorComponent`
   (`variant: :bounce_equals`) — bundle cover shows "being updated"
4. Job runs `Bundles::CompositeBuilder` (or whatever the existing
   compositor is named), writes the new image to assets
5. Backend broadcasts the new image URL via the bundle's cable channel
6. Client swaps the cover, removes the indicator overlay

Strong cable-first parity — Ratatui client would receive the same update
event and re-render its (text-only or low-res) representation. One
image, one source of truth, cable-pushed updates.

### Cover art — locked decisions

- Channel avatars: **KEEP**, drop borders (currently `border-radius: 50%`
  on circular crop)
- Video thumbnails: **KEEP** when /videos is reactivated
- Single game covers: **KEEP**, drop borders (S9 absorbed into Beta 4)
- Compound bundle covers: **B for short-term** (stitched composite,
  borderless) → **C for long-term** (mini-grid ASCII layout with atomic
  thumbnails)

### Indicator style — TBD, gated on user pick

User to pick from `tmp/demo-indicators.html` (12-15 animated variants).
The locked pick becomes `TuiIndicatorComponent`'s default frames. The
component supports a `start_offset:` prop to stagger instances.

### Keybindings — extended scope

Phase A keybindings (flat `/`, `g`, `q`, `?`, 2-letter rebinds, leader
menu) survive. Beta 4 adds:

- `h j k l` — directional navigation
- Arrow keys — directional navigation (alias of hjkl)
- `:` — command palette (TUI / vim style; supersedes some omnisearch
  use cases)
- Mode-aware behavior (NORMAL / SEARCH / COMMAND / HELP)
- Status bar reflects current mode

### Beta plan retrospective — planned for Phase F8

When Beta 4 closes, a delta document captures: what was planned in Beta 3
/ earlier, what shipped, what was dropped, what's still valid pending
consideration. Reuses `docs/orchestration/follow-ups.md` for live
tracking.

### Theming — unchanged

ADR 0015 (L1-L4 mathematical theme architecture, 12 Dracula atoms + 5
section accents + ~100 L3 tokens via `color-mix` + L4 effects) stays
canonical. Beta 4 adds TUI primitive tokens (e.g.
`--color-indicator-fg`, `--color-indicator-mute`) as needed but the
L1-L4 architecture is invariant.

### RHM and TTB — untouched

User explicitly locked these as untouchable. Beta 4 may add new
components AROUND them but does not modify them.

### User's 8 rules — codified

1. TUI parity: if a web feature cannot render in Ratatui, pick the
   minimalist approach satisfying both clients.
2. Everything is open for refactor (keybindings, copy, navigation,
   code).
3. Avatars + thumbnails kept, borders dropped. Compound cover art:
   B → C evolution.
4. Beta plan retrospective at F8 close — planned / dropped / still-valid
   delta.
5. No dead code — CSS, JS, RSpec, Ruby all cleaned as we go.
6. ViewComponent-centric for isolated specs.
7. RHM + TTB untouched.
8. Theming color conclusions preserved (ADR 0015 invariant).

### Phase plan

| Phase | Scope                                                                                                            | Sessions |
| ----- | ---------------------------------------------------------------------------------------------------------------- | -------- |
| F1    | Foundation — ADR 0016 lands, indicator picked, status bar, help overlay, cursor controller, cable architecture spec | 1-2      |
| F2    | TUI primitives ViewComponent library + RSpec                                                                     | 1        |
| F3    | /settings revamp (apply walkthrough decisions)                                                                   | 1-2      |
| F4    | /games revamp (cover borders dropped, chips + shelves TUI-styled)                                                | 2        |
| F5    | /channels revamp (variant picks locked, cable-populated, real YouTube wiring)                                    | 2-3      |
| F6    | Home dashboard (TUI canvas — fresh design)                                                                       | 1        |
| F7    | Modals + About + navigation polish                                                                               | 1        |
| F8    | Cleanup + Beta plan retrospective + design.md + CLAUDE.md updates + commit                                       | 1        |

**Total: 8-12 sessions.**

## Consequences

- Existing Beta 3 /channels Wave A (mocked layout + 19 variants in tree)
  gets re-evaluated. Variant _visual languages_ survive per user
  image-captured picks; specific layouts are re-decided in F5.
- ADR 0015 theme architecture preserved + extended.
- Mobile is deprecated. Mobile users see a static fallback message OR a
  degraded narrow-desktop layout.
- Charts (Chart.js / Chartkick) likely retired — replaced by TUI
  primitives. Saves ~80KB JS.
- Specs become co-resident with code — every dispatch ships its specs.
- Ratatui client gains a clear data contract via cable channels.

## Alternatives considered

- **Stay course with Beta 3 incremental polish.** Rejected. Does not
  push toward Ratatui parity; cumulative drift toward the TUI direction
  was already happening organically.
- **Full ASCII layouts everywhere (no CSS borders).** Rejected. Brittle
  to font / browser variations; CSS-borders-for-structure +
  ASCII-for-accents is the proven mix.
- **Drop Astro landing.** Rejected. Astro is the public marketing
  surface; stays in sync via shared L1 atoms + font.
- **Use Stimulus / Turbo for all updates (no cable).** Rejected.
  Cable-first enables Ratatui parity from day one without backporting
  later.

## Date

2026-05-20

## Related

- ADR 0015 — Theme system mathematical derivation (theming foundation;
  preserved)
- `docs/orchestration/checkpoint-2026-05-20-theme-revamp.md` —
  pre-Beta-4 state snapshot
- `docs/orchestration/playbooks/deferred-specs-2026-05-19.md` — spec
  backlog catalog
- `docs/orchestration/follow-ups.md` — open work + cron / schedule
  decisions
- `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md` —
  /channels Wave A plan (re-evaluated in F5)
- `docs/design.md` — visual rules canonical (Phase F8 update target)
- `CLAUDE.md` — hard rules (Phase F8 update target: cable-first +
  specs-as-we-go + Beta 4 references)
