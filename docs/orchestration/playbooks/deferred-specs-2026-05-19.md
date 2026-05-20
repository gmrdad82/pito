# Deferred specs playbook — 2026-05-19

This playbook is the input for the eventual RSpec consolidation phase ("the look
'n feel is validated, now we lock the behavior").

Every iteration-mode dispatch in the 2026-05-19 session shipped code without
specs (per CLAUDE.md "Iteration vs consolidation" rule). This playbook catalogs
the debt so the consolidation pass has a complete checklist.

## How to use this playbook

1. User signals "start spec consolidation" or similar.
2. Master dispatches RSpec agents to work through this list section by section.
3. Each agent writes specs for one section, runs `bin/test <files>`, marks
   complete by appending an entry to "Section completion log" at the bottom.
4. Existing specs that went RED due to mid-session refactors get rewritten first
   (see section 6) so the suite returns to a stable baseline before new coverage
   lands.
5. New behavior gets new specs (`build_stubbed` where possible, fast-loop
   discipline, per the project's testing.md).

## 1. NEW ViewComponents needing specs

The 2026-05-19 session shipped these components without specs. Path is the `.rb`
file; the matching `.html.erb` ships in the same dispatch.

### /channels Wave A1 — title bar + filter row + ID card shelf

- `app/components/channels/title_bar_component.rb` — title row, `[ + add ]` /
  `[ - remove ]` brackets, conditional rendering rules
- `app/components/channels/avatar_chip_component.rb` — circular avatar +
  checkbox; `1.4em + 4px` sizing; `-3px` vertical nudge; href generation per
  channel
- `app/components/channels/avatar_shelf_component.rb` — composes N avatar chips,
  scrolls horizontally
- `app/components/channels/id_card_component.rb` — landscape `314x158` card;
  circular avatar; landscape stats grid; YouTube Studio footer; optional
  `score:` arg renders `[NN]` top-right badge overlay

NOTE: there is no separate `id_card_shelf_component` — the canonical top-level
`ShelfComponent` is reused for the ID card row.

### /channels Wave A2-A10 variant gallery

Each section below ships 2–3 visual variants that render side-by-side on
`/channels`. The user picks one variant per section during validation
(`docs/orchestration/playbooks/channels-wave-a-validation-2026-05-19.md`); the
rejected variants get deleted in the cleanup pass that follows.

**Spec coverage targets ONLY the surviving variant per section.** Rejected
variants are deleted, not spec'd.

- `app/components/channels/basics_section_inline_component.rb` (V1)
- `app/components/channels/basics_section_card_component.rb` (V2)
- `app/components/channels/basics_section_separator_component.rb` (V3)
- `app/components/channels/top_content_list_component.rb` (V1)
- `app/components/channels/top_content_grid_component.rb` (V2)
- `app/components/channels/top_content_table_component.rb` (V3)
- `app/components/channels/window_summaries_tabs_component.rb` (V1)
- `app/components/channels/window_summaries_grid_component.rb` (V2)
- `app/components/channels/geography_list_component.rb` (V1)
- `app/components/channels/geography_bar_component.rb` (V2)
- `app/components/channels/geography_treemap_component.rb` (V3)
- `app/components/channels/demographics_pyramid_component.rb` (V1)
- `app/components/channels/demographics_grouped_component.rb` (V2)
- `app/components/channels/device_types_donut_component.rb` (V1)
- `app/components/channels/device_types_bars_component.rb` (V2)
- `app/components/channels/heatmap_grid_component.rb` (V1)
- `app/components/channels/heatmap_sparkline_component.rb` (V2)
- `app/components/channels/traffic_sources_list_component.rb` (V1)
- `app/components/channels/traffic_sources_split_component.rb` (V2)

### Shared / chrome

- `app/components/shelf_component.rb` — top-level rename of the former
  `Games::ShelfComponent`, with headless heading mode added and the scrollbar
  CSS encapsulated. `app/components/games/shelf_component.rb` is now a one-line
  `Games::ShelfComponent = ::ShelfComponent` alias — spec the canonical class;
  the alias only needs a `constantize` smoke.
- `app/components/about_modal_component.rb` — logo + K-V definition list
  (version / revision / env) + centered copyright + `[close]` bracketed link
- `app/components/search/everywhere_modal_component.rb` — mount, focus trap,
  context detection
- `app/components/search/everywhere_results_component.rb` — context-aware
  section ordering (games on /games, channels on /channels, etc.)
- `app/components/search/everywhere_section_component.rb` — thin wrapper after
  section-heading drop; verify it still renders the heading-less shape
- `app/components/search/everywhere_row_component.rb` — three kinds (game /
  bundle / channel) + type label aligned right + cover-less IGDB filter (drops
  rows with no cover)

NOTE: the user's brief mentioned `Games::RecommendedChannelsSectionComponent`
and `Games::ChannelRecommendationRowComponent` as "orphan, built but not wired"
— verification 2026-05-19 shows neither file exists under
`app/components/games/`. The recommendation **service**
(`app/services/games/channel_recommendation.rb`) shipped, but the view
components did not. Treat as out of scope for consolidation until the wiring
lands.

## 2. NEW services needing specs

- `app/services/channels/mock_data.rb` — 6 channels with all extended fields
  (`video_count`, `top_content`, `window_summaries`, `geography`,
  `demographics`, `device_types`, `viewer_time_heatmap`, `traffic_sources`,
  `yt_search_terms`); spec the shape contract
- `app/services/channels/demographics_mock.rb` — split out of `mock_data` due to
  a parallel-edit race during Wave A; spec the demographic buckets shape
  independently
- `app/services/channels/aggregator.rb` — 4+ aggregation methods
  (`subscribers_total`, `views_total`, `videos_total`, `watch_hours_total`,
  `window_summary`)
- `app/services/channels/voyage_indexer.rb` — composite text builder + Voyage
  embed + `update_columns(summary_embedding:)` upsert
- `app/services/meilisearch/channel_indexer.rb` — title / handle / description /
  keywords searchable; `add_documents` shape
- `app/services/games/channel_recommendation.rb` — `nearest_neighbors` on Voyage
  channel embeddings + 0–100 score mapping + threshold filter
- `app/services/search/everywhere.rb` — multi-source orchestrator + context
  ordering + per-source error isolation (one indexer down does not blank the
  modal)
- `app/services/formatting/compact_count.rb` — K / M / B tier transitions
- `app/services/formatting/compact_hours.rb` — European thousands separator, no
  K-compression
- `app/services/formatting/current_channel_filter_chips.rb` — dynamic year /
  month chip set derived from per-channel data

## 3. NEW jobs needing specs

- `app/jobs/channel_index_job.rb` — invokes `Meilisearch::ChannelIndexer` on a
  single channel id
- `app/jobs/channel_remove_index_job.rb` — removes a channel from Meilisearch on
  destroy
- `app/jobs/channel_voyage_index_job.rb` — invokes `Channels::VoyageIndexer` on
  a single channel id; respects the global Voyage enable toggle

## 4. NEW controllers needing specs

- `app/controllers/everywhere_search_controller.rb` — `#show` action (HTML for
  the modal mount + JSON branch for the autocomplete payload); context param
  wire-format; empty-query short-circuit; per-source failure tolerance assertion

## 5. NEW model behavior needing specs

- `Channel` — `has_neighbors :summary_embedding` configuration +
  `after_save_commit` Voyage callback enqueueing `ChannelVoyageIndexJob`
- `Channel` — `after_save_commit` Meilisearch sync via `ChannelIndexJob` +
  `after_destroy_commit` cleanup via `ChannelRemoveIndexJob`
- `Game` — `after_*_commit` ActionCable broadcasts driving live refresh on
  /games (verify the channel name + payload shape; gate that `silent: true`
  updates do not broadcast)

## 6. EXISTING specs that went RED (need rewriting)

These specs were not edited in the 2026-05-19 session but reference methods /
classes / file paths that the session refactored away. Each needs a rewrite
against the new shape before any new coverage lands.

- `spec/components/games/rating_heat_bar_component_spec.rb` — V3 method / class
  renames (`bubble_text` gone, `fill_glyphs` gone); rewrite against the current
  `RatingHeatBarComponent` public surface. RHM-V4 (continuous `=` bar) +
  RHM-V5 (flex bracket alignment + top-margin clearance) refactored this
  surface further; coverage targets to add when the rewrite lands:
  - `synthesized_score` class method — rating present, rating nil, edge
    values 0 / 100, out-of-range clamping; pair with `tier_for` companion
    that maps score → tier symbol
  - `TIERS` constant — verify the tier list (bad / mediocre / okay / good /
    great or current symbol set) and each tier's score boundaries
  - `overlay_left_percent` private method — clamps score to `[0, 100]`; test
    with negative, zero, 50, 100, 150 inputs
  - Render path — score nil — bar renders muted with no overlay (no tick,
    no bubble)
  - Render path — score 0 / 100 — bubble + tick anchor at left / right edge;
    `transform: translateX(-50%)` keeps the glyph centered
  - Render path — score 50 — bubble + tick centered
  - Render path — score 87 (mid-high) — gradient color at that position is
    correct (smoke check, not pixel-perfect)
  - `BAR_CELLS` constant — currently 60; document that the bar is a
    fixed-cell-count `=` string with the `__track` flex container handling
    alignment
  - Bracket flex behavior (RHM-V5) — `[` and `]` use `flex: 0 0 auto`;
    `__fill` uses `flex: 1 1 auto` + `overflow: hidden`; `]` always snaps to
    the parent's right edge regardless of pane width
  - Top margin clearance (RHM-V5) — `margin-top: 6px` provides clearance
    from the KV row above the bar on /games/:id
  - Visual / system spec (optional, deferred to consolidation) — render the
    bar inside a fake KV table parent at various pane widths and confirm
    `]` lands flush at parent right
  - Theme tokens used — `var(--color-rating-bad)`,
    `var(--color-rating-good)`, etc. (red is the ONE allowed non-destructive
    red per design.md exception); ensure no hardcoded colors leaked in
  - RHM-V6 (2026-05-19/20) — 7-band hard-stop gradient — the bar's
    background is a single `linear-gradient(90deg, …)` with 14 stops at
    fixed `0 / 14.28 / 14.28 / 28.57 / 28.57 / 42.85 / 42.85 / 57.14 /
    57.14 / 71.42 / 71.42 / 85.71 / 85.71 / 100` percentages, mapping to
    the 7-tier rating spectrum (`very-bad → bad → poor → fair → meh →
    good → excellent`). Each tier band occupies exactly `100 / 7 ≈
    14.28 %` of the bar width with hard color stops (no interpolation).
    Spec the exact gradient string against the rendered HTML / inline
    style and assert each band's start + end percentage matches the
    table above
  - RHM-V6 — score tick lands inside a single tier band — for `score = 50`
    (mid-fair tier), the tick's `left` % falls within `[42.85 %, 57.14 %]`
    so the underlying band color at the tick is `--color-rating-fair`.
    Add table-driven cases: `score 0 → very-bad band start`, `score 14 →
    very-bad band`, `score 50 → fair band`, `score 75 → good band`,
    `score 100 → excellent band end`
  - RHM-V6 — token-driven everything — gradient stops, bracket glyphs,
    and bubble background all reference `var(--color-rating-*)` tokens
    only; assert zero literal hex anywhere in the rendered markup
    (regex-grep the rendered HTML for `#` color literals and fail if any
    appear)
- `spec/components/games/time_to_beat_component_spec.rb` — V3 method renames
  (`HEAT_THRESHOLDS` gone, `PILLAR_COLOR` gone, `gradient_stops` gone,
  `pillar_cell_index` gone); rewrite against the adaptive-gradient
  per-pillar-color surface. TTB-V4 (2026-05-19/20) further refactored
  this surface; coverage targets when the rewrite lands:
  - 14-stop dynamic gradient — driven by 6 inline CSS custom properties
    `--ttb-p1 … --ttb-p6` computed per-game from the main / extras /
    completionist hour positions. The 7 rating-spectrum colors map onto
    the bar as: `excellent → good` (main segment) → `fair → meh`
    (extras segment) → `poor → bad → very-bad` (completionist segment).
    Spec the inline `style="--ttb-p1: …; --ttb-p2: …; …"` attribute on
    the rendered root and assert all 6 properties exist with numeric `%`
    values
  - `gradient_break_positions`
    (`app/components/games/time_to_beat_component.rb:244`) — returns a
    hash with keys `:p1 … :p6` of percentage values computed from
    main / extras / completionist hours. Table cases per edge-case
    fixture (see TTB fixtures below)
  - `tick_overlays`
    (`app/components/games/time_to_beat_component.rb:118`) — ALWAYS
    returns the 3 pillar ticks (main / extras / completionist) even
    when the underlying pillar hours are `nil` / `0`. Verify with the
    Red Dead Redemption fixture (`main = nil` → main tick rendered at
    `left: 0 %`). Footage tick is also always included even when
    footage data is missing (Witcher 3 fixture — `footage_manual = nil
    && footage_cached = nil`)
  - `pillar_label_data`
    (`app/components/games/time_to_beat_component.rb:168`) — returns 3
    entries always; assert the label text reads `—` (em-dash) when
    the underlying hours are `0` or `nil`
  - `footage_value_label`
    (`app/components/games/time_to_beat_component.rb:91`) — returns
    `"—"` when footage is `0` / `nil`; verify with the Witcher 3
    fixture and the Crimson Desert fixture
  - `footage_position`
    (`app/components/games/time_to_beat_component.rb:218`) — returns
    `0` when footage is `0` / `nil`; tick anchors at the left edge in
    that case
  - Tick color anchors — pillar ticks adopt their band-end rating
    color: main tick = `var(--color-rating-good)` (lime end of the
    main segment), extras tick = `var(--color-rating-meh)` (orange end
    of the extras segment), completionist tick = `var(--color-rating-
    very-bad)` (darkest red end of the bar). Footage tick uses
    `var(--color-text)` (white in dark theme). Assert the inline tick
    `style="background-color: var(--color-rating-*)"` for each tick
    role
  - Footage bubble shape — `num` + `▼` arrow column, matches the RHM
    `.rating-heat-bar__bubble` shape; bubble copy reads `—` (em-dash)
    when no footage data
  - Legend `|` glyphs — three legend pipes colored via inline
    `style="color: var(--color-ttb-*)"` (or the matching rating token),
    with NO border / outline / background on the glyph itself
  - Render path edge cases (see TTB fixtures below) — Pragmata
    (balanced 3-segment), RDR (`main = nil` collapses green + lime
    bands to `0 %` width), Crimson Desert (long-tail completionist
    dominates with poor / bad / very-bad sub-bands occupying ~87 % of
    the bar), Witcher 3 (footage missing → footage tick + bubble at
    `0 %` with em-dash bubble)
  - Theme tokens — every gradient color reference, tick color, legend
    glyph color, and bubble background uses `var(--color-rating-*)` /
    `var(--color-text)` / `var(--color-ttb-*)`; no literal hex anywhere

  TTB edge-case fixtures (actual DB values fetched 2026-05-20 via
  `Game.find_by(igdb_slug: …)` — `ttb_*` columns are seconds, footage
  is integer hours):

  | slug                       | main (s) | extras (s) | comp (s) | footage_manual | footage_cached |
  | -------------------------- | -------- | ---------- | -------- | -------------- | -------------- |
  | `pragmata`                 | 32400    | 51120      | 78480    | 0              | nil            |
  | `red-dead-redemption`      | nil      | 91297      | 164880   | 28             | nil            |
  | `crimson-desert`           | 216000   | 297000     | 2655000  | nil            | nil            |
  | `the-witcher-3-wild-hunt`  | 134552   | 257769     | 581483   | nil            | nil            |

  Converted to hours for sanity (seconds / 3600):

  - **Pragmata** — main 9.0 h, extras 14.2 h, completionist 21.8 h,
    footage 0 h. Balanced short-to-medium distribution; gradient bands
    spread across the bar with all three pillars visible.
  - **Red Dead Redemption** — main `nil`, extras 25.4 h, completionist
    45.8 h, footage 28 h. Expected: `p1 = p2 = 0 %` (green + lime bands
    collapse to 0-width slivers), extras tick lands near the middle,
    completionist tick lands near the right edge, footage tick lands
    between extras and completionist. Main tick + em-dash label render
    at `left: 0 %`.
  - **Crimson Desert** — main 60 h, extras 82.5 h, completionist 737.5 h,
    footage `nil`. Expected: main + extras pillars occupy tiny slivers
    at the left edge, completionist dominates ~87 % of the bar with the
    `poor → bad → very-bad` sub-band sequence; footage tick + bubble
    render at `0 %` with em-dash.
  - **The Witcher 3: Wild Hunt** — main 37.4 h, extras 71.6 h,
    completionist 161.5 h, footage `nil`. Expected: balanced 3-segment
    with completionist still largest; footage tick + bubble render at
    `0 %` with em-dash.
- `spec/requests/favicon_spec.rb` — `/favicon.ico` now serves the direct PNG (no
  redirect); also tracked in `docs/orchestration/follow-ups.md` "favicon_spec.rb
  redirect target update"
- `spec/components/games/shelf_component_spec.rb` — uses the old
  `Games::ShelfComponent` name; the canonical class is now top-level
  `::ShelfComponent` with `Games::ShelfComponent` as a one-line alias. Rewrite
  the spec against the canonical class; optionally add a one-liner
  `expect(Games::ShelfComponent).to eq(::ShelfComponent)`
- `spec/javascript/leader_menu_controller_spec.rb` — compact-mode prefix
  filtering + dead-end dismiss + lazy schema getter need positive coverage
  (already tracked in follow-ups.md "Deferred specs" section)
- `spec/system/games_index_spec.rb` — 2 TODO-skipped examples referencing genre
  nested-shelf headings; revisit alongside the surviving channels variants since
  the genre shelves reuse `ShelfComponent`
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` — `_light.svg` references
  gone after theme removal; verify the spec still asserts the single-dark
  fallback path post-edit (the edit was made; this is a green-confirm pass)
- `spec/components/games/cover_component_spec.rb` — `fallback_light_path` was
  renamed / removed; verify the spec edit already applied during theme-removal
  is still green

## 7. /channels Wave A1 + ID card iteration history

The `Channels::IdCardComponent` dimensions iterated multiple times during the
session:

1. `226 x 358` portrait first pass
2. `206 x 130` shrink
3. `217 x 344` taller variant
4. `232 x 146` short variant
5. `314 x 158` landscape with circular avatar + landscape stats grid + YouTube
   Studio footer (current locked state)

Plus the avatar chip received a `-3px` vertical nudge after the first visual
review.

**Spec the FINAL state only** (`314 x 158`, circular avatar, score badge
top-right when `score:` arg present). Intermediate states are git history, not
test surface.

## 8. SPEC files already touched by theme removal (verify still pass)

These files were edited during the theme-removal dispatch and the consolidation
pass simply runs them to confirm green. No further rewrite expected unless a
regression is found.

- `spec/javascript/theme_controller_spec.rb` (DELETED)
- `spec/javascript/leader_menu_controller_spec.rb` (themeToggle examples
  replaced with negative guards)
- `spec/system/settings_refactor_spec.rb` (`pito-theme` localStorage references
  swapped to negative guard)
- `spec/components/games/cover_component_spec.rb` (single-dark fallback)
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` (single-dark fallback)
- `spec/components/games/game_tile_component_spec.rb` (single-dark fallback)
- `spec/components/games/genre_tile_component_spec.rb` (single-dark fallback)
- `spec/components/bundles/empty_cover_placeholder_component_spec.rb`
  (single-dark)
- `spec/components/games/bundle_tile_component_spec.rb` (single-dark)
- `spec/assets/tailwind/cover_border_css_spec.rb` (single-theme)
- `spec/assets/tailwind/games_polish_css_spec.rb` (single-theme)

## 9. MCP-cut spec changes (already applied)

The MCP scope simplification cut shipped during this session removed the entire
MCP tool surface and the MCP server. Spec files touched by that cut:

- `spec/lib/scopes_spec.rb` (`Scopes::ALL == ["app"]`)
- `spec/models/api_token_spec.rb` (`Scopes::APP`)
- `spec/factories/api_tokens.rb` + `spec/factories/oauth_applications.rb`
  (`Scopes::APP`)
- `spec/lib/api/token_authenticator_spec.rb` (`Scopes::APP`)
- `spec/lib/tasks/tokens_rake_spec.rb` (single-scope)
- `spec/requests/oauth_authorization_spec.rb` (`Scopes::APP`)
- `spec/requests/api/auth_concern_spec.rb` (no-scope simulation rewrites)
- `spec/requests/api/footages_spec.rb` (no-scope simulation rewrites)
- `spec/requests/api/footages/frames_spec.rb` (no-scope simulation rewrites)

DELETED (gone with the MCP surface):

- `spec/javascript/theme_controller_spec.rb`
- `spec/services/notification_formatter/mcp_spec.rb`
- `spec/mcp/**` (all tool specs + server / resources / tool_auth specs)
- `spec/requests/mcp/**` (rack_app_auth, tool_registry, oauth_token acceptance,
  mcp_http)
- `spec/requests/oauth_scope_clip_spec.rb`
- `spec/support/api_token_context.rb`

These were all green per the cut dispatches at the time they landed. The
consolidation pass runs them as a green-confirm and removes any straggling
reference in support files / shared examples.

## 10. Behavior rules to add as regression guards

Each rule below was established or reinforced during the 2026-05-19 session and
benefits from a spec that guards it against future drift.

- **Modal footer left-align** (`docs/design.md` rule) — spec that confirm-modal
  footer renders no `margin-left: auto` and that the cancel / confirm bracketed
  links sit flush left
- **Channel avatar circular** (`border-radius: 50%`) — spec the
  `Channels::AvatarChipComponent` and `Channels::IdCardComponent` avatar
  elements render with the circle border-radius token
- **Trend glyphs `▲ – ▼`** — spec the sortable header markup +
  `RatingHeatBarComponent` + `Channels::IdCardComponent` stat row trend cells
- **Filter chip canonical primitive** — every chip surface uses
  `FilterChipComponent`; consider a structural test that fails when a view
  renders a `[ ... ]` chip without going through the component (grep-as-spec or
  a Rubocop cop)
- **Compact menu prefix dead-end dismiss** — `leader_menu_controller.js` closes
  the popup when the accumulated prefix has zero matches (already listed in
  follow-ups.md as a deferred spec)
- **Flat-key controller Turbo-nav lazy schema** — `flat_key_controller.js`
  resolves the keybinding schema lazily after Turbo navigation so a fresh page
  doesn't capture the stale schema
- **Section accent inheritance** — `body[data-section]` accent inheritance falls
  through into modals; spec that an opened modal on /channels inherits the
  section accent token (and is overridden by the modal's own narrow rule when
  present)
- **Score badge on `IdCardComponent`** — when the `score:` arg is present, the
  `[NN]` badge renders top-right with the correct heat-bar tier color; when
  `score:` is absent, the badge slot is empty
- **About modal copy contract** — version + revision + env K-V keys rendered
  exactly once, copyright line centered, `[close]` link bracketed (not
  `[ cancel ]`, per the close-vs-cancel rule in CLAUDE.md / design.md)

## 11. Open questions to resolve before / during consolidation

- /channels variant winners (user picks; rejected variants and their files get
  deleted before specs land)
- Whether to ship `Games::RecommendedChannelsSectionComponent` +
  `Games::ChannelRecommendationRowComponent` (the service exists but the view
  components do not). If yes, both ship as new components and enter section 1.
  If no, fold the service into a different consumer or drop it.
- DRACULA-SWATCHES-V2 PS-blue final pick (currently locked to Pale Cobalt
  `#7eb6ff`); if it changes, every chip / badge that consumes the token needs a
  re-snapshot
- Manual `pito:voyage:reindex_channels` cadence and a green-path spec for the
  rake task once channels are populated

## 12. Cross-references

- Wave A visual validation playbook —
  `docs/orchestration/playbooks/channels-wave-a-validation-2026-05-19.md`
- Theme-base-color refactor playbook —
  `docs/orchestration/playbooks/theme-base-color-refactor-2026-05-19.md`
- System-spec debt sweep —
  `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md`
- Channels + Live Updates handoff —
  `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
- Follow-ups deferred-specs section — `docs/orchestration/follow-ups.md`
  "Deferred specs (spec consolidation phase)"
- Phase plans — `docs/plans/beta/37-channels-revamp/plan.md` and
  `docs/plans/beta/38-games-channel-recommendations/specs/01-recommendation-system.md`
- Design tokens — `docs/design.md`

## Append-only convention

Future iteration-mode dispatches MUST append their deferred items here. Dispatch
prompts include: "before reporting done, append your deferred spec items to
`docs/orchestration/playbooks/deferred-specs-2026-05-19.md` per the existing
convention."

The master agent audits the playbook before kicking off the RSpec consolidation
phase and resolves all open questions in section 11 with the user first.

## Deferred Beta 4 specs

Iteration-mode Beta 4 dispatches append their deferred spec items here per the
append-only convention.

- TuiCursorController (app/javascript/controllers/tui_cursor_controller.js):
  - TAB / Shift-TAB cycle forward/backward
  - Ctrl-h/j/k/l directional nav
  - Focus index wraps correctly at ends
  - Skips when input/textarea/contenteditable focused
  - Skips when dialog[open] present
  - Sets data-tui-cursor-focused="yes" on current panel only
  - Calls scrollIntoView on focus change

- Tui::BottomStatusBarComponent (app/components/tui/bottom_status_bar_component.{rb,html.erb}):
  - Renders all 8 sections (home/calendar/channels/videos/projects/games/notifications/settings)
  - Current section gets .bsb-section--current class + section accent color
  - Mode lozenge changes per mode arg (:normal/:command/:search)
  - Sticky bottom positioning
  - ? help + : command hints rendered with section accent on key letters
  - All section labels lowercase

- Tui::SparklineComponent (app/components/tui/sparkline_component.{rb,html.erb}):
  - Empty values array renders empty string (no error)
  - All-zero series renders flat row of `▁` (lowest block) matching input length
  - Mixed series picks block index by `(v / max) * 6` rounded, clamped 0..6
  - Single-value series renders the top block `▇` (its own max)
  - Negative or float values do not raise; clamp logic holds
  - Renders inside a `<span class="tui-sparkline">` (one element only)

- Tui::ProgressBarComponent (app/components/tui/progress_bar_component.{rb,html.erb}):
  - Default width 10 cells; custom width arg honored
  - `current=0, total=0` renders all-empty bar (no div-by-zero) and `0/0` label
  - `current > total` clamps filled to width (no overflow)
  - Negative current/total coerced via `.to_i` and clamped to 0
  - Label uses tabular-nums (`.tui-progress__label`)
  - Output wraps bar in literal `[ ]` brackets per pito bracketed grammar

- Tui::FramedPanelComponent (app/components/tui/framed_panel_component.{rb,html.erb}):
  - No title arg -> no `<header>` rendered
  - With title -> `.tui-framed-panel__title` rendered + border-bottom
  - Block content rendered inside `.tui-framed-panel__body`
  - `with_body { ... }` slot renders when no block content given
  - `content` takes precedence over the body slot when both set
  - Wrapping `<section>` always emitted (single root)

- Tui::TableComponent (app/components/tui/table_component.{rb,html.erb}):
  - Headers render with `.tui-table__th--<align>` per `align:` array
  - Missing align entry defaults to `:left`
  - Empty rows array still renders thead (no `<tr>` in tbody)
  - Last row gets `.tui-table__row` class for border-bottom removal via :last-child
  - Cell content rendered raw (HTML-safe contract is caller's job)
  - 100% width default; respects ambient font-family

- Tui::BarChartComponent (app/components/tui/bar_chart_component.{rb,html.erb}):
  - Empty rows render an empty `<div class="tui-bar-chart">`
  - Bar width `%` computed against series max (not total)
  - `value_format:` Proc applied when present; default to_s otherwise
  - Zero-max series renders 0% bars (no div-by-zero)
  - 3-column grid (label / bar / value) via `display: contents` row wrapper
  - Bar uses `--section-accent` mix at 50% alpha (inherits ambient section color)

- Tui::HeatmapComponent (app/components/tui/heatmap_component.{rb,html.erb}):
  - Renders 7 day rows (Mon..Sun) regardless of `data:` key coverage
  - Missing day key OR missing hour index renders intensity 0
  - Intensity = `value / series_max` clamped to [0, 1]
  - All-zero data renders all-transparent cells (no errors)
  - Custom `hours:` array shrinks column count appropriately
  - Hour labels zero-padded to 2 chars (`'00'..'23'` style)

- Tui::PyramidComponent (app/components/tui/pyramid_component.{rb,html.erb}):
  - Bar widths computed against SHARED max across left + right (cross-side comparison)
  - Empty rows array renders empty `<div class="tui-pyramid">`
  - Zero-max series renders 0% bars (no div-by-zero)
  - Left bar uses `--dracula-green`, right bar uses `--dracula-purple`
  - Values render with literal `%` suffix in template
  - 5-column grid layout (left-value | left-bar | label | right-bar | right-value)

- Tui::TreemapComponent (app/components/tui/treemap_component.{rb,html.erb}):
  - Tile background opacity scales with share-of-total percent
  - `flex-grow` set to raw value (sizes proportionally)
  - Zero-total renders all 0% tiles (no div-by-zero)
  - Caller-provided ordering preserved (no internal sort)
  - Code + pct rendered as separate spans (caller can style independently)
  - Min tile dims (80×60) prevent collapse under heavy fragmentation

- Tui::HelpOverlayComponent (app/components/tui/help_overlay_component.{rb,html.erb}):
  - All 4 groups (global / section nav / panel nav / session) render
  - Bracketed keys formatted [?], [:], [SPACE], etc.
  - Section accent on group titles via cascade
  - Stimulus controller toggles on ? and Escape
  - Modal opens via showModal() (uses HTML dialog element)
  - Ignores ? when input/textarea/contenteditable focused
  - Ignores ? when Ctrl/Meta/Alt modifiers are held

### F3-DEEP-A (Beta 4 — 2026-05-20) — TUI revamp of remaining /settings views

- TOTP enrollment view (app/views/settings/security/totps/new.html.erb):
  - Renders QR code in TuiFramedPanelComponent
  - Numbered steps with lowercase headings
  - Backup codes in monospace tabular-nums
  - 6-digit TOTP input has TUI styling
  - [verify] action uses BracketedLinkComponent
- TOTP enrollment pane component (app/components/settings/totp_enrollment_pane_component.{rb,html.erb}):
  - Scan section wrapped in Tui::FramedPanelComponent with lowercase title
  - Seed pre-block uses tabular-nums + dark Dracula bg + hairline
  - [verify] submit button styled as bracketed link
  - QR white-bg inline-block preserved for cross-theme scan contrast
- Time zone pane (app/views/settings/_time_zone_pane.html.erb):
  - Detected + saved zones displayed muted
  - Select dropdown styled per TUI
  - [update] action rendered as bracketed link button
  - Lowercase h2 heading
- Webhook help modal (app/views/settings/webhooks/help/show.html.erb):
  - Wrapped in TuiFramedPanelComponent
  - Brand names capitalized in title ("webhook help — Slack" / "webhook help — Discord")
  - [close] muted (BracketedMutedLinkComponent) at bottom triggering webhook-help-modal#close
- Global form input styling (app/assets/tailwind/application.css):
  - All text/password/email/url/tel/number/search inputs + select + textarea use
    TUI dark bg (var(--color-bg-alt)) + hairline border + no shadow + 13px
    monospace inherit + 0 border-radius
  - Focus state: section accent border, no glow
  - Disabled state: muted color + not-allowed cursor
  - Specialized inputs (.totp-modal-box, .omnisearch-input, .bundle-title-input)
    keep their own styling via higher selector specificity
- Heading hierarchy (app/assets/tailwind/application.css):
  - h1-h6 all render at 13px bold per ADR 0016 single-font-size lock
  - Per-surface overrides (.webhook-help-content h1/h2/h3) keep their sizes
    via higher specificity
- Visual regression scope to check during consolidation:
  - /settings index — headings (was h1 18px / h2 14px, now uniform 13px)
  - /login + /signup forms — input styling change (dark bg vs white bg)
  - Any view rendering `<input type="text">` outside the specialized list

### F3-DEEP-B (Beta 4 — 2026-05-20) — sessions table + action-screen TUI

- Sessions::TableComponent (app/components/sessions/table_component.html.erb):
  - Renders `<table class="tui-table sessions-table">` (Approach B class
    swap — no component refactor)
  - Header row uses `.tui-table__th` family with explicit `--left` /
    `--right` align modifiers (checkbox + user-agent left, pinged right)
  - Row tags carry `.tui-table__row`; td tags carry `.tui-table__td`
    with align modifiers matching the header
  - Sortable header links (`sort_link_to` user-agent + pinged) survive
    the swap and continue to drive `?sessions_sort=&sessions_dir=` on
    `/settings`
  - Bulk-revoke wiring intact — `data-sessions-bulk-revoke-target` on
    header + per-row checkbox wrappers, `data-current` host element
    preserved on per-row span
  - Tui::CheckboxComponent + Tui::ChipComponent (`[this]` marker) +
    TooltipBadgeComponent (`[ip]`) all still mount inside the
    refactored cells
  - Empty-state branch (`sessions.any?` else) still renders
    `<p class="text-muted">no active sessions.</p>` (unchanged copy)
  - Verify the legacy `.sessions-table` arrow-positioning rules in
    application.css still apply because the `<table>` retains
    `sessions-table` as a secondary class

- shared/_action_screen.html.erb (TUI confirmation footer):
  - `submit_label:` accepts both bare label ("delete") and legacy
    `[wrapped]` label ("[ confirm cancel ]") — the partial detects +
    unwraps a single set of surrounding brackets before re-wrapping
    via `[<span class="bl">…</span>]`
  - Non-destructive render: `<button class="bracketed
    action-screen-submit">` (no `text-danger`)
  - Destructive render: `<button class="bracketed action-screen-submit
    text-danger">` — pink via `--color-danger`
  - Cancel link rendered via `BracketedMutedLinkComponent` (replaces
    the legacy inline `BracketedLinkComponent label: "cancel"`)
  - `data-keyboard-confirmation` on `<form>` + `data-keyboard-
    confirmation-cancel` on cancel link preserved (Esc + y keyboard
    contract from `keyboard_controller.js` intact)
  - `form_method:` :delete / :post / default :post all serialize the
    correct `_method` hidden field
  - The four call sites all render without Template::Error:
    - `/deletions/show.html.erb` (passes localized label)
    - `/deletions/show_youtube_connection.html.erb` (legacy
      `[confirm revoke]` wrapped label)
    - `/deletions/_calendar_entry.html.erb` (legacy `[ confirm
      cancel ]` wrapped label)
    - `/syncs/show.html.erb` (localized "sync" label)

- application.css additions:
  - `button.bracketed.action-screen-submit` resets browser button
    chrome (no background, no border, no padding, inherits font)
  - Hover swaps `var(--color-link)` → `var(--color-link-hover)` (or
    `var(--color-danger)` → `var(--color-danger-hover)` in the
    destructive variant)
  - Inner `.bl` glyph inherits the parent button color (no separate
    color rule needed)
  - Pre-existing `.action-screen-footer` sticky-bottom rule is kept
    (still owns the sticky chrome the partial renders into)

## Section completion log

Entries added by the RSpec consolidation agents as they work through this list.
Format: `- YYYY-MM-DD — section N — <one-line note> — <commit SHA or pending>`.

- (none yet — consolidation has not started)
