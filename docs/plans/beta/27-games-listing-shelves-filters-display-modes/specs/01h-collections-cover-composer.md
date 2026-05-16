# 01h — Collections Cover Composer

> Adds a server-side composite cover image for Custom collection sub-shelves
> rendered on `/games`. The composer stitches up to 6 member-game IGDB covers
> into a single shelf-sized JPEG. Layout selection is keyed on game count (0 / 1
> / 2 / 3 / 4 / 5 / 6+). Output size matches the `:shelf` cover-art variant the
> consumer renders.
>
> Builds on Phase 14's `Composite::*` bundle pipeline (`Composite::Builder`,
> `Composite::LayoutChooser`, `Composite::Checksum`, `Composite::TileCache`,
> `Composite::TileFetchError`). The composer this spec introduces lives in a
> sibling `Collections::*` namespace, NOT in `Composite::`, so the bundle code
> stays untouched.

---

## Goal

Each Custom collection on `/games` is rendered as a sub-shelf whose leading tile
is a single composite image stitched together from the collection's member
games' IGDB covers — 1 to 6 tiles arranged in a layout that scales with member
count, served at the same pixel footprint the `:shelf` cover-art variant uses on
the page. The composite is fingerprint-cached on disk so re-renders are cheap;
when the collection's membership or member cover art changes, the fingerprint
changes and the next render writes a new file.

The composer's output sits in front of the user as visual shorthand for "what's
in this collection." It mirrors the bundle composite shape from Phase 14 but
narrowed to the 6-variant matrix the sub-shelf design needs.

---

## Grounding (verified against the repo on 2026-05-10)

The following are facts pulled from the current code, not assumptions. The
implementation lane MUST honor them; deviations require a new architect pass.

### Phase 14 composite pipeline (`app/services/composite/`)

- `Composite::Builder` — class with `#initialize(tile_cache: TileCache.new)` +
  `#call(bundle)` + `#output_path(bundle)`. Output canvas is 600 × 800.
  `JPEG_QUALITY = 80`. Calls `layout.compose(tiles, total_member_count:)`.
- `Composite::LayoutChooser` — module with `module_function`,
  `.choose(count) -> Module`. Raises `ArgumentError` on non-Integer or count
  ≤ 0.
- `Composite::Checksum` — module with `module_function`,
  `.compute(image_ids, layout_name) -> String`. Sorts ids lexically, filters
  nil, hashes `"<layout_name>|<id1>,<id2>,...,<idN>"` with SHA-256.
- `Composite::TileCache` — class with `#fetch(cover_image_id) -> Vips::Image`,
  `#evict(cover_image_id)`, `#tile_path(cover_image_id) -> Pathname`. Backing
  store: `<PITO_ASSETS_PATH>/composites/_tiles/<cover_image_id>.jpg`. Source:
  IGDB CDN `t_cover_big` (227 × 320 native).
- `Composite::TileFetchError` — raised on non-200 IGDB CDN responses.
- Layout modules under `app/services/composite/layout/` each expose
  `module_function`, `.layout_name -> String`,
  `.compose(tiles, total_member_count: nil) -> Vips::Image`. Tiles are
  `Vips::Image` instances returned by `TileCache#fetch`.

The `Collections::CoverComposer` reuses `Composite::TileCache` directly (same
cache directory, same source token, same evict semantics — sharing the cache is
load-bearing for cost). It does NOT reuse `Composite::LayoutChooser` or any of
the `Composite::Layout::*` modules — the layout matrix is different (Pair /
Netflix-3 / Quad / Netflix-5 / Six-grid vs. Pair / Netflix / Quad / NineGrid).

### Collection ↔ Game relationship (`app/models/collection.rb`, `db/schema.rb`)

- `Collection has_many :games, dependent: :nullify`.
- `games.collection_id` is a **direct foreign key**, NOT a join table. There is
  no `CollectionMember` / `CollectionGame` model. Invalidation hooks attach to
  `Game`, not to a join row.

### Composite serving route (`app/controllers/composites_controller.rb`,

`config/routes.rb`)

- Route: `GET /composites/:filename.jpg` → `composites#show`. Helper
  `composite_cover_path(filename:)`.
- Route constraint: `filename: /[a-z_]+-\d+/`.
- Controller regex (defense in depth): `FILENAME_REGEX = /\A[a-z_]+-\d+\z/`.
- File resolution: `Pito::AssetsRoot.path("composites", "#{name}.jpg")`.
- Auth: inherits `ApplicationController` (login required across the app).

> **Filename-pattern note.** The current route regex (`[a-z_]+-\d+`) only
> accepts `<prefix>-<digits>`. The user's prompt suggests the new filename
> `collection-<id>-<variant>-<sha256>.jpg`, which the existing regex would 404.
> See **Open questions** below — this MUST be resolved before the implementation
> lane ships. The recommended path is keeping the existing regex shape AND
> moving the fingerprint into a query parameter
> (`/composites/collection-42.jpg?v=<sha256>`), so the route stays compatible
> with the bundle composer.

### `:shelf` cover-art variant (`app/components/games/cover_component.rb`)

- `Games::CoverComponent::DIMENSIONS[:shelf]` is currently **98 × 130**, sourced
  from IGDB token `t_cover_small_2x` (180 × 256 native).
- The 65% → 70% bump the user described in the task brief is **not present in
  the codebase as of this spec**. The component still locks 65% (98 × 130). See
  **Open questions #1** below — this spec assumes the user is committing to the
  70% bump (105 × 140), but the implementation lane MUST either land the
  component bump in this spec OR target 98 × 130 (whatever the user pins).

### Placeholder for missing covers (`app/components/games/cover_component.html.erb`)

- Web placeholder for a Game with no `cover_image_id`: a `<span>` with classes
  `bracketed-active text-muted game-cover-missing` rendering `[no cover]` inside
  the sized slot.
- Composite placeholder (existing, inside `Composite::Layout::NineGrid`): flat
  dark grey (`BG_RGB = [30, 30, 30]`) tile produced via
  `Vips::Image.black(TILE_W, TILE_H).new_from_image(BG_RGB)`.

The composite-internal placeholder pattern (flat dark grey block) is the right
match for the composer in this spec — embedded JPEG bytes, no text overlay.

---

## Output canvas + locked pixel math

> Output canvas: **105 × 140 px** (matches the `:shelf` cover-art variant target
> at 70% of the 150 × 200 grid — pending Open question #1 resolution).

Six layout variants keyed on game count. Each tile is sourced from
`TileCache#fetch(cover_image_id)` (returns a `Vips::Image` of the 227 × 320
`t_cover_big` asset), resized via `thumbnail_image(W, height: H, crop: :centre)`
following the existing layout-module convention, and joined via libvips
`Vips::Image#join(:horizontal | :vertical)`.

**Gap policy (LOCKED — re-derived from scratch per the master-agent dispatch's
mandate to fix the 5-game off-by-1):** **no gap between tiles.** The composer
joins tiles edge-to-edge; libvips `join` does not insert padding. Tile widths
are chosen so they sum exactly to 105 (and heights to 140). Where 105 / 140 do
not divide evenly across N columns / rows, the leftmost / topmost tile carries
the extra pixel. This is the same convention `Composite::Layout::NineGrid` uses
for its 800 / 3 → 267 + final-crop pattern.

### Variant matrix

| Count | Layout name   | Description                                | Tile boxes (w × h, in canvas order)                                                   |
| ----- | ------------- | ------------------------------------------ | ------------------------------------------------------------------------------------- |
| 0     | `empty`       | Placeholder (NO composite written to disk) | n/a — composer returns nil; view renders `[empty]` placeholder block                  |
| 1     | `passthrough` | Single tile, no composite                  | n/a — composer returns nil; view renders the lone `Games::CoverComponent`             |
| 2     | `pair`        | 1 × 2 side-by-side                         | left 52 × 140, right 53 × 140                                                         |
| 3     | `netflix3`    | 1 big left + 2 small stacked right         | big 70 × 140; top-right 35 × 70; bottom-right 35 × 70                                 |
| 4     | `quad`        | 2 × 2 grid                                 | TL 52 × 70, TR 53 × 70, BL 52 × 70, BR 53 × 70                                        |
| 5     | `netflix5`    | 1 big left + 2 × 2 grid right              | big 53 × 140; TR 26 × 70, TR2 26 × 70 (top row); BR 26 × 70, BR2 26 × 70 (bottom row) |
| 6+    | `six_grid`    | 2 × 3 grid (3 cols × 2 rows)               | each tile 35 × 70 (perfect integer split: 35 × 3 = 105, 70 × 2 = 140)                 |

**Sums (verifying exact tiling to 105 × 140):**

- pair: 52 + 53 = 105 ✓; height 140 ✓.
- netflix3: left 70 + right column 35 = 105 ✓; right column 70 + 70 = 140; left
  140 ✓.
- quad: 52 + 53 = 105 ✓; 70 + 70 = 140 ✓.
- netflix5: 53 + (26 + 26) = 53 + 52 = 105 ✓; top row 70 + bottom row 70 = 140
  ✓; big 140 ✓.
- six_grid: 35 × 3 = 105 ✓; 70 × 2 = 140 ✓.

All variants tile exactly to 105 × 140. **No rounding to fractional pixels and
no letterbox bars are needed.**

> If Open question #1 resolves to keep the variant at 98 × 130 (the current
> code), the pixel math regresses to: pair 49+49=98 / h 130; netflix3 big 64×130
>
> - right col 34 (top 34×65, bot 34×65) → 64+34=98 ✓ / 65+65=130; quad 49+49=98
>   / 65+65=130; netflix5 big 50 + right col 48 (each cell 24×65) → 50+48=98 /
>   65+65=130; six_grid w 98/3 = 32.66 → 33+33+32=98 / 65+65=130. The six_grid
>   loses its clean integer split. The 70% bump exists partly to make the
>   six_grid clean — this is why Open question #1 matters.

### 6+ game ordering

Sort all member games alphabetically by `Game#title` (case-insensitive). Take
the first 6. Drop any "fallback to created_at" — the order column is **only**
title. Deterministic ordering is load-bearing for the fingerprint to remain
stable across renders.

### Placeholder tile (game with nil `cover_image_id`)

When a game in the slot has no `cover_image_id`, the composer substitutes a flat
dark-grey block matching the existing
`Composite::Layout::NineGrid::BG_RGB = [30, 30, 30]` pattern at the tile's
target dimensions. **Substitute, do not skip the slot** — keeping the slot
preserves the layout's geometric symmetry.

### libvips error degradation (LOCKED — substitute placeholder)

When `TileCache#fetch(cover_image_id)` raises `Composite::TileFetchError` (or
any `Vips::Error` during `thumbnail_image` / `join` / `composite2`), the
composer substitutes a placeholder tile (same `BG_RGB = [30, 30, 30]` block) at
the slot's target dimensions and **continues building the composite**. Total
silent fallback per slot; the composer logs at WARN with the cover_image_id and
the underlying error class. No retry, no re-raise — the composite ships with a
grey hole, and the next collection update (which would change the fingerprint)
gives the cache another chance.

> Rationale: a single bad IGDB asset should not block the rest of the
> collection's composite from rendering. This intentionally differs from the
> bundle composer (`BundleCoverBuild` re-raises so Sidekiq retries), because the
> collection composer is intended to run synchronously inside the page-render
> request path on first miss — re-raising would surface a 500.

---

## Files touched

New:

- `app/services/collections/cover_composer.rb` — the orchestrator. Public API:

  ```ruby
  Collections::CoverComposer.new(tile_cache: Composite::TileCache.new).call(collection)
  # -> Pathname | nil
  ```

  Returns the absolute Pathname of the on-disk composite when a fingerprint miss
  caused a write, returns the absolute Pathname of the existing on-disk
  composite on a fingerprint hit (no rewrite), returns `nil` for the `empty` /
  `passthrough` layouts (counts 0 / 1).

- `app/services/collections/composite_layout.rb` — pure layout engine. Public
  API:
  ```ruby
  Collections::CompositeLayout.choose(count) -> Symbol  # :empty | :passthrough | :pair | :netflix3 | :quad | :netflix5 | :six_grid
  Collections::CompositeLayout.tile_boxes(layout, output_w: 105, output_h: 140) -> Array<{ x:, y:, w:, h: }>
  Collections::CompositeLayout.compose(layout, tiles)  -> Vips::Image
  # `tiles` is an Array<Vips::Image | nil>; nil slots are filled with the
  # placeholder block in `compose`. Slot count matches `tile_boxes(layout).size`.
  ```
  The layout engine is libvips-aware but knows nothing about collections,
  caching, fingerprints, or filenames — those are `cover_composer.rb`'s job.

Edited:

- `app/models/collection.rb` — add `#cover_url(variant: nil)` returning either
  the public `/composites/collection-<id>.jpg?v=<fingerprint>` URL or `nil` when
  the composer has not yet written a file for this collection. Reuses the same
  shape as `Bundle#composite_cover_url`. `variant:` is reserved for future
  shelf-size variants; currently ignored.
- `app/models/game.rb` — extend
  `after_update_commit :invalidate_bundle_covers_if_image_changed` to ALSO evict
  the parent collection's cover when `cover_image_id` changes. The cleanest
  implementation is a new
  `after_update_commit :invalidate_collection_cover_if_image_changed` callback
  that enqueues a `Collections::CoverInvalidate` job (mirror of
  `BundleCoverInvalidate`). Alternative is to do nothing — the fingerprint will
  change on the next composer call and a fresh write will replace the stale
  file. **LOCKED:** do nothing on cover_image_id change. The fingerprint is the
  source of truth for staleness; the on-disk file becomes orphaned but a
  reap-orphans rake task (deferred follow-up) sweeps it later.
- `app/models/game.rb` — add
  `after_update_commit :evict_collection_composite_on_collection_change` that,
  when `collection_id` changes (add / move / remove), deletes any on-disk
  `collection-<old_id>.jpg` AND `collection-<new_id>.jpg` so the next page
  render re-derives them. The fingerprint catches the same change, but eviction
  makes the next render faster (no need to re-hash 6 ids to discover the cache
  is stale — the file literally is not there).

  Reuses the same callback class pattern as
  `Game#invalidate_bundle_covers_if_image_changed`. No new job — eviction is a
  small `File.delete` and happens inline on the after-commit callback.

View partial (consumer):

- `app/views/games/_collection_sub_shelf.html.erb` (new) — renders one Custom
  collection's sub-shelf row. Calls the composer inline:

  ```erb
  <% composite_url = collection.cover_url %>
  <% if composite_url.present? %>
    <img src="<%= composite_url %>" width="105" height="140" loading="lazy"
         alt="<%= collection.name %>" class="collection-cover-composite">
  <% elsif collection.games.count == 1 %>
    <%= render(Games::CoverComponent.new(game: collection.games.first, variant: :shelf, link_to_show: false)) %>
  <% else %>
    <span class="bracketed-active text-muted collection-cover-empty"
          style="width: 105px; height: 140px; display: inline-flex; align-items: center; justify-content: center;">
      [empty]
    </span>
  <% end %>
  ```

  The view does NOT call the composer service directly — `Collection#cover_url`
  hides the "do I need to (re)build?" detail. The first-render miss writes
  through; subsequent hits are a file-stat away.

Controller / route (touched):

- `app/controllers/composites_controller.rb` — the `FILENAME_REGEX` constant
  needs to admit the collection composite filename. With the
  fingerprint-in-query approach (recommended), no change is needed. With the
  fingerprint-in-filename approach, the regex bumps to
  `/\A[a-z_]+-\d+(-[a-z0-9]+){0,2}\z/` (or similar). **LOCKED to
  fingerprint-in-query per Open question #2's recommended path** — no controller
  / route changes.

CSS (touched, minimal):

- `app/assets/tailwind/application.css` — add `.collection-cover-composite`
  fixed-pixel rules (width: 105px; height: 140px; display: block; border-radius:
  2px; — no transforms, no `width: 100%`). Mirrors the `.game-cover` /
  `.game-cover--shelf` pattern.

---

## Fingerprint + filename

### Filename pattern (on disk)

```
<PITO_ASSETS_PATH>/composites/collection-<collection_id>.jpg
```

Resolved via `Pito::AssetsRoot.path("composites", "collection-<id>.jpg")`.
Matches the existing route regex (`[a-z_]+-\d+`). One file per collection.

### Fingerprint (cache-busting hash)

Composed via the existing `Composite::Checksum`:

```ruby
fingerprint = Composite::Checksum.compute(
  member_cover_image_ids_sorted_alphabetically_by_title,  # ordered + filtered Array<String|nil>
  layout_symbol.to_s                                       # e.g. "netflix3"
)
```

The fingerprint is **stored on the Collection row** in a new column
`composite_cover_checksum` (string, nullable, 64-char hex). Mirror of
`bundles.composite_cover_checksum`. Add a migration:
`add_column :collections, :composite_cover_checksum, :string`.

> Note: the user prompt described the cache key as a SHA-256 of sorted **game
> ids** ("sorted-game-ids"). This spec **deviates intentionally**: the
> fingerprint hashes `cover_image_id` values (matching `Composite::Checksum`'s
> existing contract for bundle covers), NOT `Game#id` values. Hashing
> `cover_image_id` means the composite is correctly invalidated when the
> underlying IGDB cover changes for the SAME game (which happens on IGDB
> resync), where hashing `Game#id` would miss that. The ordering is anchored on
> `Game#title` (alphabetical, case-insensitive) for determinism, but the hash
> payload is the `cover_image_id` list.

### Public URL

```ruby
def cover_url(variant: nil)
  return nil if composite_cover_checksum.blank?
  "/composites/collection-#{id}.jpg?v=#{composite_cover_checksum}"
end
```

The `?v=` query parameter is the cache-buster: the URL changes whenever the
fingerprint changes, so browsers and CDN edges evict in step.

### Cache hit / miss flow

```text
Collections::CoverComposer#call(collection)
  1. games = collection.games.order(Arel.sql("LOWER(title)")).limit(6).to_a
  2. count = games.size
  3. layout = Collections::CompositeLayout.choose(count)
  4. return nil if layout == :empty || layout == :passthrough
  5. cover_image_ids = games.map(&:cover_image_id)  # nil entries preserved
  6. fingerprint = Composite::Checksum.compute(cover_image_ids, layout.to_s)
  7. path = Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
  8. if collection.composite_cover_checksum == fingerprint && path.exist?
       return path  # hit
     end
  9. tiles = cover_image_ids.map do |cid|
       cid.nil? ? nil : safe_fetch_tile(cid)  # nil OR Vips::Image
     end
  10. composite = Collections::CompositeLayout.compose(layout, tiles)
  11. FileUtils.mkdir_p(path.dirname)
       composite.jpegsave(path.to_s, Q: 80, strip: true)
  12. collection.update!(composite_cover_checksum: fingerprint)
  13. path
```

`safe_fetch_tile(cid)` swallows `Composite::TileFetchError` and any `Vips`
error, returning `nil` so the placeholder slot kicks in. WARN-logs the failure.

### Cache invalidation triggers (LOCKED)

- **Membership add / remove**: `Game#after_update_commit` when `collection_id`
  changes — `File.delete(path)` for both old and new collection ids (best
  effort; the fingerprint mismatch in `#call` is the canonical guard).
- **Per-game cover swap**: NO explicit invalidation. The fingerprint
  recomputation on the next page render catches it; the orphaned file gets swept
  by the (deferred) reap-orphans rake task.
- **Collection destroyed**:
  `Collection#before_destroy :sweep_composite_cover_file` (mirror of
  `Bundle#sweep_composite_cover_file`) — `File.delete(path)` if it exists.
  Best-effort; survives `Errno::ENOENT`.

---

## Acceptance

- [ ] `Collections::CompositeLayout.choose(n)` returns the correct layout symbol
      for every n in `[0, 1, 2, 3, 4, 5, 6, 7, 100]`.
- [ ] `Collections::CompositeLayout.tile_boxes(layout)` returns the documented
      `{ x:, y:, w:, h: }` boxes for every layout; sum of widths per row equals
      105 and sum of heights per column equals 140; no overlaps; no gaps.
- [ ] `Collections::CompositeLayout.compose(layout, tiles)` returns a
      `Vips::Image` of dimensions exactly 105 × 140 for every non-empty /
      non-passthrough variant.
- [ ] `Collections::CompositeLayout.compose(layout, tiles)` substitutes a flat
      `[30, 30, 30]` RGB block for any `nil` tile, at the slot's exact box
      dimensions.
- [ ] `Collections::CoverComposer#call(collection)` returns `nil` for 0-game and
      1-game collections (no on-disk write).
- [ ] `Collections::CoverComposer#call(collection)` writes
      `<assets>/composites/collection-<id>.jpg` for 2..6+-game collections and
      stamps `collection.composite_cover_checksum`.
- [ ] On a fingerprint hit (checksum matches AND file exists),
      `Collections::CoverComposer#call` returns the existing path WITHOUT
      rewriting the file (assertion: `File.mtime` unchanged across two calls).
- [ ] Members are ordered alphabetically by `Game#title` (case-insensitive) for
      the tile slot AND for the fingerprint payload.
- [ ] For 6+ members, only the first 6 (alphabetical) contribute to tiles AND to
      the fingerprint.
- [ ] A `Composite::TileFetchError` raised inside `Composite::TileCache#fetch`
      is swallowed; the composite still ships, with the failing slot filled by
      the dark-grey placeholder block.
- [ ] A `Vips::Error` raised during `thumbnail_image` / `join` / `composite2` is
      swallowed (same fallback); composer returns the path; logger receives a
      WARN-level entry with `cover_image_id` and the error class.
- [ ] `Collection#cover_url` returns the public URL with the `?v=<fingerprint>`
      query parameter; returns `nil` when `composite_cover_checksum` is blank.
- [ ] Adding / removing a `Game` from a `Collection` evicts the on-disk
      composite for both the old and the new collection id (when applicable),
      via `Game#after_update_commit`.
- [ ] Destroying a `Collection` removes the on-disk composite file (best effort
      — `Errno::ENOENT` is swallowed).
- [ ] `Composite::Checksum.compute` is used unchanged for the fingerprint — no
      new hash helper.
- [ ] `Composite::TileCache` is reused unchanged — the collection composer
      shares the bundle composer's `_tiles/` directory.
- [ ] View partial `app/views/games/_collection_sub_shelf.html.erb` renders an
      `<img>` with the composite URL for ≥ 2-game collections, falls back to
      `Games::CoverComponent.new(variant: :shelf)` for 1-game collections, and
      renders an `[empty]` block for 0-game collections.
- [ ] `CompositesController` continues to serve the on-disk file without regex
      changes (filename matches existing `[a-z_]+-\d+` constraint; fingerprint
      rides on `?v=`).
- [ ] No `transform: scale`, no percentage-width sizing, no CSS `zoom` on
      `.collection-cover-composite`. Width / height are inline pixel values AND
      CSS pixel values.
- [ ] Spec pyramid: service spec, layout-engine spec, model spec, view spec,
      request spec on `/composites/:filename.jpg?v=<sha>` round-trip (see
      below).
- [ ] No `alert` / `confirm` / `prompt` / `data-turbo-confirm`. No
      `cursor: pointer` on the composite image itself (the sub-shelf wrapper
      carries the click affordance).
- [ ] No JS changes. The composer is pure Ruby + libvips; the consumer is a
      static `<img>`.

---

## Spec pyramid

### Service spec — `spec/services/collections/cover_composer_spec.rb`

Mandatory groups (every group is full-coverage — happy / sad / edge / flaw):

- `#call` for each variant (0 / 1 / 2 / 3 / 4 / 5 / 6 / 7-as-truncated-to-6).
  Assert: return value (Pathname | nil), output file dimensions when written
  (read back via
  `Vips::Image.new_from_file(path).then { [_1.width, _1.height] } == [105, 140]`),
  `composite_cover_checksum` set on the collection.
- Cache hit: invoke `#call` twice. Assert the second call does NOT rewrite the
  file (file mtime unchanged).
- Cache miss after membership change: invoke `#call`, change a member, invoke
  `#call` again. Assert the file is rewritten AND `composite_cover_checksum`
  changed.
- Cache miss after cover swap: invoke `#call`, change one member's
  `cover_image_id`, invoke `#call` again. Assert fingerprint changed AND file
  rewritten.
- Tile fetch error: stub `Composite::TileCache#fetch` to raise
  `Composite::TileFetchError` for one cover_image_id. Assert the composer still
  returns the path, the file exists, the file dimensions are still 105 × 140,
  and the failing slot is the placeholder block (sample a centre pixel from the
  slot box, assert RGB = `[30, 30, 30]` within 1).
- Vips error: stub `Vips::Image#thumbnail_image` to raise `Vips::Error` for one
  tile. Same assertions as the previous.
- Fingerprint determinism: build the same collection twice in independent test
  DBs, assert identical fingerprints.
- Member ordering: build a 6-game collection where 3 of the games' titles differ
  only in case (`alpha`, `Alpha`, `ALPHA`, `beta`, `Beta`, `gamma`). Assert the
  ordering is stable and case-insensitive (alphabetical by `LOWER(title)`).
- 7-game collection: assert only the first 6 (alphabetical) contribute to both
  the tile array AND the fingerprint payload. The 7th game's `cover_image_id`
  does NOT appear in the hash.
- Variant override: not applicable — the composer has one output size.

### Layout-engine spec — `spec/services/collections/composite_layout_spec.rb`

Pure-function, no fixtures, no libvips actual rendering (use bare
`Vips::Image.black(W, H)` as input tiles where needed).

- `.choose(n)` returns the documented symbol for every n in
  `[0, 1, 2, 3, 4, 5, 6, 7, 100]`. Negative n raises `ArgumentError`.
- `.tile_boxes(layout)` returns the documented array of `{ x:, y:, w:, h: }`
  hashes for every non-empty / non-passthrough layout. Assert exact pixel values
  (the matrix above). Assert sum-of-widths-per-row = 105 and
  sum-of-heights-per-column = 140.
- `.tile_boxes(layout, output_w: 200, output_h: 280)` proportionally scales —
  assert this rule explicitly. (Useful if the variant size ever changes; the
  test pins the contract.)
- `.compose(layout, tiles)` returns a `Vips::Image` of 105 × 140 for every
  non-empty / non-passthrough layout.
- `.compose(layout, tiles)` raises `ArgumentError` when `tiles.size` differs
  from `tile_boxes(layout).size`.
- `nil` tiles in the `tiles` array are substituted with the placeholder block
  (`Vips::Image.black(W, H).new_from_image([30, 30, 30])`) at the slot's exact
  box dimensions.

### Model spec — `spec/models/collection_spec.rb` (additions)

- `#cover_url` returns `nil` when `composite_cover_checksum` is blank.
- `#cover_url` returns `"/composites/collection-<id>.jpg?v=<sha>"` when
  `composite_cover_checksum` is present.
- `#cover_url(variant: :anything)` is unaffected (variant arg reserved).
- `before_destroy :sweep_composite_cover_file` removes the on-disk file when
  present; survives `Errno::ENOENT`.

### Model spec — `spec/models/game_spec.rb` (additions)

- `after_update_commit` on `collection_id` change evicts the on-disk composite
  for BOTH the old and new collection ids (stub `File.delete` and assert call
  args).
- No-op when `collection_id` did not change.

### View spec — `spec/views/games/_collection_sub_shelf.html.erb_spec.rb`

- 0-game branch renders the `[empty]` placeholder span with inline 105 × 140
  pixel dimensions.
- 1-game branch renders a `Games::CoverComponent` at `:shelf` variant.
- 2..6+-game branch renders an `<img>` with `src` = `Collection#cover_url`,
  `width="105"`, `height="140"`, `loading="lazy"`, `alt="<collection.name>"`.
- No `cursor: pointer` on the composite `<img>` itself.
- No inline `transform`, no inline `width: 100%`.

### Request spec — `spec/requests/composites_spec.rb` (extension)

- `GET /composites/collection-42.jpg` returns the on-disk JPEG when present
  (200, content-type `image/jpeg`).
- `GET /composites/collection-42.jpg?v=<any-hex>` ignores the query param and
  returns the same file (query is browser-side cache-buster only).
- `GET /composites/collection-99999.jpg` (no file on disk) returns 404.
- Auth gate: anonymous GET redirects to `/login` (existing
  `ApplicationController` behavior).
- Path traversal guard: `GET /composites/..%2Fetc%2Fpasswd.jpg` is rejected at
  the route constraint level (404).

### System spec — `spec/system/games_index_spec.rb` (extension)

> System specs are intentionally thin per pito's architect rule D. Add ONE
> example to the existing file: load `/games` with two 3-game custom collections
> seeded, assert the composite `<img>` renders with the right URL AND the file
> actually exists on disk after the request. Do NOT branch out into a 6-variant
> system test — the variants are covered by the service spec.

---

## Manual test recipe

Prerequisite: dev DB seeded with at least one Custom collection per game-count
variant the user wants to verify.

```bash
# 1. Seed a collection with 0, 1, 2, 3, 4, 5, 6, 7 games respectively.
bin/rails console
collection_2 = Collection.create!(name: "Pair test")
Game.where("title ILIKE 'a%'").limit(2).update_all(collection_id: collection_2.id)
# Repeat for 3 / 4 / 5 / 6 / 7 ...

# 2. Trigger the composer on each.
Collections::CoverComposer.new.call(collection_2)
# Expect: returns Pathname; file exists at
#   tmp/pito-assets/composites/collection-<id>.jpg
# Expect: collection_2.reload.composite_cover_checksum is a 64-char hex string.

# 3. Verify output dimensions.
require "vips"
Vips::Image.new_from_file("tmp/pito-assets/composites/collection-#{collection_2.id}.jpg")
  .then { |img| [img.width, img.height] }
# => [105, 140]

# 4. Verify the cache hit (no rewrite).
before_mtime = File.mtime("tmp/pito-assets/composites/collection-#{collection_2.id}.jpg")
Collections::CoverComposer.new.call(collection_2)
after_mtime = File.mtime("tmp/pito-assets/composites/collection-#{collection_2.id}.jpg")
before_mtime == after_mtime
# => true

# 5. Visit /games. Confirm each Custom collection sub-shelf renders an
#    <img src="/composites/collection-<id>.jpg?v=<sha>" width="105" height="140">.
#    Right-click → open in new tab. Confirm the JPEG renders the expected layout.

# 6. Tile-fetch error path (manual simulation).
allow_any_instance_of(Composite::TileCache)
  .to receive(:fetch).and_raise(Composite::TileFetchError.new("test"))
Collections::CoverComposer.new.call(collection_2)
# Expect: returns Pathname; file exists; opens to a 105 × 140 image of solid
#         dark grey (placeholder for both tiles).
```

Tear-down: `rm tmp/pito-assets/composites/collection-*.jpg` to reset state.

---

## Cross-stack scope

| Surface              | In scope this spec                            |
| -------------------- | --------------------------------------------- |
| Rails web (`/games`) | YES — composer + view partial + model hook    |
| Rails MCP            | NO — composer is a private cache; no MCP tool |
| `pito` CLI (Rust)    | NO — CLI does not render covers (text TUI)    |
| Cloudflare website   | NO                                            |

---

## Open questions (must be answered before implementation lane spawns)

1. **Output canvas size — 98 × 130 or 105 × 140?** The user prompt assumes 105 ×
   140 (70% of grid). The codebase currently locks 98 × 130 (65%, see
   `Games::CoverComponent::DIMENSIONS[:shelf]`). The pixel math above tiles
   exactly to 105 × 140; if the answer is 98 × 130, the six_grid variant loses
   its clean integer split (98 / 3 = 32.66). Either:
   - (a) Bump `Games::CoverComponent::DIMENSIONS[:shelf]` to
     `width: 105, height: 140` in this spec's implementation lane, OR
   - (b) Re-derive the pixel matrix above against 98 × 130 (the six_grid becomes
     33+33+32 × 65+65 with the leftmost column carrying the extra pixel).

   **Architect's recommendation:** (a). The user's task brief explicitly names
   70% and the integer math is cleaner.

2. **Filename pattern — fingerprint in query (`?v=<sha>`) or in filename
   (`collection-<id>-<sha>.jpg`)?** Fingerprint-in-query keeps the existing
   `CompositesController::FILENAME_REGEX` and route constraint unchanged.
   Fingerprint-in-filename requires loosening the regex AND complicates the
   `before_destroy` sweep (it would need to glob `collection-<id>-*.jpg`).

   **Architect's recommendation:** fingerprint-in-query. Locked in this spec
   pending user confirmation.

3. **Netflix-3 big tile placement — left or right?** This spec defaults to
   **left big, right column of two small** (matches the existing
   `Composite::Layout::Netflix`). Visual preference — could flip if the user
   prefers the big tile on the right (the eye-leading edge for LTR readers).

   **Architect's recommendation:** **left big** (matches Netflix's actual UI AND
   the existing bundle composer).

4. **1px gap between tiles or no gap?** This spec locks **no gap** (matches the
   existing bundle composer's edge-to-edge layout). A 1px gap would mean
   re-deriving every variant's pixel math (the 2×3 grid would become
   34+1+34+1+35 wide, 69+1+70 tall — loses its clean uniformity). Visual
   preference: a 1px gap reads as "intentional separation"; no gap reads as
   "stitched poster."

   **Architect's recommendation:** **no gap**. Cleaner integer splits, matches
   existing bundle composer.

5. **Should the collection-cover `<img>` link anywhere?** This spec renders a
   bare `<img>` inside the sub-shelf wrapper (no `<a>` around the composite).
   The sub-shelf row itself is rendered by
   `app/views/games/_collections_shelf.html.erb` (existing) which already wraps
   its tiles in `<a href="<%= games_path(collection: ...) %>">`. Confirm the
   sub-shelf wrapper for THIS new partial routes the composite click
   identically; if not, the spec needs an `href:` on the `<img>` parent `<a>`.

6. **Migration for `collections.composite_cover_checksum`** — separate migration
   or inline in this spec's implementation? Recommend separate (one sub-spec,
   one migration per pito convention). The migration adds the nullable string
   column; backfill is not needed (the next composer call on each existing
   collection writes the value).
