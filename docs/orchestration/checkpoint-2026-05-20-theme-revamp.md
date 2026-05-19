# Theme revamp checkpoint — 2026-05-20

**Last commit:** `03fc07f` (theme system mathematical refactor + TTB v4 +
simplifications)

**Purpose:** Snapshot of theme + visual polish work so we can resume here OR
pivot entirely. The next session opens with an exploratory discussion the user
wants to have that might push us in a totally different direction.

---

## 1. What landed (current state)

### Theme system — ADR 0015 (`docs/decisions/0015-theme-system-mathematical-derivation.md`)

Layered architecture in `app/assets/tailwind/application.css`:

- **L1 — 12 Dracula atoms** (immutable raw palette):
  `--dracula-{bg,current-line,fg,comment,cyan,green,orange,pink,purple,red,yellow}`
  + `--pale-cobalt`.
- **L2 — 5 section accents**: home Purple / channels Red / games Pale Cobalt /
  settings Orange / dialog re-pin Purple. Cascaded via `body[data-section]`.
- **L3 — ~100 semantic tokens** derived via `color-mix()` math from L1/L2. Zero
  literal hex permitted at L3.
- **L4 — effect tokens** (chip-bg-active, focus-ring, disabled, etc.) derived
  from L3.

Body bg now uses `--color-bg-tint` =
`color-mix(in srgb, var(--section-accent) 4%, var(--dracula-bg))` — every
section gets a subtle accent wash.

**Critical decisions locked (Q1-Q6 in ADR):**

- Q1 v4 — single `--color-danger: var(--dracula-pink)` covers errors /
  flash-error / deletes / form validation / dangerous actions. Dracula Red
  retreats to Channels accent + rating spectrum only. `#cc0000` fully purged.
- Q2 — links section-aware (`--color-link: var(--section-accent)`).
- Q3 — `[link]` no spaces canonical syntax. 8 inline migrations done.
- Q4 — status badge palette tokenized under `--color-badge-*`.
- Q5 — platform brand colors tokenized under `--color-platform-{ps,switch,steam}`.
- Q6 — JS Chart.js fallbacks kept (defensive); SVG migration deferred.

### Section-accent runtime fix

`<body data-section>` was preserved across Turbo Drive navigations from the
first page load. Fix: meta tag `<meta name="pito:section">` in head (Turbo
manages head merges) + JS shim listening to `turbo:load` / `turbo:render` /
`DOMContentLoaded` that copies meta content to
`document.body.dataset.section`.

### Section categorization

`current_section` helper at `app/helpers/application_helper.rb:20-69` now maps
auth-adjacent surfaces to "settings":

- `settings/*` (existing)
- `login/totp_challenges`
- `password_resets`
- `doorkeeper/*` (OAuth handshake)
- `oauth/registrations` (MCP dynamic-client register)
- `youtube_connections/oauth_callbacks` (Google OAuth callback)

### RHM (`RatingHeatBarComponent`) — V6

- 7-band hard-stop gradient at fixed 14.28% intervals
- Score tick lands on a single tier band (no interpolation blur)
- Token-driven; zero literal hex

### TTB (`TimeToBeatComponent`) — V4

- 14-stop **dynamic** gradient driven by 6 CSS custom properties (`--ttb-p1`
  through `--ttb-p6`) computed per-game from main/extras/completionist hour
  positions
- 7 rating-spectrum colors mapped: excellent → good (main), fair → meh
  (extras), poor → bad → very-bad (completionist)
- Bar widths reflect game shape — Crimson Desert's 737.5h completionist tail
  dominates 87% of the bar in red zones; Pragmata's tight 9/14/22h reads as
  balanced
- All 3 pillar ticks always render (em-dash label at 0% for missing data — RDR
  main = nil handled, Witcher 3 footage = nil handled)
- Footage bubble has num + ▼ arrow matching RHM bubble shape
- Legend `|` glyphs in tick colors (replaced CSS rectangles)
- Tick colors anchor to band-end rating colors

### Astro landing

- Dark-only, Dracula Purple `#bd93f9` accent
- Dracula bg `#282a36` everywhere (CSS + manifest + webmanifest + browserconfig
  + Apple/MS tile meta)
- L1 atoms shared with Rails (`extras/website/src/styles/global.css` lines
  22-51)
- Deployed to `https://435bfb3b.pito-website.pages.dev` (pitomd.com alias
  propagates)

### Simplifications S1+S2+S5

- S1 — zebra striping dropped; tables use `border-bottom` hairlines
- S2 — pane backgrounds dropped; vertical hairlines between sibling panes via
  `.pane + .pane { border-left }`
- S5 — `--color-text-bold` dropped (duplicate of `--color-text`); use
  `font-weight` for bold semantic
- ID card now FLAT (no card-specific bg), border-only

### Other

- OMNISEARCH `/` context-aware (section-specific modal if mounted, fallback to
  Everywhere) — `app/javascript/controllers/flat_key_controller.js`
- 8 bracketed-link inline `[ label ]` → `[label]` migrations in
  `app/views/videos/*` + `app/views/shared/_diff_table.html.erb`
- 23 inline CSS rule literals migrated to tokens (status-badge / platform-chip
  / heatmap / rating-score-chip / etc.)
- CHAN-A1.15 — ID card footer vertical hairline removed; component LOCKED

### Spec accumulation

Deferred-specs playbook at
`docs/orchestration/playbooks/deferred-specs-2026-05-19.md` extended with:

- RHM V6 coverage (3 bullets)
- TTB V4 coverage (11 bullets) + 4-game fixture table + per-fixture render
  expectations
- Edge-case games' real DB hours: Pragmata (9/14.2/21.8h), RDR (nil/25.4/45.8h,
  footage 28h), Crimson Desert (60/82.5/737.5h), Witcher 3 (37.4/71.6/161.5h,
  footage nil)

---

## 2. What's queued but NOT YET dispatched (Phase 3 paused for debate)

These were ready to fan out before the user paused for exploratory discussion:

### Visual simplifications (user already locked)

- **S8** — Drop `border-radius: 2px` everywhere. Sharp corners across all
  components, badges, cards. More terminal-y aesthetic.
- **S9** — Drop cover-art borders in `/games` (game detail page, bundle modal,
  grid + shelf). Covers float frameless.

### Component literal migrations (Q4/Q5 approval already locked)

- `platforms/chip_component.rb` SLUG_BRAND constant →
  `var(--color-platform-{ps,switch,steam})`
- `channels/device_types_donut_component.rb` SLICE_COLORS →
  `var(--color-device-*)` tokens (need to verify if these were added to `:root`
  by PHASE-3-CSS)
- `games/rating_score_chip_component.rb` TIER_BG_COLOR →
  `var(--color-rating-*)` tokens
- `channels/geography_treemap_component.html.erb` 2 white literals →
  `var(--color-text)`
- `viewer_time_heatmap_component.rb` rgba interpolation →
  `var(--color-link)` derivation

### Helper migrations

- `application_helper.rb` CHART_PALETTE array (5 hex) → token aliases
  referencing `--color-chart-{1..5}`

### SVG asset migrations

- `controller_icon_dark.svg`, `game_cover_fallback_grid_dark.svg`,
  `game_cover_fallback_shelf_dark.svg` → `fill="currentColor"` + wrapping
  `<span style="color: var(--color-muted)">`

### Section-accent visibility deep-dive

User reports section accent feels barely visible — page bg tint at 4% is
subtle, link colors may not pop enough across sections. If after a real visual
pass the difference is still too quiet, options:

- Increase bg tint percentage (4% → 6-8%)
- Apply accent to page header text / chrome elements
- More aggressive accent on hover states (currently
  `color-mix(... 80%, white)`)

---

## 3. Known open questions

- **Variant winners on /channels** — 19 variants across 8 sections sitting in
  tree from Wave A iteration. User still debating which to lock. Cleanup gated
  on this decision.
- **Cron/schedule decisions list** at `docs/orchestration/follow-ups.md` — 3
  Voyage reindex cadence questions (Games / Bundles / Channels) parked.
- **Page-level accent intensity** — is the 4% bg tint enough, or do we need
  more aggressive section-color signal?

---

## 4. What might come next (exploratory)

Phase 3 fan-out is **paused** at the user's request. The next session opens
with an exploratory discussion that may push the work in a totally different
direction than the queue above suggests.

When the new direction lands, this checkpoint becomes the "what we'd have done
otherwise" record. The Phase 3 queue items above can either:

- Be resumed verbatim (if the pivot is partial)
- Be re-prioritized (if the pivot reshapes priority)
- Be dropped (if the pivot supersedes them)

ADR 0015 (the L1-L4 theme architecture) stays canonical regardless — every
pivot direction inherits the atoms + section accents + math.

---

## 5. Reference links

- Theme architecture ADR:
  `docs/decisions/0015-theme-system-mathematical-derivation.md`
- Spec debt catalog:
  `docs/orchestration/playbooks/deferred-specs-2026-05-19.md`
- Follow-ups (open work items): `docs/orchestration/follow-ups.md`
- /channels Wave plan:
  `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
- Design system canonical: `docs/design.md` (NOT YET updated with ADR 0015
  changes — Phase 4B pending)
- CLAUDE.md hard rules (NOT YET updated with `[link]` syntax + Pink danger —
  Phase 4B pending)

---

## 6. Open dispatches at checkpoint

None — all parallel agents landed before commit `03fc07f`.
