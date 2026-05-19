# ADR 0015 — Theme system: mathematical color derivation (L1-L4 architecture)

## Status

Proposed — 3 of 6 open decisions locked 2026-05-19 (Q1/Q2/Q3 below); Q1
simplified further to v4 on 2026-05-20 (one `--color-danger` token instead
of the v3 two-tier destructive/danger split). Remaining 3 open decisions
(Q4-Q6) need user lock before Phase 3 dispatches.

## Context

pito's theme system was stripped to dark-only earlier this session
(2026-05-19). The Astro landing is also dark-only with Dracula Purple. This
ADR proposes a layered architecture where every color in the app is derived
mathematically from a small set of L1 atoms — no hand-picked literals
scattered through CSS/components/views.

Four parallel Explore audits (2026-05-19) inventoried the current color
usage:

- **1A — CSS tokens:** 86 tokens in `:root`
  (`app/assets/tailwind/application.css` lines 10-207); 27 hardcoded hex/rgb
  literals OUTSIDE token definitions; section-cascade rules confirmed for 4
  sections at lines 229-241; modal re-pin to Purple at line 1959; no legacy
  theme blocks (strip is clean).
- **1B — Component literals:** 18 inline hex/rgba across 5 components
  (`platforms/chip_component.rb`, `channels/device_types_donut_component.rb`,
  `games/rating_score_chip_component.rb`,
  `channels/geography_treemap_component.html.erb`,
  `viewer_time_heatmap_component.rb`). Clean: `rating_badge_component`,
  `played_chip_component`, `demographics_*`.
- **1C — Views/helpers/JS literals:** 17 findings —
  `application_helper.rb:294` CHART_PALETTE (5 hex), 8 Chart.js fallback hex
  in `application.js`, 3 SVG assets with hardcoded `#6272a4` + `#44475a`
  Dracula colors, `_needs_reauth_banner.html.erb` `#cc0000` ×2 (legacy
  destructive red — migrates to `var(--color-danger)` = Pink in Phase 3F).
- **1D — Tailwind utilities:** Zero baking. Codebase is fully token-based at
  the Tailwind layer.

Top hex duplicates: `#282a36` (×6 — flash bgs), `#44475a` (×4), `#ff5555`
(×4 — danger/fail/flash-error/rating-bad), `#50fa7b` (×4), `#bd93f9` (×3 —
section-accent/chart-1/keycap), `#6272a4` (×3).

## Decision

### L1 — Raw palette (atoms, immutable). 12 tokens.

Dracula palette + 1 derived atom. L1 atoms never reference each other.

```css
--dracula-bg:           #282a36
--dracula-current-line: #44475a
--dracula-fg:           #f8f8f2
--dracula-comment:      #6272a4
--dracula-cyan:         #8be9fd
--dracula-green:        #50fa7b
--dracula-orange:       #ffb86c
--dracula-pink:         #ff79c6
--dracula-purple:       #bd93f9
--dracula-red:          #ff5555
--dracula-yellow:       #f1fa8c
--pale-cobalt:          #7eb6ff   /* derived for /games section accent */
```

The 1 non-Dracula atom (`--pale-cobalt`) is an intentional addition — it
carries semantic meaning that the Dracula palette doesn't directly cover:

- `--pale-cobalt`: /games section accent (PlayStation-blue feel, distinct
  from Cyan which is too similar to other tokens).

No separate `--destructive-red` atom. Every "this is bad" surface — errors,
flash-error, deletes, reindex, form validation failures, dangerous actions —
routes to a SINGLE `--color-danger` token at L3 which resolves to
`--dracula-pink` (Q1 v4 lock — see below). The v3 two-tier
destructive/danger split is removed: one token covers all critical/error/
destructive semantics. `--dracula-red` retreats to exactly two narrow roles:
the Channels section accent and the rating spectrum's "bad" gradient anchor.

### L2 — Section accents (picks from L1, with cascade)

```css
--section-accent-home:     var(--dracula-purple)
--section-accent-channels: var(--dracula-red)
--section-accent-games:    var(--pale-cobalt)
--section-accent-settings: var(--dracula-orange)

body[data-section="home"]     { --section-accent: var(--section-accent-home);     }
body[data-section="channels"] { --section-accent: var(--section-accent-channels); }
body[data-section="games"]    { --section-accent: var(--section-accent-games);    }
body[data-section="settings"] { --section-accent: var(--section-accent-settings); }

/* Modals re-pin to Home Purple unless section-bound */
dialog { --section-accent: var(--section-accent-home); }
```

### L3 — Semantic tokens (derived via color-mix math).

Strict rule: every L3 token is a var() reference to L1/L2 OR a color-mix()
of L1/L2. Zero literal hex permitted at L3.

```css
/* Surfaces */
--color-bg:           var(--dracula-bg)
--color-bg-tint:      color-mix(in srgb, var(--section-accent) 4%,  var(--dracula-bg))
--color-bg-alt:       color-mix(in srgb, var(--dracula-fg)      3%, var(--dracula-bg))
--color-bg-hover:     var(--dracula-current-line)
--color-pane-bg-a:    color-mix(in srgb, var(--dracula-fg)      6%, var(--dracula-bg))
--color-pane-bg-b:    color-mix(in srgb, var(--dracula-fg)      8%, var(--dracula-bg))

/* Text */
--color-text:         var(--dracula-fg)
--color-muted:        var(--dracula-comment)
--color-text-dim:     color-mix(in srgb, var(--dracula-fg) 60%, var(--dracula-bg))

/* Borders */
--color-border:       var(--dracula-current-line)
--color-input-border: var(--dracula-comment)

/* Links — section-aware (Q2 LOCKED) */
--color-link:         var(--section-accent)
--color-link-hover:   color-mix(in srgb, var(--section-accent) 80%, white)
--color-link-visited: color-mix(in srgb, var(--section-accent) 70%, var(--dracula-comment))

/* Status — Q1 v4 LOCKED — ONE token for all critical/error/destructive
   surfaces. The v3 two-tier (destructive vs danger) split is removed. */
--color-danger:  var(--dracula-pink)    /* covers: errors, flash-error, deletes,
                                           reindex, form validation failures,
                                           dangerous actions, anything
                                           semantically "this is wrong / bad" */
--color-fail:    var(--color-danger)    /* alias */
--color-success: var(--dracula-green)
--color-warn:    var(--dracula-orange)

/* Trend indicators */
--color-trend-up:     var(--dracula-green)
--color-trend-steady: var(--color-muted)
--color-trend-down:   var(--color-danger)   /* going bad = single Pink token */

/* Flash messages — error flavor routes through --color-danger */
--color-flash-bg:               var(--dracula-bg)
--color-flash-notice-text:      var(--dracula-cyan)
--color-flash-success-text:     var(--dracula-green)
--color-flash-warning-text:     var(--dracula-orange)
--color-flash-error-border:     var(--color-danger)
--color-flash-error-text:       var(--color-danger)

/* Rating spectrum — keeps Dracula Red (rating-quality spectrum semantic,
   separate from "error" — Red here means "bad rating", not "bad action") */
--color-rating-excellent: var(--dracula-green)
--color-rating-good:      color-mix(in srgb, var(--dracula-green) 60%, var(--dracula-yellow))
--color-rating-fair:      var(--dracula-yellow)
--color-rating-meh:       var(--dracula-orange)
--color-rating-poor:      color-mix(in srgb, var(--dracula-orange) 60%, var(--dracula-red))
--color-rating-bad:       var(--dracula-red)
--color-rating-very-bad:  color-mix(in srgb, var(--dracula-red) 50%, black)

/* TTB ticks (locked 2026-05-19, separate ADR scope) */
--color-ttb-main:          var(--dracula-green)
--color-ttb-extras:        var(--dracula-cyan)
--color-ttb-completionist: var(--dracula-pink)
--color-ttb-footage:       var(--dracula-yellow)

/* Charts */
--color-chart-1: var(--dracula-purple)
--color-chart-2: var(--dracula-green)
--color-chart-3: var(--dracula-pink)
--color-chart-4: var(--dracula-orange)
--color-chart-5: var(--dracula-cyan)
--color-chart-grid: var(--color-border)

/* Misc */
--color-cover-border:         color-mix(in srgb, var(--dracula-fg) 30%, var(--dracula-bg))
--color-cover-placeholder-bg: var(--dracula-bg)
--color-channel-id-card-bg:   var(--color-pane-bg-a)
--color-tooltip-bg:           color-mix(in srgb, var(--dracula-bg) 95%, black)
--color-backdrop:             color-mix(in srgb, black 80%, transparent)
--color-keycap:               var(--dracula-purple)
--color-keycap-hover:         color-mix(in srgb, var(--dracula-purple) 80%, white)
--color-zebra-bg:             color-mix(in srgb, white 2.5%, transparent)
```

Backend-rejected form fields (validation errors) render with
`--color-danger` — same Pink as flash errors, delete buttons, and all other
"this is bad" surfaces. There is intentionally NO separate destructive
token; the semantic is unified. Form-field error styling (border + helper
text) reuses `--color-danger` directly rather than introducing a
`--color-form-error-*` family.

### L4 — Effect tokens (state derivations)

```css
--color-chip-bg-active:    color-mix(in srgb, var(--section-accent) 20%, transparent)
--color-chip-bg-hover:     color-mix(in srgb, var(--section-accent) 12%, transparent)
--color-chip-border:       var(--section-accent)
--color-focus-ring:        color-mix(in srgb, var(--section-accent) 40%, transparent)
--color-disabled:          color-mix(in srgb, var(--color-text) 40%, var(--dracula-bg))
--color-row-hover:         color-mix(in srgb, white 4%, transparent)
```

### Bracketed link syntax — Q3 LOCKED

The canonical bracketed link convention is `[link]` (no spaces around the
label) — NOT `[ link ]`. Hover state inherits `--section-accent` so on
/games the hover flashes Pale Cobalt, on /channels flashes Red, etc.
`CLAUDE.md` and `docs/design.md` will be updated in Phase 4B to reflect
this; the migration of existing `[ ... ]` sites lands in Phase 3 as a
dedicated dispatch (gated on BRACKET-MIGRATE-SCOPE recon currently in
flight).

### Section categorization — which surfaces map to which section?

The `current_section` helper at
`app/helpers/application_helper.rb#current_section` maps `controller_path`
to a section bucket (home / channels / games / settings). The user
clarified 2026-05-19 that several auth-adjacent surfaces should map to
**settings**, not the default **home**:

- TOTP enrollment routes (`/settings/security/totp/*`,
  `Settings::Security::TotpsController` and any nested controllers)
- MCP authorization screens (Doorkeeper-driven
  `Oauth::AuthorizationsController` and related)
- Google OAuth authorization callbacks (`Oauth::Google*Controller` /
  YouTube connection callbacks)

These surfaces inherit `data-section="settings"` so the Dracula Orange
`#ffb86c` section accent applies (links, hover states, focus rings, chip
backgrounds, etc.). Implementation lands in Phase 3 as a dedicated dispatch
updating the helper's regex/map.

## Open decisions — Q4-Q6 (need user lock before Phase 3J/3E/3G/3H/3I)

Each item below must be explicitly locked. The implementation dispatches
will block on these.

**Q4 — Status badge palette tokenization.** The 7 inline literals in
`rating_score_chip_component.rb` + 7 in `application.css` `.status-badge--*`
rules. Two paths:

- A: Migrate ALL to `--color-badge-*` tokens (urgent / strong / warn /
  muted / code) under the L3 namespace. Cleanest.
- B: Keep inline; design accepts these as semantic exceptions.

**Q5 — Platform brand colors.** The 3 hex in `platforms/chip_component.rb`
(PS #003791, Switch #E60012, Steam #00ADEE). External brand identities.

- A: Tokenize under `--color-platform-*` namespace (literal hex inside the
  token def). Makes future audit/swap easier.
- B: Accept inline — these are externally-sourced brand colors, not
  derivable from palette math.

**Q6 — JS Chart.js fallbacks + SVG hardcoded Dracula colors.** Two related
cleanups:

- The 8 fallback hex in `app/javascript/application.js` are defensive
  against missing CSS vars (e.g. `Chart.defaults.color || "#555555"`). Keep
  them (defensive) or remove (strict token-only)?
- The 3 SVG assets (`controller_icon_dark.svg`,
  `game_cover_fallback_*_dark.svg`) use literal `#6272a4` + `#44475a`.
  Options: (a) leave as-is — these are atomic art assets; (b) migrate to
  `currentColor` + ensure wrapping element sets `color: var(--color-muted)`
  etc.

## Implementation phases (after Q4-Q6 lock)

| Phase | Scope                                                                                    | Wall-clock         | Parallel              |
| ----- | ---------------------------------------------------------------------------------------- | ------------------ | --------------------- |
| 3A    | Implement L1 raw palette (12 atoms) in application.css                                   | ≤5 min             | Sequential first      |
| 3B    | Confirm L2 section cascade (already in place)                                            | ≤3 min             | After 3A              |
| 3C    | Implement L3 semantic tokens (color-mix derivations)                                     | ≤10 min            | After 3A              |
| 3D    | Implement L4 effect tokens                                                               | ≤5 min             | After 3A              |
| 3E    | Migrate platform chip + device slice + rating chip + treemap + heatmap literals (per Q4/Q5) | ≤8 min each, 5 dispatches | After 3A-C, parallel |
| 3F    | Migrate legacy `#cc0000` sites to `var(--color-danger)` (= Pink): `_needs_reauth_banner.html.erb` ×2 + any incidental hits found in the same sweep | ≤4 min             | After 3C, parallel    |
| 3G    | Migrate `application_helper.rb` CHART_PALETTE → chart-N tokens                           | ≤4 min             | After 3C, parallel    |
| 3H    | Migrate JS Chart.js fallbacks (per Q6)                                                   | ≤4 min             | After 3C, parallel    |
| 3I    | Migrate SVG assets (per Q6)                                                              | ≤6 min             | After 3C, parallel    |
| 3J    | Migrate 27 inline CSS rule literals → tokens, including `status-badge--urgent` `#cc0000` → `var(--color-danger)` (= Pink) | ≤10 min            | After 3C              |
| 3K    | Bracketed link migration: `[ label ]` → `[label]` (gated on BRACKET-MIGRATE-SCOPE)       | ≤8 min             | After scope returns   |
| 3L    | Propagate L1 atoms to Astro `extras/website/src/styles/global.css`                       | ≤5 min             | After 3A, parallel    |
| 3M    | Section categorization helper — update current_section to map auth surfaces (TOTP/MCP/OAuth) to "settings" | ≤4 min | After 3A-C, ✅      |
| 4A    | Visual smoke check on /, /games, /channels, /settings — MANUAL gate                      | —                  | —                     |
| 4B    | Update `docs/design.md` + `CLAUDE.md` with new architecture + `[link]` convention        | ≤5 min             | After 4A              |
| 5A    | Bulk commit + push + Slack ping                                                          | ≤2 min             | After 4B              |

## Consequences

- Every color traces back to L1. Future palette swap = 12 hex edits. L1
  stays at exactly 12 atoms (Dracula 11 + Pale Cobalt) — no separate
  `--destructive-red` 13th atom and no v3-style two-tier status family.
- ONE token (`--color-danger`) shoulders the entire "this is bad"
  semantic: errors, flash-error, deletes, reindex, form validation
  failures, dangerous actions, trend-down. `--color-fail` is the only
  alias kept. There is intentionally NO `--color-destructive` token —
  every reviewer asking "should this be destructive or danger?" gets a
  single answer.
- All section variants behave uniformly without per-component theming
  logic.
- `color-mix()` browser support: 99%+ (Baseline). No fallback needed.
- Some L3 tokens that currently resolve to a Dracula atom directly gain a
  layer of indirection — slight readability cost but huge consistency win.
- 18 component literals + 17 view/JS literals + 27 CSS rule literals +
  bracketed-link spacing migration = ~70 sites migrated.
- Pink (`--dracula-pink`) shoulders ALL "bad things" semantic load —
  destructive actions, danger states, flash-error, form-validation
  errors, trend-down. Semantic load on a single atom is high but
  acceptable because the surrounding contexts (a `[delete]` confirmation
  button vs a TTB completionist tick vs a chart-3 line) disambiguate
  visually. Reviewers must still avoid stacking two Pink-routed tokens
  in the same composition (e.g. a Pink chart line behind a Pink flash
  banner) without an intervening neutral.
- Dracula Red (`--dracula-red`) retreats fully to exactly two surfaces:
  Channels section accent (`--section-accent-channels`) and the rating
  spectrum (`--color-rating-bad`, `--color-rating-very-bad`). Any new use
  of `var(--dracula-red)` outside those two surfaces is a smell and
  should reach for `--color-danger` (Pink) or `--color-warn` (Orange)
  instead.
- Legacy `#cc0000` sites (`_needs_reauth_banner.html.erb` ×2 +
  `.status-badge--urgent`) migrate to `var(--color-danger)` = Pink in
  Phase 3F / 3J. `#cc0000` is no longer a tracked token — after the
  migration sweep, a literal `#cc0000` anywhere in the tree is a bug.

## Alternatives considered

- **Single-flat token tier (no L1-L4 layering):** rejected. Without atoms,
  palette swaps require touching dozens of token definitions. Layered
  indirection wins.
- **Per-section duplicate token sets (`--home-color-link`,
  `--channels-color-link`, etc.):** rejected. Cascade via
  `body[data-section]` is cleaner; one `--color-link` token, four section
  values.
- **HSL-based mathematical derivation instead of `color-mix()`:** rejected.
  Dracula palette is hand-tuned for visual harmony; HSL rotation would
  drift from those values. `color-mix()` preserves the source colors.

## Date

2026-05-19

## Related

- `docs/decisions/0014-platform-chip-generation-collapse.md` — platform
  chip palette context.
- `docs/design.md` — visual system canonical doc (to be updated in
  Phase 4B).
- `CLAUDE.md` — hard rules (bracketed link convention, unified
  `--color-danger` Pink for all "bad things") (to be updated in
  Phase 4B).
- Astro landing palette parity — `extras/website/src/styles/global.css`.
