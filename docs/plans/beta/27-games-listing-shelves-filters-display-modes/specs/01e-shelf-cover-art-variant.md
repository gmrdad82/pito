# 01e — Shelf Cover-Art Variant

> Parallel with all other sub-specs. Adds an explicit `:shelf` cover-art variant
> to the cover-rendering pipeline at 65% of grid size (~152 × 203 px against the
> current 234 × 312 grid). Server-side variant; no browser-resize / CSS scaling.

---

## Goal

Introduce an explicit `:shelf` variant in the cover-art pipeline so any
shelf-rendered tile (Genres shelf, Collections shelf, Shelves-by-letter mode)
fetches a correctly-sized server-side asset rather than relying on CSS scaling
of the `:grid` asset. The variant has its own asset pipeline entry, its own
cache key, and its own width × height.

---

## Files touched

Component:

- `app/components/games/cover_component.rb` (extend variant set)
- `app/components/games/cover_component.html.erb`

Image processing / asset pipeline:

- `app/models/game.rb` (Active Storage `has_one_attached :cover` variants) OR
- `app/services/games/cover_variant_resolver.rb` (if covers are stored in a
  different shape — confirm against the current implementation)

CSS:

- `app/assets/stylesheets/components/_game_cover.css` (or wherever the current
  `:grid` variant CSS lives — extend with `:shelf` class)

Specs:

- `spec/components/games/cover_component_spec.rb`
- `spec/models/game_spec.rb` (variant accessor — only if Active Storage)
- `spec/services/games/cover_variant_resolver_spec.rb` (if applicable)

---

## Variant shape

| Variant  | Width  | Height | Ratio to `:grid` |
| -------- | ------ | ------ | ---------------- |
| `:grid`  | 234 px | 312 px | 100% (baseline)  |
| `:shelf` | 152 px | 203 px | **65%** (locked) |

Aspect ratio preserved (3:4 IGDB-standard cover ratio). Both dimensions rounded
to the nearest pixel.

If covers are stored via Active Storage variants:

```ruby
has_one_attached :cover do |attachable|
  attachable.variant :grid, resize_to_fill: [234, 312]
  attachable.variant :shelf, resize_to_fill: [152, 203]
end
```

If covers come from IGDB's CDN with size suffixes (e.g. `cover_big_2x.jpg` vs
`cover_small.jpg`), the resolver maps the variant symbol to the appropriate IGDB
suffix.

---

## Component decomposition

### `Games::CoverComponent`

Inputs:

- `game: Game` (or any record with `.cover`)
- `variant: Symbol` (`:grid` (default), `:shelf`)
- `link_to_show: Boolean` (default `true`)

Renders:

- An `<img>` tag whose `src` resolves to the variant's URL.
- The component sets `width` / `height` HTML attributes matching the variant
  (prevents layout shift).
- A `data-variant` attribute mirroring the variant symbol (load-bearing for the
  spec).
- Wraps in an `<a href="/games/:slug">` when `link_to_show: true`.

The component MUST NOT rely on CSS `transform: scale(...)` or `width: 65%` of a
`:grid` asset. The asset itself is `:shelf`-sized.

---

## Spec pyramid

### Component — `spec/components/games/cover_component_spec.rb`

Happy:

- `variant: :grid` renders width=234, height=312.
- `variant: :shelf` renders width=152, height=203.
- variant URL differs between `:grid` and `:shelf` (cache keys differ).
- `data-variant="grid"` and `data-variant="shelf"` set respectively.

Sad:

- unknown variant raises `ArgumentError` (or `KeyError`) — explicit guard.

Edge:

- game with no cover attached renders a placeholder image at the variant's
  dimensions.
- both variants render without N+1 (preloading verified via `bullet` gem
  assertion or query count assertion).

Flaw:

- no inline CSS `transform: scale` emitted.
- no inline `width: 65%` style emitted.

### Model — `spec/models/game_spec.rb` (additions, if Active Storage)

Happy:

- `game.cover.variant(:shelf).processed.url` returns a URL.
- `:grid` and `:shelf` variants generate distinct blobs.

Sad:

- variant generation does not silently fall back if image processor missing —
  surfaces as an error in dev / test.

### Service — `spec/services/games/cover_variant_resolver_spec.rb` (if IGDB)

Happy:

- `resolve(game, :grid)` → IGDB CDN URL with the `t_cover_big` segment.
- `resolve(game, :shelf)` → IGDB CDN URL with the `t_cover_small_2x` segment
  (architect-proposed; confirm against IGDB's actual size set).

Sad:

- unknown variant raises.

Edge:

- IGDB URL with `https://` is preserved (no protocol downgrade).

---

## CSS additions

Add a `.game-cover--shelf` class with `width: 152px; height: 203px;`. The
component sets `class="game-cover game-cover--<variant>"`. The CSS is purely
descriptive (no `transform`, no scaling) — it matches the asset's native size.

---

## yes / no boundary

No external booleans introduced here.

---

## Friendly URL preservation

- Variant URLs are Active Storage representations; their stable URLs don't
  conflict with FriendlyId.
- If using IGDB CDN URLs directly, slugs are unaffected.

---

## Manual test recipe

1. Open `/games` — observe the two shelves at the top use the `:shelf` variant.
   Inspect an image tag; confirm `width="152"`, `height="203"`,
   `data-variant="shelf"`.
2. The grid below uses the `:grid` variant. Inspect an image tag; confirm
   `width="234"`, `height="312"`, `data-variant="grid"`.
3. View source / network panel — confirm the two URLs differ (different variant
   key, different cache).
4. Switch to `?display=shelves` — confirm letter-shelf tiles use `:shelf`
   variant.
5. List mode (`?display=list`) — cover thumbnails in the table use the `:shelf`
   variant as well (smaller cell footprint).
6. Reload — cached `:shelf` variants serve from disk, not re-generated.

---

## Cross-stack scope

| Surface    | In scope                                      |
| ---------- | --------------------------------------------- |
| Rails web  | YES — variant in the cover-rendering pipeline |
| Rails MCP  | NO — MCP doesn't render images                |
| `pito` CLI | NO — TUI doesn't render images                |
| Website    | NO                                            |

---

## Open questions

1. **Active Storage vs. IGDB CDN URLs.** Which is the current source-of- truth
   for game covers? The implementation differs significantly. Master agent
   should confirm before `01e` ships.
2. **Placeholder asset for missing covers.** Use a single shared
   `cover-placeholder.svg` at 234 × 312 and scale via the variant pipeline, OR
   ship a `cover-placeholder-shelf.svg` at 152 × 203? Architect leans single
   source + variant pipeline.
3. **IGDB cover size mapping** (if applicable). IGDB offers `t_thumb` (90×128),
   `t_cover_small` (90×128), `t_cover_small_2x` (180×256), `t_cover_big`
   (264×374), `t_cover_big_2x` (528×748). At 152 × 203 `t_cover_small_2x`
   (180×256) is the closest fit — slightly bigger, which the browser can
   letterbox cleanly. Architect leans `t_cover_small_2x` for `:shelf`.
4. **Retina / 2x support.** Should we also generate `@2x` variants for high-DPI
   displays? Architect leans defer — Active Storage handles DPR server-side; a
   `@2x` variant pass can land later if needed.
5. **Image format.** WebP vs. JPEG? Architect leans WebP with JPEG fallback
   (browser-detection via `<picture>`). Optional; spec ships JPEG if WebP adds
   complexity.
