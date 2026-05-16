# 05 — Games index: shelves-by-letter only (drop grid + list)

> Phase 27 v2 spec. Collapses `/games` to a SINGLE layout — shelves —
> dropping the grid and list display modes (and their persistence) entirely.
> Reworks the shelf set: one shelf per genre (alphabetical), one shelf for
> the collections row, one shelf per letter for the master "all" listing.
> Introduces short genre names and explicit cover-art size tracks (two
> sizes — one for genres+collections shelves, one for individual game
> tiles). Repo-wide slim scrollbar audit at 4-6px thickness for both
> horizontal and vertical bars.

---

## Goal

The `/games` page becomes a single dense, browsable surface — three layers
of shelves stacked vertically. No mode switcher, no localStorage choice, no
display-mode persistence on the user record. The user scrolls; that is the
navigation. Shelves are horizontally scrollable when content overflows,
with the project's themed slim scrollbar (4-6px) reused.

This spec consolidates the genre/collection/letter shelves into a single
mental model so the user can predict what the page shows: "every genre I
own at least one game in, every collection, every letter that has at least
one game."

---

## Scope in

- Delete the three-mode display switcher introduced in 01d (grid / list /
  shelves-by-letter). Drop `User#preferred_games_display_mode` and the
  `Users::GamesPreferencesController`.
- Drop `_grid_mode.html.erb`, `_list_mode.html.erb`,
  `_shelves_by_letter_mode.html.erb`, `_display_mode_switcher.html.erb`.
- Drop the URL `?display=` param + the controller's
  `resolved_display_mode` helper.
- Collapse the index view to a single rendering path: genres outer shelf
  → hairline → collections outer shelf → hairline → filter row → letter
  shelves.
- Letter shelves: one shelf per starting letter (case-insensitive on the
  first character of `Game.title`). Letters with zero games are HIDDEN.
  Digits / symbols collapse to a single `#` bucket at the END (or top,
  see Open questions — pinned).
- One shelf per genre: heading is the SHORT genre name (per mapping
  below); games inside the shelf are alphabetical by title (case-
  insensitive). Each shelf carries the themed horizontal-scroll skin.
- One shelf for collections, listed alphabetically by `Collection.name`.
  The leading tile per collection is the composite cover (per spec 02).
- TWO cover sizes:
  - **Shelf-tile size** for individual game tiles inside any shelf —
    98 × 130 (the existing `:shelf` cover variant from `01e`). Unchanged.
  - **Composition-tile size** for collection composite tiles AND for
    genre-row leading tiles (if a genre row gets a composite, which is
    out of scope here — see Open questions). For now this is the same
    98 × 130; the spec separates the names so a future re-size of one
    set without the other is a one-place change.
- Short genre names — a lookup table mapping `Genre.name` → short label.
  See "Genre short names" section. Used ONLY for the shelf heading; the
  full name still lives in the `Genre` row.
- Slim scrollbar audit: walk every horizontal AND vertical scrollbar
  styling in the repo (currently `8px` in many places per recent commit
  `c630afa`; this work tightens to 4-6 px). Confirm consistent track /
  thumb colors across themes.

## Scope out

- Pagination on `/games` (explicitly NONE — see spec 06 § "no
  pagination").
- Filter row layout — that's spec 06.
- Per-tile footer changes (year + platform logo) — that's spec 07.
- Game detail page — spec 08.
- The bundles shelf and "recently played" shelf currently rendered above
  the all-games partition. Recommendation: KEEP them as additional
  shelves (above the genre shelves), since the user prompt's "one shelf
  per genre, one for collections, one per letter" did not call them out
  to drop. Confirm in Open questions; default is keep.
- Keybindings — that's spec 09.

---

## Files to change

### Delete (model / controller / migration / view / spec)

- `app/views/games/_grid_mode.html.erb` (delete)
- `app/views/games/_list_mode.html.erb` (delete)
- `app/views/games/_shelves_by_letter_mode.html.erb` (delete)
- `app/views/games/_display_mode_switcher.html.erb` (delete)
- `app/controllers/users/games_preferences_controller.rb` (delete)
- `config/routes.rb` — remove `resources :games_preferences, only:
  [:update]` (or whatever the existing route declaration is) under the
  `users` namespace.
- `app/models/user.rb` — remove `enum preferred_games_display_mode`
  declaration and the related scope.
- `db/migrate/<TS>_drop_preferred_games_display_mode_from_users.rb`
  (NEW) — `remove_column :users, :preferred_games_display_mode, :integer`.
- `spec/models/user_spec.rb` — drop the enum specs.
- `spec/requests/users/games_preferences_spec.rb` (delete).
- `spec/system/games_display_modes_spec.rb` (delete).
- The 01d-era `_display_mode_switcher` partial spec (delete).
- The 12 `display mode resolution (Phase 27 §01d)` request examples in
  `spec/requests/games_spec.rb` (delete).
- The `data-display-mode="grid"` test scaffolding in the existing 01b
  contradiction-notice spec — re-anchor to a stable surrogate (the
  shelves-by-letter wrapper).

### Rewrite (controller + index view)

- `app/controllers/games_controller.rb#index`
  - Drop `@display_mode = resolved_display_mode` and the helper.
  - Drop `@bundles_shelf` + `@recently_played` + `@platforms_shelves`
    references IF the open question lands on "drop them" (default
    keeps them — see Open questions).
  - Add `@letter_buckets`: an Array of `[letter, games_relation]`
    tuples for non-empty letter buckets. Build via a single grouped
    query: `Game.primaries.where(...).group_by { |g|
    g.title.first.upcase if g.title.first =~ /[A-Z]/ } ` then merge
    digits / symbols into a `#` bucket.
  - Genres outer shelf input (`@genres_for_shelf`) — unchanged from
    01c-v2. Confirm scoping reads `primary_genre_id`.
  - Collections outer shelf input (`@collections_for_shelf`) — unchanged.
  - Filter pipeline (`@filter_tokens`, `Games::Filter`) — unchanged in
    this spec; spec 06 reworks the filter row but the controller
    plumbing is mostly intact.

- `app/views/games/index.html.erb`
  - Drop the H2 `all` heading and the case/when display-mode branch.
  - Replace with: `<%= render "games/letter_shelves", buckets:
    @letter_buckets %>`.
  - Drop the display-mode switcher render in the filter-row's
    right-slot.
  - Keep the genres outer shelf and collections outer shelf in their
    current order (above the filter row).
  - Reorder per the new contract:
    1. Page title `games` + `[+]`.
    2. Filter row (spec 06 reworks the filter row layout itself).
    3. Bundles shelf (if kept — Open questions).
    4. Recently-played shelf (if kept — Open questions).
    5. Hairline.
    6. Genres outer shelf (one sub-shelf per genre, short heading
       names per the lookup table).
    7. Hairline.
    8. Collections shelf (one sub-shelf — the collection composites
       laid out horizontally; click a tile opens the existing
       collections-modal pane).
    9. Hairline.
    10. Letter shelves (one shelf per non-empty letter A..Z, then
        `#` bucket if non-empty).

- `app/views/games/_letter_shelves.html.erb` (NEW)
  - Wraps the per-letter shelf iteration. Each shelf is one `<section
    class="shelf">` with an `<h3>` heading carrying the letter, then a
    horizontal-scroll row of `Games::CoverComponent` shelf-variant
    tiles, sorted alphabetical by title within the bucket.
  - Reuses the `steam-shelf` Stimulus controller for drag-scroll +
    wheel-to-horizontal scroll.

- `app/views/games/_genres_shelf.html.erb` /
  `app/views/games/_genre_sub_shelf.html.erb`
  - Confirm each sub-shelf is alphabetical by `LOWER(games.title)`.
  - Switch the `<h3>` heading from `<%= genre.name %>` to
    `<%= short_genre_name(genre) %>` (helper introduced below).

### Helpers

- `app/helpers/games/genre_short_names_helper.rb` (NEW)
  - Method `short_genre_name(genre) -> String`. Looks up
    `Genre.name` in the static mapping below; falls back to
    `Genre.name` when no mapping exists.

### CSS — slim scrollbar audit

- `app/assets/tailwind/application.css`
  - Find every `::-webkit-scrollbar { width: ... }` /
    `::-webkit-scrollbar { height: ... }` rule. Today many sit at 8 px;
    the recent commit `c630afa` already moved some to 6 px (vertical
    matches horizontal). Audit and unify at 6 px both axes (or 4 px on
    secondary surfaces — pick one bracket per surface and document).
  - Apply across: horizontal shelf overflow scrollbars, the pane-row
    horizontal scrollbar, every `<dialog>` body vertical scrollbar,
    the dropdown menus, modal bodies. Document which surfaces moved.

---

## Genre short names (lookup)

The user pinned: "Use SHORT genre names: RPG, FPS, JRPG, Sim, MOBA, etc."
Below is the architect's full mapping. The helper takes the IGDB-canonical
`Genre.name` and returns the short label. Unknown names fall through to
the canonical `Genre.name`.

| IGDB canonical                           | Short label    |
| ---------------------------------------- | -------------- |
| Role-playing (RPG)                       | RPG            |
| Japanese Role-Playing Game (JRPG)        | JRPG           |
| Shooter                                  | FPS            |
| First-person Shooter                     | FPS            |
| MOBA                                     | MOBA           |
| Real Time Strategy (RTS)                 | RTS            |
| Turn-based strategy (TBS)                | TBS            |
| Simulator                                | Sim            |
| Sport                                    | Sport          |
| Racing                                   | Racing         |
| Fighting                                 | Fighting       |
| Adventure                                | Adventure      |
| Platform                                 | Platformer     |
| Puzzle                                   | Puzzle         |
| Strategy                                 | Strategy       |
| Pinball                                  | Pinball        |
| Arcade                                   | Arcade         |
| Music                                    | Music          |
| Hack and slash/Beat 'em up               | Hack/Slash     |
| Quiz/Trivia                              | Quiz           |
| Tactical                                 | Tactical       |
| Visual Novel                             | VN             |
| Indie                                    | Indie          |
| Card & Board Game                        | Card           |
| Point-and-click                          | Adventure      |

The mapping is a Ruby constant `SHORT_NAMES = { ... }.freeze` in the
helper. Keys are the EXACT strings IGDB returns; the helper does
case-sensitive lookup, falling through to `Genre.name` for any miss.

---

## Behavior contracts

### Letter bucketing

- Bucket key: first character of `Game.title` uppercased, when in
  `[A-Z]`. Otherwise `'#'`.
- Empty buckets are HIDDEN (the section does not render).
- Buckets render alphabetical A..Z first, then `#` (numeric / symbol)
  at the end.
- Within each bucket, games are sorted by `LOWER(title)`, then `id` for
  tie-break.

### Cover-art size split (LOCKED)

- `Games::CoverComponent` keeps two variants:
  - `:grid` (150 × 200) — UNUSED on `/games` after this spec. Stays in
    the component for future use; the grid-mode removal does not delete
    the variant. Document this.
  - `:shelf` (98 × 130) — used by every shelf tile on `/games`
    (genres, collections sub-shelf interior, letter shelves).
- Composite covers (collections) — also 98 × 130, matching `:shelf`.
  Pinned by spec 02.

### Filter row position

- Sits BETWEEN the page title row and the bundles / recently-played /
  genre shelves. (Spec 06 owns the row's internal layout.)

### Scrollbar styling

- Both axes: 6 px (target). The `c630afa` commit already moved
  vertical from 8→6; this spec extends to horizontal where still 8.
- Auto-hide on idle (existing pattern), themed track / thumb colors.

### No persistence

- No `User#preferred_games_display_mode` — column dropped, controller
  dropped, switcher dropped.
- Page state is URL-driven exclusively (filters via `?filters=`, genre
  via `?genre=`, collection via `?collection=` — all unchanged).

---

## Migrations

```ruby
class DropPreferredGamesDisplayModeFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :preferred_games_display_mode
  end

  def down
    add_column :users, :preferred_games_display_mode, :integer, default: 0,
               null: false
  end
end
```

---

## ViewComponents

None new. `Games::CoverComponent` is reused as-is.

---

## Stimulus controllers

- `steam_shelf_controller.js` — reused on every shelf. No change.
- Drop the `display_mode_switcher_controller.js` if one exists (verify;
  the switcher may have been a vanilla `button_to` form with no JS).

---

## Spec coverage required

### Controller / request spec (`spec/requests/games_spec.rb`)

- `GET /games` returns 200, renders one `<section class="shelf">` per
  non-empty letter bucket.
- A library with games starting with `A`, `B`, `F`, `M`, `Z` renders
  exactly 5 letter shelves (no empty letters).
- Digit-titled games (`"7 Days to Die"`) land in the `#` bucket at the
  end of the iteration.
- `?display=list` is IGNORED (the param is removed from the
  resolver — controller emits the default shelves layout regardless).
- No `data-display-mode` attribute anywhere in the rendered HTML.

### View specs

- `spec/views/games/index.html.erb_spec.rb` — top-level structure
  asserts the rendering order (page title → filter row → genres outer →
  collections outer → letter shelves).
- `spec/views/games/_letter_shelves.html.erb_spec.rb` (NEW) — renders
  one section per non-empty letter; correct heading; tiles ordered
  alphabetical; `#` bucket renders only when present.
- `spec/views/games/_genre_sub_shelf.html.erb_spec.rb` — heading uses
  the short name (`RPG`, `JRPG`, `Sim`, etc.) for known IGDB names;
  falls through to the canonical name for unmapped genres.

### Helper spec (`spec/helpers/games/genre_short_names_helper_spec.rb`)

- `short_genre_name(genre_with_name("Role-playing (RPG)"))` → `"RPG"`.
- `short_genre_name(genre_with_name("Shooter"))` → `"FPS"`.
- `short_genre_name(genre_with_name("Adventure"))` → `"Adventure"`
  (one-to-one mapping).
- Unknown genre name (`"Pumpkin Spice Latte"`) → returns the canonical
  name unchanged.
- Nil genre → returns `"—"` (or raises ArgumentError — pin behavior at
  implementation).

### Model spec (`spec/models/user_spec.rb`)

- The `preferred_games_display_mode` enum no longer exists. The spec
  should fail loudly on any reference.

### Migration spec

- After the migration, `User.column_names` does not include
  `"preferred_games_display_mode"`. Re-run the migration down/up to
  prove reversibility.

### System spec (`spec/system/games_index_spec.rb` — extend)

- ONE end-to-end scenario:
  1. Seed 12 games across 4 letters (`A`, `M`, `Z`, `7`) and 3 genres
     (`Shooter`, `Role-playing (RPG)`, `Adventure`) and 2 collections.
  2. `GET /games` → assert the page has: genres outer shelf with 3
     sub-shelves (`FPS`, `RPG`, `Adventure`), collections outer shelf
     with 2 tiles, 4 letter shelves (`A`, `M`, `Z`, `#`).
  3. No mode switcher rendered.
  4. Click a tile → navigates to game show page.
- The 01d-era display-modes system spec is DELETED.

### Scrollbar audit

- Manual verification only (visual). Documented in the manual test
  recipe.

---

## Manual test recipe (index page, single-mode)

1. `bin/dev` → open `http://localhost:3000/games`.
2. Confirm NO `[grid]` / `[list]` / `[shelves]` switcher anywhere on
   the page.
3. URL `?display=grid` does NOT change the layout — still renders the
   shelves layout.
4. Confirm: page title `games` + `[+]` → filter row → bundles shelf
   (if non-empty) → recently-played shelf (if non-empty) → hairline →
   genres outer shelf → hairline → collections shelf → hairline →
   letter shelves (one section per non-empty letter, `#` bucket at
   end if any digit/symbol-titled game).
5. Hover over any horizontal shelf — scrollbar appears thin (6 px)
   and themed.
6. Add a game whose title starts with a letter no other game has
   (e.g. `"Quake"`) — refresh `/games` — a `Q` letter shelf appears.
7. Delete the only `Q`-titled game — refresh — the `Q` shelf is gone.
8. Confirm the genre shelf heading reads the short label (e.g. `FPS`
   for a `Shooter` IGDB genre).
9. Confirm no JS console errors.

---

## Open questions

1. **Keep or drop the existing `bundles` + `recently played` shelves
   above the genre shelves?** Architect lean: keep — the user prompt
   said "one shelf per genre, one for collections, one per letter" but
   did not call out dropping bundles/recently-played. They add value
   for the workflow. Confirm during review.
2. **Where does the `#` (digit / symbol) bucket render — top or
   bottom?** Architect lean: BOTTOM. After Z, so the A..Z run feels
   natural and "everything else" is the tail. Confirm.
3. **Composite covers on genre rows?** The user prompt mentioned "TWO
   cover sizes: one for genres+collections shelves (collection
   composition), one for individual game tiles." That phrasing
   suggests genre rows ALSO render a composite (the genre's top N
   games as a composite tile). v2 default: NO composite on genre
   rows — each sub-shelf is a horizontal row of individual game tiles
   (matches existing 01c-v2 behavior). If the user wants genre rows
   to ALSO have a leading composite tile, surface as a follow-up.
4. **Slim scrollbar bracket — 4 px or 6 px?** Architect lean: 6 px
   for primary scrolls (page, shelves), 4 px for secondary (dropdown,
   small modal). Confirm.
5. **Pagination — explicitly none, even for libraries with 5000+
   games?** Architect lean: yes, none. The letter-shelf groupings
   bound the per-row count; total DOM size is acceptable up to a few
   thousand games. If perf becomes painful, introduce a per-shelf
   `[see all]` link as a follow-up (out of scope here).
6. **Drop the `Users::GamesPreferencesController` entirely vs leave a
   stub that 410s?** Architect lean: drop entirely. Any saved bookmark
   to `/users/games_preferences/...` 404s — acceptable.
