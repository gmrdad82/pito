# 01c — Genres and Collections Shelves

> Independent of `01b`'s filter row; can run in parallel. Adds two horizontal
> shelves above the main listing on `/games`: one Genres shelf (one tile per
> genre), one Collections shelf (one tile per custom collection). Both sorted
> alphabetically, both using the existing skinned horizontal-scroll component,
> both rendering tiles at the `:shelf` cover-art size (depends on `01e`).

---

## Goal

Replace the implicit "where do I find a genre or collection grouping?" with two
first-class horizontal shelves at the top of `/games`. Tiles are clickable:
clicking a genre tile filters the listing by that genre (genre becomes a
separate query param, NOT part of the filter row's chip set; genre / collection
are higher-cardinality and live in their own state slot). Clicking a collection
tile opens the collection page.

---

## Files touched

Components:

- `app/components/games/genres_shelf_component.rb`
- `app/components/games/genres_shelf_component.html.erb`
- `app/components/games/collections_shelf_component.rb`
- `app/components/games/collections_shelf_component.html.erb`
- `app/components/games/shelf_tile_component.rb` (shared)
- `app/components/games/shelf_tile_component.html.erb`

Views:

- `app/views/games/index.html.erb` (renders both shelves above filter row)

Controller:

- `app/controllers/games_controller.rb` (`#index` accepts `?genre_slug=...`)

Model + scopes:

- `app/models/game.rb` — `scope :in_genre, ->(slug) { ... }`

Specs:

- `spec/components/games/genres_shelf_component_spec.rb`
- `spec/components/games/collections_shelf_component_spec.rb`
- `spec/components/games/shelf_tile_component_spec.rb`
- `spec/models/game_spec.rb` (in_genre scope)
- `spec/requests/games_spec.rb` (genre_slug param)
- `spec/system/games_index_spec.rb` (clicking a shelf tile)

---

## Component decomposition

### `Games::GenresShelfComponent`

Inputs:

- `genres: ActiveRecord::Relation` (defaults to `Genre.order(:name)`)

Renders:

- The skinned horizontal-scroll wrapper (existing project class — e.g.
  `.skinned-scroll`).
- Inside, one `Games::ShelfTileComponent` per genre, alphabetical order.

### `Games::CollectionsShelfComponent`

Inputs:

- `collections: ActiveRecord::Relation` (defaults to
  `Collection.where(kind: :custom).order(:name)`)

Renders:

- The skinned horizontal-scroll wrapper.
- Inside, one `Games::ShelfTileComponent` per collection, alphabetical order.

### `Games::ShelfTileComponent` (shared)

Inputs:

- `label: String`
- `href: String`
- `cover_source: ApplicationRecord | nil` (Genre or Collection — both expected
  to expose a cover-art helper; falls back to a placeholder when nil)
- `variant: Symbol` (always `:shelf` here; pass-through to the cover component
  from `01e`)

Renders:

- A clickable tile (`cursor: pointer` per project rule).
- Cover thumbnail at `:shelf` size.
- Bracketed label below cover: `[label]`.

---

## Model + scope

### `Game.in_genre(slug)`

```ruby
scope :in_genre, ->(slug) {
  joins(:genres).where(genres: { slug: slug })
}
```

Assumes `Game has_many :genres, through: :game_genres` exists (from prior
phase). If not, surface as an open question.

### URL contract

- `GET /games?genre_slug=action` — filters to games in the `action` genre.
- `GET /games?genre_slug=action&filters=owned,ps5` — composes with the filter
  row.
- Clicking a Collection tile navigates to `/collections/:slug` (existing route —
  not new in this phase).

---

## Spec pyramid

### Component — `spec/components/games/genres_shelf_component_spec.rb`

Happy:

- renders one tile per genre, alphabetical.
- passes through `variant: :shelf` to each tile.

Sad:

- renders zero tiles when no genres exist (still renders the scroll wrapper).

Edge:

- genres with identical names sort stably (id tiebreak).

Flaw:

- never emits a JS confirm (no destructive action).

### Component — `spec/components/games/collections_shelf_component_spec.rb`

Happy:

- renders one tile per custom collection, alphabetical.
- excludes non-custom collections (e.g. system collections, if any).

Sad:

- renders zero tiles when no custom collections exist.

Edge:

- alphabetical sorting is case-insensitive (`order(Arel.sql("LOWER(name)"))`).

Flaw:

- never includes a deleted collection (uses default scope).

### Component — `spec/components/games/shelf_tile_component_spec.rb`

Happy:

- renders `[label]` exactly.
- renders cover at `:shelf` variant.
- `href` resolves to the right target.

Sad:

- `cover_source: nil` renders placeholder, not a broken image.

Edge:

- long labels wrap predictably (CSS class confirmed in spec via class
  assertion).

Flaw:

- `cursor: pointer` applied (class assertion).

### Model — `spec/models/game_spec.rb` (additions)

Happy:

- `Game.in_genre('action')` returns games tagged with the action genre.

Sad:

- `Game.in_genre('nonexistent')` returns an empty relation, does not error.

### Request — `spec/requests/games_spec.rb` (additions)

Happy:

- `GET /games?genre_slug=action` filters the listing.
- `GET /games?genre_slug=action&filters=owned` composes with filter row.

### System — `spec/system/games_index_spec.rb` (additions)

Happy:

- visiting `/games`, clicking a Genre tile updates URL with `?genre_slug=<slug>`
  and narrows the listing.
- clicking a Collection tile navigates away to `/collections/:slug`.

---

## yes / no boundary

No external booleans on this surface.

---

## Friendly URL preservation

- `genre_slug` uses Genre's existing FriendlyId slug.
- Collection tile `href` uses Collection's existing FriendlyId slug.

---

## Manual test recipe

1. Open `/games`. Confirm two horizontal shelves render above the filter row.
2. Each shelf scrolls horizontally with the skinned scrollbar.
3. Tiles render at `:shelf` cover size (visibly smaller than the grid tiles
   below).
4. Click a Genre tile — URL gains `?genre_slug=<slug>`; listing narrows.
5. Compose with filter row — click `[owned]`; URL becomes
   `?genre_slug=action&filters=owned`; listing narrows further.
6. Click a Collection tile — navigates to `/collections/<slug>`.

---

## Cross-stack scope

| Surface    | In scope                                              |
| ---------- | ----------------------------------------------------- |
| Rails web  | YES — shelves on `/games`                             |
| Rails MCP  | NO — `genre_slug` already supported via existing tool |
| `pito` CLI | NO — CLI shelves can land in a follow-up if needed    |
| Website    | NO                                                    |

---

## Open questions

1. **Does `Game has_many :genres` already exist?** If not, this sub-spec needs a
   migration + association; surface to master agent.
2. **`Collection` `kind: :custom` filter** — confirm Collection currently has a
   `kind` enum distinguishing "custom" (user-made) from any system or
   IGDB-derived collections. If not, drop the filter and show all collections.
3. **Empty shelf rendering** — render an empty scroll-wrapper or hide the shelf
   entirely when zero items? Architect leans: render the wrapper with a muted
   "(no genres yet)" / "(no collections yet)" placeholder so the layout doesn't
   shift.
4. **Shelf height with `:shelf` variant** — locked to ~203 px (cover height)
   - ~24 px label row. Confirm in `docs/design.md` update.
5. **Genre tile cover source** — Genres typically don't have a cover image on
   their own. Should we render a representative game's cover, or a text tile
   with the genre name only? Architect leans text-only tile (no cover) for
   Genres; cover for Collections (since Collections curate games and can pick a
   representative cover).
