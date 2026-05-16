# 07 — Platform logos on tile footer + detail page

> Phase 27 v2 spec. Adds platform-logo glyphs to two surfaces: (a) the
> small footer line of each game tile on `/games` and (b) the LEFT pane of
> the game detail page (per spec 08), where logos render at 4× the tile-
> footer size. Logos are shipped as static SVG assets in the repo so the
> page works offline and the visual style stays consistent with the
> project's design system.

---

## Goal

Every game tile on `/games` carries a compact `<rating> · <year> ·
<logo>` footer that surfaces the primary platform at a glance. The detail
page (spec 08's LEFT pane) renders the same logos at ~64 px (4× the
~16 px footer logo). The detail page decomposes the legacy `PC` umbrella
into per-storefront logos (Steam, GoG, Epic), shown only when the game is
on each respective store.

---

## Scope in

- Ship 5 static SVG assets under `app/assets/images/platform_logos/`:
  - `ps5.svg`
  - `switch2.svg`
  - `steam.svg`
  - `gog.svg`
  - `epic.svg`
- Helper `platform_logo_tag(slug, size:)` that emits an `<img>` /
  `<svg>` tag for the slug at the given pixel size.
- Tile footer: extend `_tile.html.erb` to append `· <logo>` after the
  existing year. The logo is the PRIMARY platform the user owns the
  game on (if owned) OR the most-likely-played platform (if not owned;
  see Behavior). When no platform applies, omit the logo segment
  entirely.
- Detail page (LEFT pane in spec 08): render logos for every platform
  the game is RELEASED ON, sized at 64 px. Decompose PC →
  Steam/GoG/Epic per the game's `external_*_id` columns. Show ONLY
  PS5, Switch2, and (if any) Steam/GoG/Epic.
- Architect lean: ship as STATIC svg assets, NOT via Google's favicon
  service. The favicon service requires the page to make a network
  request per tile, leaks the user's library shape to Google, and
  varies in style (Google returns whatever the site's favicon is).
  Static assets are offline-friendly, consistent, and version-
  controlled. Pin the recommendation.

## Scope out

- Per-store linking from the logo (the detail page's existing
  "[steam] / [gog] / [epic]" link list under "stores" stays — the
  logo is decorative, not interactive).
- Animated logos / hover effects.
- Custom Xbox handling (Xbox is DROPPED from the chip set per spec
  06).
- Per-tile decomposition into multiple logos on the index page (one
  logo per tile, not multiple). Decomposition is a detail-page-only
  pattern.

---

## Files to change

### Static assets (NEW)

- `app/assets/images/platform_logos/ps5.svg`
- `app/assets/images/platform_logos/switch2.svg`
- `app/assets/images/platform_logos/steam.svg`
- `app/assets/images/platform_logos/gog.svg`
- `app/assets/images/platform_logos/epic.svg`

Asset constraints:

- Single-color (monochrome) SVGs so they pick up the page text color
  via `fill="currentColor"`. The architect's choice; alternative is
  full-color brand SVGs, which fight the design system's monochrome
  feel. Pin "currentColor" for consistency. If the user wants brand
  color on the 64 px detail-page logos, surface as an open question.
- Square viewBox sized for clean rendering at 16 px AND 64 px (the
  same SVG must look crisp at both sizes — pick a viewBox like
  `0 0 32 32` and trust SVG scaling).
- Filename matches the platform slug exactly so the helper can
  build paths from the slug.
- `alt`-style accessible name in the helper (the `<img>` tag carries
  `alt="<canonical short name>"`).

### Helper

- `app/helpers/platform_logos_helper.rb` (NEW)
  - `platform_logo_tag(slug, size:)` → returns an `<img>` tag
    pointing at `image_path("platform_logos/#{slug}.svg")` with
    inline `width: #{size}px; height: #{size}px;` and `alt=
    Platform::CANONICAL_SHORT_NAMES[slug]`.
  - Returns nil (or empty `safe_buffer`) when the slug is not in
    the 5-asset set. Documented.
  - Constant `KNOWN_LOGOS = %w[ps5 switch2 steam gog epic].freeze`.
  - Helper `game_index_tile_logo_slug(game) -> String | nil` —
    picks the ONE platform slug to render in the tile footer.
    Selection rule, in order:
    1. The alphabetical-first slug from `game.owned_platforms`
       intersected with `KNOWN_LOGOS` (if any).
    2. The alphabetical-first slug from `game.platforms_available`
       intersected with `KNOWN_LOGOS` (if any).
    3. Nil — no logo segment renders.
  - Helper `game_detail_logo_slugs(game) -> Array<String>` —
    returns every slug from `KNOWN_LOGOS` that applies to the
    game, in `KNOWN_LOGOS` order. Inclusion rule:
    - `ps5` if the game is released on the PS5 `Platform` row
      (via `game.platforms_available` carrying the canonical
      `ps5` slug).
    - `switch2` if released on the Switch 2 `Platform` row.
    - `steam` if `game.external_steam_app_id.present?`.
    - `gog` if `game.external_gog_id.present?`.
    - `epic` if `game.external_epic_id.present?`.

### Tile footer

- `app/views/games/_tile.html.erb`
  - The existing meta line renders `<rating> · <year>`. Extend to
    `<rating> · <year> · <logo>` when
    `game_index_tile_logo_slug(game)` returns a slug. The middle
    dot separator between year and logo is rendered with
    `aria-hidden="true"` matching the existing rating/year
    separator pattern.
  - Logo size: 14 px (current meta line font is 10 px — 14 px logo
    aligns vertically with the meta text via inline
    `vertical-align: middle`). Confirm at implementation time;
    the user prompt said "~16px" — 14 px is a tested alternative
    that often reads cleaner against 10 px text. Pick 14 or 16,
    document.

### Detail page

- `app/views/games/show.html.erb` (current; spec 08 owns the full
  rewrite — coordinate)
  - In the LEFT pane, after the genre row, render a flex row of
    `platform_logo_tag(slug, size: 64)` for each slug returned by
    `game_detail_logo_slugs(@game)`. When the slug list is empty,
    render nothing (no placeholder block).

---

## Behavior contracts

### Asset path

- All five logos live at `app/assets/images/platform_logos/<slug>.svg`.
- Served by the asset pipeline at `/assets/platform_logos/<slug>-<digest>.svg`.
- The helper uses `image_path("platform_logos/#{slug}.svg")` so the
  digest fingerprinting is automatic.

### Tile-logo selection (one logo per tile)

- Priority: owned platform (alphabetical first within
  `KNOWN_LOGOS`) → available platform (alphabetical first) → none.
- This means an unreleased game still shows a logo if IGDB reports
  it as available on a known platform (e.g. `ps5` for a PS5 launch
  title).
- Games released ONLY on Xbox (not in the 5-logo set) render NO
  logo segment.

### Detail-page logo set (multiple logos)

- Returns 0..5 slugs in this fixed order: `ps5, switch2, steam,
  gog, epic`. Skips any slug whose inclusion condition is false.
- The decomposition rule for PC → Steam / GoG / Epic relies on the
  `external_*_id` columns IGDB populates during sync. A game with
  `external_steam_app_id` set is "on Steam"; no
  `external_steam_app_id` means "not on Steam" (regardless of
  whether IGDB lists a generic `PC (Microsoft Windows)` platform
  row).
- Layout: horizontal flex row with `gap: 8px`. Logos render at
  `width: 64px; height: 64px;`.

### Color

- Logos use `fill="currentColor"` in the SVG. The wrapping element
  (page body) sets the text color from the active theme, so light
  theme renders dark logos and dark theme renders light logos.
- If the user wants brand color (PS5 blue, Steam blue, Epic black,
  GoG purple, Switch red), surface as an open question. Default:
  monochrome.

---

## Migrations

None.

---

## ViewComponents

None new. The logo rendering is helper-based to keep the
per-render cost low (no ViewComponent allocation per tile).

---

## Stimulus controllers

None.

---

## Spec coverage required

### Helper spec (`spec/helpers/platform_logos_helper_spec.rb`)

- `platform_logo_tag("ps5", size: 16)` → renders an `<img>` with
  the right `src` (asset path + digest), `width="16"`, `height="16"`,
  `alt="PS5"`.
- `platform_logo_tag("evil", size: 16)` → returns nil.
- `game_index_tile_logo_slug(game_owned_on_ps5)` → `"ps5"`.
- `game_index_tile_logo_slug(game_owned_on_steam_and_gog)` →
  `"gog"` (alphabetical first within `KNOWN_LOGOS` order).
  CAVEAT: the priority list says "alphabetical first within
  `KNOWN_LOGOS`" — the order in `KNOWN_LOGOS` is `[ps5, switch2,
  steam, gog, epic]`; "alphabetical first" means `epic`
  alphabetically. Clarify at implementation: pick ONE rule (either
  alphabetical, OR `KNOWN_LOGOS` order). Architect lean:
  `KNOWN_LOGOS` order (so `ps5` always wins if owned). Open
  question.
- `game_index_tile_logo_slug(game_unreleased_on_ps5_only)` →
  `"ps5"` (available platform fallback).
- `game_index_tile_logo_slug(game_xbox_only)` → nil.
- `game_detail_logo_slugs(game_on_ps5_steam_gog)` →
  `["ps5", "steam", "gog"]`.

### View specs

- `spec/views/games/_tile.html.erb_spec.rb` — extend:
  - Tile for a game with a known logo renders the `<img>` after
    the year.
  - Tile for a game with no known logo renders no `<img>`
    (regression: the meta line still renders for rating+year).
- `spec/views/games/show.html.erb_spec.rb` — extend:
  - Detail page renders 64-px logos for every applicable
    platform.
  - Detail page renders ZERO logos when no platform applies.

### System spec

- ONE scenario in `spec/system/games_index_spec.rb` — seed three
  games (PS5-owned, Steam+GoG-owned, Xbox-only) → visit `/games`
  → assert each tile's footer logo (or absence).

---

## Manual test recipe

1. Place SVGs at `app/assets/images/platform_logos/{ps5,switch2,steam,gog,epic}.svg`.
2. `bin/dev` → open `http://localhost:3000/games`.
3. A PS5-owned game's tile footer reads `87 · 2026 · <ps5 logo>`.
4. A Steam+GoG-owned game's tile footer reads
   `78 · 2025 · <ps5-priority or steam-or-gog logo>` per the
   pinned priority rule.
5. An Xbox-only game's tile footer reads `81 · 2024` (no logo).
6. Click into a game detail page (spec 08 layout) — LEFT pane
   shows 64 px logos for every applicable platform. No logo set
   when the game has no known platform.
7. Switch themes (light ⇄ dark) — logos invert via
   `currentColor`.

---

## Open questions

1. **Static asset vs Google's favicon service.** Architect lean:
   static. Pin this as the choice unless the user objects.
2. **Tile-logo priority rule — `KNOWN_LOGOS` order vs alphabetical
   first.** Architect lean: `KNOWN_LOGOS` order (so PS5 always
   wins for a PS5+Steam owner). Confirm.
3. **Tile-logo size — 14 px vs 16 px.** Pick the size that aligns
   cleanly with the 10 px meta text. The user prompt said
   "~16px"; 14 px tested better against 10 px text in past
   surfaces. Verify visually at implementation.
4. **Brand color vs monochrome `currentColor`.** Architect lean:
   monochrome. Brand color fights the design system's red-only-
   for-destructive rule (PS5 blue is fine but Steam blue
   conflicts with link color, Epic black has no contrast in dark
   theme, etc.).
5. **SVG source — where do the assets come from?** Architect
   lean: design the architect / docs agent fetches a single SVG
   from the relevant brand's press kit, simplifies to a single-
   color silhouette suitable for `currentColor`. The implementer
   does NOT generate these; the user provides them OR the
   architect issues a follow-up to design.
6. **PS5 / Switch 2 — distinguish from PS4 / Switch (gen 1)?**
   Per `Platform::IGDB_ID_TO_CANONICAL_SLUG`, the project only
   tracks PS5 (167) and Switch 2 (508). PS4 / Switch 1 games
   render NO logo on their tiles. Confirm this is the intended
   behavior. Alternative: render the PS5 logo for PS4 games too
   (since they share the brand). Architect lean: keep
   distinct — render no logo for PS4 / Switch 1.
