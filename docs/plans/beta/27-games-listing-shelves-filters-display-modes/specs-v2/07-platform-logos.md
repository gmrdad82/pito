# 07 — Platform logos on tile footer + detail page (rake-downloaded favicons)

> Phase 27 v2 spec. Adds platform-logo glyphs to two surfaces: (a) the
> small footer line of each game tile on `/games` and (b) the LEFT pane
> of the game detail page (per spec 08). Logos are sourced from Google's
> favicon service via a one-shot Rake task that downloads the assets to
> `public/platform_logos/` at TWO sizes (16 px for tiles, 64 px for the
> detail page). The web renders the static PNG files — no render-time
> network calls, no per-tile latency.

---

## Goal

Every game tile on `/games` carries a compact `<rating> · <year> ·
<logo>` footer that surfaces the primary platform at a glance. The
detail page (spec 08's LEFT pane) renders the same logos at 56 px
(roughly 4× the 14 px tile-footer size). The detail page decomposes
the legacy `PC` umbrella into per-storefront logos (Steam, GoG, Epic),
shown only when the game is on each respective store.

Asset pipeline: a Rake task fetches each platform's favicon from
Google's favicon service ONCE, saves it locally at two sizes, and
checks the result into the project. The web app reads from
`public/platform_logos/<key>-<size>.png`. No runtime network calls.

---

## Scope in

- Rake task `pito:platform_logos:download` that downloads favicons for
  the 5 supported platforms from Google's favicon service and saves
  them to `public/platform_logos/` at two sizes.
- Helper `platform_logo_tag(slug, size:)` that emits an `<img>` tag
  pointing at the local PNG asset for the given slug and size.
- Tile footer: extend `_tile.html.erb` to append `· <logo>` after the
  existing year. The logo is the PRIMARY platform the user owns the
  game on (if owned) OR the most-likely-played platform (if not owned;
  see Behavior). When no platform applies, omit the logo segment
  entirely.
- Detail page (LEFT pane in spec 08): render logos for every platform
  the game is RELEASED ON, sized at 56 px. Decompose PC →
  Steam/GoG/Epic per the game's `external_*_id` columns. Show ONLY
  PS5, Switch2, and (if any) Steam/GoG/Epic.
- The Rake task is idempotent — re-running overwrites the local files
  with fresh downloads. Useful when a brand updates its favicon.

## Scope out

- Per-store linking from the logo (the LEFT-pane logos are decorative,
  not interactive — the stores link section is DROPPED per spec 08).
- Animated logos / hover effects.
- Custom Xbox handling (Xbox is DROPPED from the chip set per spec
  06).
- Per-tile decomposition into multiple logos on the index page (one
  logo per tile, not multiple). Decomposition is a detail-page-only
  pattern.
- Vector (SVG) assets — favicons from Google are raster PNGs at fixed
  sizes; we save the PNG bytes as-is.

---

## Files to change

### Rake task (NEW)

- `lib/tasks/pito_platform_logos.rake` (NEW)
  - Namespace: `pito:platform_logos`.
  - Task: `download`.
  - Invocation: `bin/rails pito:platform_logos:download`.
  - For each platform in the canonical mapping below, fetch from
    `https://www.google.com/s2/favicons?domain=<domain>&sz=<size>`
    for both `sz=16` and `sz=64`. Save to
    `public/platform_logos/<slug>-<size>.png`.
  - Domain mapping:
    | slug      | domain               |
    | --------- | -------------------- |
    | `ps5`     | `playstation.com`    |
    | `switch2` | `nintendo.com`       |
    | `steam`   | `steampowered.com`   |
    | `gog`     | `gog.com`            |
    | `epic`    | `epicgames.com`      |
  - Sizes: `16` (tile footer) and `64` (detail page). The detail page
    renders at 56 px but uses the 64 px asset for crispness on
    high-DPI displays.
  - Uses `Net::HTTP` (or `URI.open`) — no extra gem dependency.
  - Creates `public/platform_logos/` directory if missing.
  - Logs each download (`[pito:platform_logos] saved
    public/platform_logos/ps5-16.png (924 bytes)`).
  - On HTTP error (non-200), logs a warning and continues with the
    next platform; does NOT crash the task. The operator re-runs
    after fixing the network / domain issue.

### Static assets (downloaded — checked into git)

- `public/platform_logos/ps5-16.png` (and `-64.png`)
- `public/platform_logos/switch2-16.png` (and `-64.png`)
- `public/platform_logos/steam-16.png` (and `-64.png`)
- `public/platform_logos/gog-16.png` (and `-64.png`)
- `public/platform_logos/epic-16.png` (and `-64.png`)

These are committed binary artifacts — the Rake task is the
provenance, the files are the source of truth at runtime.

### Helper

- `app/helpers/platform_logos_helper.rb` (NEW)
  - `platform_logo_tag(slug, size:)` → returns an `<img>` tag with
    `src="/platform_logos/#{slug}-#{size}.png"`, inline
    `width: #{size}px; height: #{size}px;`, and
    `alt=Platform.display_label(canonical_name_for(slug))` (using
    the `PLATFORM_LABELS` map from spec 06). The src path is a
    plain `/public` reference — no asset-pipeline digesting.
  - Returns nil (or empty `safe_buffer`) when the slug is not in
    the 5-asset set. Documented.
  - Constant `KNOWN_LOGOS = %w[ps5 switch2 steam gog epic].freeze`.
  - Constant `LOGO_SIZES = [16, 64].freeze` — the only sizes the
    Rake task downloads; `platform_logo_tag` raises ArgumentError
    when given a size not in the list (to catch typos at boot).
  - Helper `game_index_tile_logo_slug(game) -> String | nil` —
    picks the ONE platform slug to render in the tile footer.
    Selection rule, in order:
    1. The first slug from `game.owned_platforms` intersected with
       `KNOWN_LOGOS`, walked in `KNOWN_LOGOS` declaration order (so
       `ps5` always wins when owned).
    2. The first slug from `game.platforms_available` intersected
       with `KNOWN_LOGOS`, same declaration-order walk.
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
  - Logo size: **14 px** (tile-side LOCKED). The Rake-downloaded
    16 px asset is rendered at 14 px via inline `width: 14px;
    height: 14px;` — the 2 px scale-down preserves crispness and
    aligns vertically against the 10 px meta text. Vertical
    alignment via inline `vertical-align: middle`.

### Detail page

- `app/views/games/show.html.erb` (current; spec 08 owns the full
  rewrite — coordinate)
  - In the LEFT pane, after the genre row, render a flex row of
    `platform_logo_tag(slug, size: 56)` for each slug returned by
    `game_detail_logo_slugs(@game)`. The 64 px asset is rendered
    at **56 px** (detail-side LOCKED) via inline `width: 56px;
    height: 56px;`. When the slug list is empty, render nothing
    (no placeholder block).

---

## Behavior contracts

### Asset path

- All five logos live at `public/platform_logos/<slug>-<size>.png`
  at sizes `16` and `64`.
- Served by Rails / Puma as static files under `/public` — no asset
  pipeline digest, no fingerprint. The helper emits the raw
  `/platform_logos/<slug>-<size>.png` path.
- The Rake task is the only mechanism that writes these files.
  Operators re-run the task to refresh (e.g., when a brand changes
  favicons).

### Rake task contract

- `bin/rails pito:platform_logos:download` →
  - Iterates the 5-platform mapping.
  - For each, fetches `https://www.google.com/s2/favicons?domain=
    <domain>&sz=16` AND `sz=64`.
  - Saves response body bytes to
    `public/platform_logos/<slug>-<size>.png`.
  - Logs `[pito:platform_logos] saved <path> (<bytes>)`.
  - On non-200 response, logs `[pito:platform_logos] WARN: <slug>
    <size> fetch returned HTTP <code>; skipped.` and continues.
  - Returns success even if some downloads failed (operator's
    responsibility to re-run after fixing the issue).
- The task is documented at the top of the file with a comment
  block explaining the source (Google favicons) and re-run
  cadence (when a brand updates its logo).

### Tile-logo selection (one logo per tile)

- Priority: owned platform (first in `KNOWN_LOGOS` order) →
  available platform (first in `KNOWN_LOGOS` order) → none.
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
  `width: 56px; height: 56px;` (the 64 px source asset scales down
  cleanly).

### Color

- Favicons from Google are full-color brand assets — we render them
  as-is. The 14 px tile size keeps them visually compact; the 56 px
  detail size shows brand color clearly.
- No `currentColor` override — these are raster PNGs, not SVGs.

---

## Migrations

None.

---

## ViewComponents

None new. The logo rendering is helper-based to keep the
per-render cost low (no ViewComponent allocation per tile).

---

## Rake tasks

- `pito:platform_logos:download` (NEW) — see Files to change.

---

## Stimulus controllers

None.

---

## Spec coverage required

### Rake task spec (`spec/lib/tasks/pito_platform_logos_spec.rb`)

- Stub `Net::HTTP` (or `URI.open`) responses for each of the 10
  fetch combinations (5 platforms × 2 sizes).
- Run the task; assert each of the 10 expected files is written
  to `public/platform_logos/` with the stubbed bytes.
- Stub one fetch to return 500 → assert the task logs a warning
  and writes the other 9 files successfully.
- Use `Dir.mktmpdir` to isolate the write target during the test
  (override `Rails.public_path` for the duration).

### Helper spec (`spec/helpers/platform_logos_helper_spec.rb`)

- `platform_logo_tag("ps5", size: 16)` → renders an `<img>` with
  `src="/platform_logos/ps5-16.png"`, `width="16"`, `height="16"`,
  `alt="PS5"`.
- `platform_logo_tag("ps5", size: 64)` → src ends in `ps5-64.png`.
- `platform_logo_tag("evil", size: 16)` → returns nil.
- `platform_logo_tag("ps5", size: 32)` → raises ArgumentError
  (size not in LOGO_SIZES).
- `game_index_tile_logo_slug(game_owned_on_ps5)` → `"ps5"`.
- `game_index_tile_logo_slug(game_owned_on_steam_and_gog)` →
  `"steam"` (first in `KNOWN_LOGOS` order among the owned
  platforms — `ps5, switch2, steam, gog, epic`).
- `game_index_tile_logo_slug(game_unreleased_on_ps5_only)` →
  `"ps5"` (available platform fallback).
- `game_index_tile_logo_slug(game_xbox_only)` → nil.
- `game_detail_logo_slugs(game_on_ps5_steam_gog)` →
  `["ps5", "steam", "gog"]`.

### View specs

- `spec/views/games/_tile.html.erb_spec.rb` — extend:
  - Tile for a game with a known logo renders the `<img>` after
    the year at 14 px.
  - Tile for a game with no known logo renders no `<img>`
    (regression: the meta line still renders for rating+year).
- `spec/views/games/show.html.erb_spec.rb` — extend:
  - Detail page renders 56-px logos for every applicable
    platform.
  - Detail page renders ZERO logos when no platform applies.

### System spec

- ONE scenario in `spec/system/games_index_spec.rb` — seed three
  games (PS5-owned, Steam+GoG-owned, Xbox-only) → visit `/games`
  → assert each tile's footer logo (or absence).
- The scenario depends on the Rake task having been run; the
  spec setup either (a) runs the task in a `before(:all)` hook,
  or (b) stubs `File.exist?` and asserts only the `<img>` markup
  presence without requiring the actual PNG bytes. Architect
  lean: (b) — keep the spec fast and independent of network.

---

## Manual test recipe

1. Run `bin/rails pito:platform_logos:download` — task logs 10
   successful saves (5 platforms × 2 sizes) to
   `public/platform_logos/`.
2. `ls public/platform_logos/` shows 10 files: `ps5-16.png`,
   `ps5-64.png`, `switch2-16.png`, `switch2-64.png`, ...,
   `epic-64.png`.
3. `bin/dev` → open `http://localhost:3000/games`.
4. A PS5-owned game's tile footer reads
   `87 · 2026 · <ps5 favicon at 14px>`.
5. A Steam+GoG-owned game's tile footer reads
   `78 · 2025 · <steam favicon at 14px>` (Steam wins per
   `KNOWN_LOGOS` order over GoG).
6. An Xbox-only game's tile footer reads `81 · 2024` (no logo).
7. Click into a game detail page (spec 08 layout) — LEFT pane
   shows 56 px favicons in a row for every applicable platform.
   No logo set when the game has no known platform.
8. Re-run `bin/rails pito:platform_logos:download` — files
   overwrite cleanly; page reload still shows logos.
9. Delete `public/platform_logos/ps5-16.png` manually and reload
   `/games` — tiles for PS5 games now render a broken-image
   placeholder (browser default) but the page does not error.
   Re-run the Rake task to restore.

---

## Open questions

1. **Google favicon service rate limit / ToS.** Google's favicon
   service is intended for in-browser use; large batched
   downloads from a server may be rate-limited or against ToS.
   The Rake task is 10 requests total per run, infrequent —
   architect lean: acceptable risk. If Google blocks the
   downloads, fall back to manually-sourced PNGs from each
   brand's press kit.
2. **PS5 / Switch 2 — distinguish from PS4 / Switch (gen 1)?**
   Per `Platform::IGDB_ID_TO_CANONICAL_SLUG`, the project only
   tracks PS5 (167) and Switch 2 (508). PS4 / Switch 1 games
   render NO logo on their tiles. Confirm this is the intended
   behavior. Alternative: render the PS5 logo for PS4 games too
   (since they share the brand). Architect lean: keep
   distinct — render no logo for PS4 / Switch 1.
3. **Tile-logo size — 14 px confirmed.** Locked. Detail-page
   size — 56 px confirmed. Locked. The Rake task downloads at
   16 and 64; the 2 px scale-down at each end keeps the assets
   crisp.
4. **Switch2 favicon domain.** `nintendo.com` returns Nintendo's
   corporate favicon (a generic Nintendo logo), not a
   Switch-2-specific glyph. Verify visually at implementation —
   if the corporate favicon is acceptable, ship it; if a
   Switch-2-specific glyph is needed, source from a different
   URL or accept a manually-curated PNG override.
