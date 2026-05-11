# 01c v2 — Nested Shelves (Genres / Collections)

> **Corrected from 70% draft — locked decision §1 is 65% (98 × 130 px against
> the real 150 × 200 grid).** Every `70%` / `105 × 140` reference below is a
> historical artefact of an in-flight draft that proposed bumping the variant;
> the master agent reaffirmed 65% (matching 01e and the shipped
> `Games::CoverComponent` `:shelf` variant). Treat the 70% / 105 × 140 lines as
> superseded; the real values are 65% / 98 × 130.

> **Supersedes `01c-genres-and-collections-shelves.md`** per direct user
> direction (architect intake 2026-05-10, "nested shelves" directive). The flat
> two-shelf design that shipped under 01c is replaced by a **nested** layout: an
> outer "Genres" shelf that iterates one sub-shelf per genre, and an outer
> "Custom collections" shelf that iterates one sub-shelf per collection. Each
> sub-shelf is itself a horizontally-scrolling row of game tiles at the `:shelf`
> cover variant.
>
> Read this spec INSTEAD of 01c-v1. Anywhere this spec contradicts 01c-v1, this
> spec wins. The 01c-v1 file stays in the repo as historical record; do not
> delete it. The plan checkbox copy and a subset of the v1 checkboxes get
> un-ticked — see "Plan delta" at the bottom.

---

## Goal

Replace the flat genres / collections shelf design (one tile per genre, one tile
per collection) with a **nested** structure that surfaces actual game covers at
the top of `/games`:

```
/games
├── [Outer shelf] Genres
│   ├── [Sub-shelf] Adventure   — games where primary_genre = Adventure
│   │   └─ horizontally-scrolling row of :shelf-variant game tiles
│   ├── [Sub-shelf] RPG
│   ├── ... one sub-shelf per non-empty genre, alphabetical
│
├── [Outer shelf] Custom collections
│   ├── [Sub-shelf] My favorites
│   │   └─ leading compound-cover collection tile + horizontally-scrolling
│   │      row of :shelf-variant game tiles
│   ├── [Sub-shelf] Replay queue
│   ├── ... one sub-shelf per non-empty collection, alphabetical
│
└── [Main listing area]
    ├── [grid] [list] [shelves] display-mode switcher (01d)
    ├── Filter row (01b)
    └── Listing (Grid mode renders the 150 × 200 :grid variant)
```

A game with multiple genre associations now picks ONE bucket via a new
`Game#primary_genre_id` pointer; it appears under exactly that genre's
sub-shelf, no duplication across sub-shelves.

For collections, the leading tile is a **compound cover** rendered server-side
by the new `Collections::CoverComposer` (specced in `01h`), which reuses the
existing Phase 14 `Composite::Builder` pipeline via a freshly-extracted
`Compositable` concern.

---

## Files touched

### Migrations

- `db/migrate/<ts>_add_primary_genre_id_to_games.rb` — adds
  `games.primary_genre_id :bigint`, nullable, FK to `genres.id`, indexed. Data
  migration: backfill from `game_genres` (pick the first genre by
  `LOWER(name)` ASC, `id` ASC for tie-break). Games with zero genre
  associations stay NULL.
- `db/migrate/<ts>_add_composite_columns_to_collections.rb` — adds
  `collections.composite_cover_path :string` and
  `collections.composite_cover_checksum :string`, both nullable. No index.
  Mirrors the existing `bundles` shape so the `Compositable` concern can share
  one accessor set.

### Models

- `app/models/game.rb`
  - Add `belongs_to :primary_genre, class_name: "Genre", optional: true`.
  - Add `before_save :nilify_primary_genre_if_orphaned` (or equivalent
    in-association callback) — if `primary_genre_id` no longer points to one of
    the game's currently associated genres, set it to nil so the show/edit UI
    can re-prompt.
  - Add scope `scope :with_primary_genre, ->(genre_id) { where(primary_genre_id: genre_id) }`.
  - Update `Game#after_save` / `after_commit` on the join (see GameGenre below)
    — when `genres` association changes such that the current primary is no
    longer associated, nil it. Implementation note for the implementer: the
    cleanest hook lives on the join model (`GameGenre`) since the change comes
    through there; encode the rule wherever the implementer judges least
    spooky. The behavior is what matters.

- `app/models/genre.rb`
  - Add `has_many :primary_for_games, class_name: "Game", foreign_key: :primary_genre_id, dependent: :nullify`.
  - Add scope `scope :with_primary_games, -> { joins(:primary_for_games).distinct }`
    — used by the outer Genres shelf to skip empty buckets.

- `app/models/game_genre.rb`
  - Add `after_destroy_commit :nilify_primary_on_parent_if_orphaned` — when the
    join row removed is the one backing the game's `primary_genre_id`, nil
    the parent's column.

- `app/models/collection.rb`
  - Add `include Compositable`.
  - Add a `#cover_url(variant: :shelf)` method that returns the composite cover
    URL when present; nil otherwise. (Sub-shelf rendering branches on presence
    — see view specs below.)
  - Add scope `scope :with_games, -> { joins(:games).distinct }` — used by the
    outer Custom collections shelf to skip empty buckets.

- `app/models/bundle.rb`
  - Refactor to `include Compositable`. The existing
    `composite_cover_path` / `composite_cover_checksum` columns stay; the
    accessor methods on Bundle move into the concern.

### Concerns (new)

- `app/models/concerns/compositable.rb` — extracted interface used by both
  Bundle and Collection. Defines:
  - `composite_cover_url` (returns the `/composites/<basename>` URL or nil).
  - `composite_cover_absolute_path` (Pathname via `Pito::AssetsRoot.path`, or
    nil).
  - `needs_cover_rebuild?` — abstract method; each host implements the
    member-list / checksum logic. The concern defines the public surface; the
    body delegates to a `compositable_member_image_ids` hook the host
    implements.
  - `compositable_member_image_ids` — abstract (raise `NotImplementedError`
    when not overridden). Returns the ordered list of IGDB `cover_image_id`
    strings to feed into `Composite::Builder` / `LayoutChooser` /
    `Checksum`.
  - `compositable_kind_token` — abstract. Returns the on-disk filename prefix
    (`"bundle"` for Bundle, `"collection"` for Collection).
  - Shared `before_destroy :sweep_composite_cover_file` hook.

### Services

- `app/services/composite/builder.rb`
  - Refactor to accept any `Compositable`. Replace `bundle.bundle_members` with
    `compositable.compositable_member_image_ids` (or equivalent abstraction).
  - The output path becomes
    `Pito::AssetsRoot.path("composites", "#{compositable.compositable_kind_token}-#{compositable.id}.jpg")`.
    Bundle continues to produce `bundle-<id>.jpg`; Collection produces
    `collection-<id>.jpg`. The `CompositesController#show` regex
    `/\A[a-z_]+-\d+\z/` already accepts both forms — no controller change.
  - Keep the existing Bundle-overflow nine-grid edge-case (cap at 9 tiles for
    the overflow layout) — applies to both surfaces.

- `app/services/collections/cover_composer.rb` — **specced separately at
  `01h-collections-cover-composer.md` (in flight)**. This spec lists it under
  files touched purely so the implementer wires the call site
  (`CollectionCoverRebuildJob`) in the right place; the composer's internal
  shape is defined by 01h.

### Jobs

- `app/jobs/collection_cover_rebuild_job.rb` (new) — Sidekiq job. Loads the
  Collection, runs `Collections::CoverComposer.new(collection).call` (which in
  turn calls `Composite::Builder.new.call(collection)` per 01h). Stale-while-
  revalidate semantics: the old composite stays on disk and continues to be
  served until the new bytes overwrite it (atomic file rename — implementer
  decides between in-place overwrite and tempfile-then-rename; both are
  acceptable provided no half-written JPEG is ever readable).

- Bundle's existing `BundleCoverBuild` / `BundleCoverInvalidate` stay as-is.

### Cache invalidation hook

- `app/models/game.rb` already triggers `BundleCoverInvalidate` on
  `cover_image_id` change. Extend the hook so it also enqueues
  `CollectionCoverRebuildJob.perform_async(game.collection_id)` when the game
  belongs to a collection. (Implementation lane may also fan this out from a
  callback on the Game model — the rule is: when a Game's `cover_image_id`
  changes, the collection it belongs to gets rebuilt.)
- Game's `collection_id` change: when a Game moves into / out of a Collection,
  enqueue a rebuild for the **outgoing** and the **incoming** Collection (both,
  via `previous_changes[:collection_id]`).
- No direct hook on a "CollectionGame" join — that join does not exist; the
  Game ↔ Collection relationship is a direct `games.collection_id` column.

### Views (REWRITE)

- `app/views/games/_genres_shelf.html.erb` — REWRITE. Old behavior (flat list
  of clickable genre-name tiles) is REPLACED. New behavior:
  - Outer-shelf wrapper: `<section data-shelf="outer-genres">` with an `<h2>`
    label "Genres" using the bracketed-link convention not required on
    headings.
  - Iterates over `Genre.with_primary_games.order(Arel.sql("LOWER(name)"))`.
  - For each genre, renders `games/genre_sub_shelf` (see below).
  - Empty outer-shelf (no genres have any primary-tagged games) → hide the
    whole section (no muted placeholder, no `<h2>`).
- `app/views/games/_collections_shelf.html.erb` — REWRITE. Old behavior (flat
  list of clickable collection-name tiles) is REPLACED. New behavior:
  - Outer-shelf wrapper: `<section data-shelf="outer-collections">` with an
    `<h2>` label "Custom collections".
  - Iterates over `Collection.with_games.order(Arel.sql("LOWER(name)"))`.
  - For each collection, renders `games/collection_sub_shelf`.
  - Empty outer-shelf (no collections own any games) → hide the whole section.
- `app/views/games/_genre_sub_shelf.html.erb` (new) — one sub-shelf per genre.
  Renders an `<h3>` row with the genre name on the left and a `[see all]`
  bracketed link on the right (only when the bucket exceeds the cap; see
  ordering rule below). Inside, a horizontally-scrolling skinned-scroll
  container with one `Games::CoverComponent` per game at `variant: :shelf`.
  - Local: `genre`.
  - Game collection passed in:
    `genre.primary_for_games.order(Arel.sql("LOWER(title)")).limit(30)`.
- `app/views/games/_collection_sub_shelf.html.erb` (new) — one sub-shelf per
  collection. Mirror of the genre sub-shelf, with one extra leading tile:
  - First tile in the row: collection compound-cover tile. Renders an `<a>`
    linking to `/collections/<slug>`. The image source is the composite cover
    served by `CompositesController` (`/composites/collection-<id>`). The
    compound cover slot is sized at the `:shelf` variant dimensions (105 × 140
    after the size change below — see "Locked size change") so the visual
    rhythm of the row is unbroken.
  - Following tiles: individual `Games::CoverComponent` at `variant: :shelf`
    for each game in `collection.games.order(Arel.sql("LOWER(title)")).limit(30)`.
  - `[see all]` link on the `<h3>` row when the bucket exceeds the cap.
- `app/views/games/index.html.erb` — renders the two outer-shelf partials at
  the top of the page, above the display-mode switcher and filter row. (This
  section of `index.html.erb` already calls the v1 partials — the rewrite
  preserves the call sites, only the partial bodies change.)

### Cover component (size update)

- `app/components/games/cover_component.rb`
  - `DIMENSIONS[:shelf]` changes from `{ width: 98, height: 130, ... }` to
    `{ width: 105, height: 140, ... }` — **70% of 150 × 200**, locked decision
    #1 in "Locked decisions" below.
  - The IGDB source token `t_cover_small_2x` stays — 180 × 256 native still
    downsamples cleanly into 105 × 140. No CDN-side change.
  - The class doc comment block needs the "Size decision — `:shelf` at 70%"
    section to replace the existing "65%" rationale (paragraphs labeled "50% of
    150 × 200" / "65% of 150 × 200" / "70% of 150 × 200" — keep the comparison
    table, change the "Chosen" line to 70%).

### Tailwind / CSS

- `app/assets/tailwind/application.css`
  - `.game-cover--shelf { width: 105px; height: 140px; }` — replace the
    existing 98 × 130 rule.
  - No `transform: scale`, no percentage widths. Real pixels per the existing
    01e rule.
  - Add `.shelf-sub-row` (or equivalent) — flex row, gap, horizontal scroll,
    overflow auto. Reuse the existing skinned-scroll class if one is already
    in use under the v1 partials.

### Routes / controllers

- `app/controllers/games_controller.rb`
  - `#index` accepts `?genre=<slug>` and `?collection=<slug>` (existing param
    names, no change to the action signature — they already work per the v1
    log).
  - Drop the `genre_slug` legacy param name from the action and view links
    (consolidate on `?genre=` and `?collection=`). If the legacy name appears
    in a view, route helper, or saved-view, it must be migrated. (The 01c-v1
    landing actually uses `?genre=` and `?collection=` already — confirmed in
    the 01c session log; this is a no-op in the controller, but a fresh
    inventory pass on call sites is part of acceptance.)
- `app/controllers/composites_controller.rb` — **no change**. The existing
  `FILENAME_REGEX = /\A[a-z_]+-\d+\z/` already accepts `collection-<id>` as
  a valid name.

### Specs (full pyramid per project rule D)

- Model:
  - `spec/models/game_spec.rb` — `belongs_to :primary_genre`, scope
    `.with_primary_genre`, nilify-on-orphan rule (cases: game has 2 genres,
    user picks one as primary, removes that genre from the join → primary
    nils out; covers happy + sad + edge — single genre, zero genres, all
    same-named genres tie-broken by id).
  - `spec/models/genre_spec.rb` — `has_many :primary_for_games`, scope
    `.with_primary_games`, dependent-nullify on genre destroy (when a genre
    is deleted, downstream games' `primary_genre_id` nils — not orphaned to
    a dangling ID).
  - `spec/models/collection_spec.rb` — `include Compositable`, the new
    `composite_cover_path` / `composite_cover_checksum` accessors, the
    `#cover_url(variant: :shelf)` resolution path (returns
    `/composites/collection-<id>` when path is present; nil otherwise), the
    `with_games` scope.
  - `spec/models/bundle_spec.rb` — assert the Compositable extraction did not
    regress the existing public surface (`composite_cover_url`,
    `composite_cover_absolute_path`, `needs_cover_rebuild?`). Existing 14 §2
    specs should pass byte-identical against the refactored model.
  - `spec/models/concerns/compositable_spec.rb` (new) — shared-examples
    coverage that both Bundle and Collection conform to the interface
    (using `RSpec.shared_examples "a Compositable host"` or equivalent).

- Service:
  - `spec/services/composite/builder_spec.rb` — extend existing spec. Add a
    new `context "with a Collection compositable"` that exercises the build
    path against a fixture Collection with 1 / 2 / 3 / 5 / 9 / 12 cover-image
    ids. Filename written is `collection-<id>.jpg`. Checksum reuses the same
    canonical algorithm. Existing Bundle examples stay green.

- Job:
  - `spec/jobs/collection_cover_rebuild_job_spec.rb` (new) — enqueue + perform,
    happy / sad / edge (collection missing → no-op; collection with zero
    games → composite path + checksum cleared); flaw — never raises uncaught
    on a missing record (Sidekiq retry is expensive).

- Component:
  - `spec/components/games/cover_component_spec.rb` — update the existing
    `:shelf` examples to assert 105 × 140 (replaces 98 × 130). The 28 existing
    examples need a one-line constant update each. NO new examples; this is a
    pure size delta.

- View:
  - `spec/views/games/_genres_shelf.html.erb_spec.rb` (REWRITE) — the existing
    spec asserts a flat list of tiles. Rewrite to assert: outer-shelf
    wrapper, one `<h3>` per genre, alphabetical order (case-insensitive),
    empty genres hidden, `[see all]` only when count > 30, no muted-empty
    placeholder anywhere.
  - `spec/views/games/_collections_shelf.html.erb_spec.rb` (REWRITE) —
    same shape; additionally assert the leading compound-cover tile renders
    only when `collection.composite_cover_path.present?` (collections without
    a built composite render a fallback tile — see "Open questions" below).
  - `spec/views/games/_genre_sub_shelf.html.erb_spec.rb` (new) — partial-level
    coverage of a single sub-shelf: `<h3>` row, game count cap (30), `[see
    all]` link only when capped, scroll container, `:shelf` cover variant
    applied to each game tile, alphabetical ordering.
  - `spec/views/games/_collection_sub_shelf.html.erb_spec.rb` (new) — mirror
    of the above plus the leading compound-cover tile assertion.

- Request:
  - `spec/requests/games_spec.rb` — extend "Phase 27 §01c" block. Add
    examples:
    - `GET /games` renders nested outer-shelf structure (one `<h2>` per
      outer shelf, one `<h3>` per non-empty sub-shelf).
    - `GET /games` with zero genres in the DB hides the Genres outer shelf
      (no `<h2>` rendered).
    - `GET /games` with zero collections owning games hides the Custom
      collections outer shelf.
    - `GET /games?genre=<slug>` filters the listing.
    - `GET /games?collection=<slug>` filters the listing.
    - `GET /games` does NOT include games with `primary_genre_id IS NULL` in
      any sub-shelf (only in the main listing below).

- System:
  - `spec/system/games_index_spec.rb` — extend. One critical-path scenario:
    user lands on `/games`, sees nested shelves, clicks the `[see all]` link
    on a sub-shelf, lands on the filtered listing. Per architect rule D,
    system spec is selective — one happy-path scenario, not a sweep.

- Game show / edit (primary-genre picker — see "UI: primary genre selection"):
  - `spec/views/games/show.html.erb_spec.rb` — primary genre label rendered
    when set; nothing rendered when nil.
  - `spec/views/games/edit.html.erb_spec.rb` — dropdown rendered when the
    game has ≥ 2 genres; hidden when 0 genres; pre-selected to the lone
    genre when exactly 1.
  - `spec/requests/games_spec.rb` (or
    `spec/requests/games/primary_genre_spec.rb` if the implementer prefers a
    namespaced request spec) — `PATCH /games/:slug` accepts
    `game[primary_genre_id]`; rejects an id that is not in the game's
    `genre_ids` (validation error, not silent ignore).

---

## Locked decisions (master agent, this spec)

These supersede or extend the plan-level locked decisions. The plan.md needs
a small edit per the "Plan delta" section.

1. **`:shelf` cover variant size: 70% of grid (105 × 140 px).** Supersedes
   plan locked decision #1, which read "65% (≈ 152 × 203 px)" but actually
   shipped at 65% of the real 150 × 200 grid → 98 × 130. The user's intake
   asked for "either 50, 60, or 70%"; architect picks **70% for legibility**.
   The original 65% rationale (lower end of the addendum's 65–70% fallback
   range) was a defensible read of the addendum but produced tiles that the
   user found cramped in practice. 105 × 140 retains a recognizable cover at
   the cost of ~14% horizontal density per row — acceptable.
2. **Nested structure replaces flat.** The flat-tile design (one tile per
   genre / one tile per collection) is dropped entirely. Outer shelves
   iterate sub-shelves of game-cover tiles.
3. **`Game#primary_genre_id` column.** Nullable FK to `genres.id`, indexed,
   `dependent: :nullify` from the Genre side. Backfill on migration: pick
   the first associated genre by `LOWER(name)` ASC, `id` ASC for tie-break.
   Games with zero genre associations stay NULL.
4. **Primary-genre orphaning rule.** When a Game's `genres` association
   changes such that `primary_genre_id` no longer matches one of the
   currently-associated genres, the column is nilled out (no exception, no
   silent reassignment to another genre). User re-picks in the show/edit UI.
5. **Primary-genre picker UI.**
   - Game `show`: read-only display of the primary genre name (if any).
   - Game `edit`: dropdown picking from associated genres only.
     - 0 associated genres → dropdown hidden (no primary to pick).
     - 1 associated genre → dropdown hidden, primary auto-set on save.
     - ≥ 2 associated genres → dropdown rendered with current value
       pre-selected (blank option allowed → nilify primary).
   - Submission goes through the existing `PATCH /games/:slug` action and
     the existing `local_only_params` permit list (`primary_genre_id`
     added to the permit set).
6. **Game appears in exactly ONE genre sub-shelf** — the one matching its
   `primary_genre_id`. A multi-genre game does not duplicate across
   sub-shelves.
7. **Empty buckets hidden.** Empty genres (no games where
   `primary_genre_id = <genre.id>`) and empty collections (no
   `games.collection_id = <collection.id>` rows) are skipped during outer-
   shelf iteration. No "(none yet)" placeholders inside the genre / collection
   enumeration. This **reverses 01c-v1 open question #3** (which had leaned
   toward muted placeholders) — the new directive is "if it has no games,
   it's not on the page."
8. **Sub-shelf ordering: alphabetical by `Game#title`** (case-insensitive),
   capped at 30. Beyond 30, a `[see all]` link to `/games?genre=<slug>` or
   `/games?collection=<slug>` opens the filtered listing in the main area.
   30 is the cap because shelves longer than that turn into endless
   horizontal scrolling; the user is expected to switch to grid or list
   mode for the long tail.
9. **`[see all]` URL pattern: `?genre=<slug>` / `?collection=<slug>`.**
   Drops the legacy `?genre_slug=` name from any leftover code path. The
   01c-v1 log confirms the live action already accepts both
   `?genre=<slug>` and `?genre=<id>` — the slug form is the canonical
   `[see all]` target; id fallback stays for hand-typed URLs.
10. **Compound cover for collection sub-shelves.** Each non-empty Collection
    sub-shelf renders a compound cover as its **leading** tile (left edge of
    the horizontal row). The compound cover is produced by the new
    `Collections::CoverComposer` (specced in `01h`), built async via
    `CollectionCoverRebuildJob`, served via `CompositesController#show` at
    `/composites/collection-<id>.jpg`.
11. **`Composite::Builder` reuse via `Compositable` concern.** The current
    builder is hard-coupled to Bundle (`bundle.bundle_members`,
    `composite_cover_path`, `composite_cover_checksum` accessors, output
    filename `bundle-<id>.jpg`). Refactor into a `Compositable` model
    concern that both Bundle and Collection include. Builder consumes any
    Compositable. Output filename derives from the host's
    `compositable_kind_token` (`"bundle"` / `"collection"`).
12. **Collection composite cache invalidation.** When the membership of a
    Collection changes (games added / removed / a member game's
    `cover_image_id` changes), enqueue `CollectionCoverRebuildJob` async.
    Stale-while-revalidate: the existing composite stays readable on disk
    until the rebuild completes and writes new bytes. No HTTP-level cache
    busting — `CompositesController` does not set ETags; the browser refetch
    cycle is the existing image-tag mechanism.

---

## yes / no boundary

No external booleans on this surface (no checkbox params, no truthy URL
flags). The `primary_genre_id` picker carries an integer FK, and the
`[see all]` link uses slug strings. The plan-wide yes / no rule applies to
01b's filter row and 01g's MCP surface, not here.

---

## Friendly URL preservation

- `?genre=<slug>` uses `Genre`'s existing slug column. (The 01c-v1 log notes
  `genres.slug` is not unique-indexed — out of scope here, queued as a
  one-line follow-up unrelated to the nested-shelves design.)
- `?collection=<slug>` uses `Collection#friendly_id` (slugged + history +
  finders per the existing Phase 20 setup).
- Compound-cover image URL `/composites/collection-<id>.jpg` uses the
  numeric id deliberately — the filename is on disk and the regex on
  `CompositesController` requires `[a-z_]+-\d+`. Slugs would invalidate the
  guard.

---

## Acceptance

- [ ] Migration adds `games.primary_genre_id` (nullable FK, indexed); data-
      backfill populates from `game_genres` (first by `LOWER(name)` ASC, `id`
      ASC). Idempotent if re-run.
- [ ] Migration adds `collections.composite_cover_path` and
      `composite_cover_checksum` (both nullable, no index).
- [ ] `Game#primary_genre` association + `Genre#primary_for_games` reverse.
- [ ] Primary-genre orphaning rule fires on `GameGenre#after_destroy_commit`
      and on `Game#before_save` (defense in depth — covers direct
      `primary_genre_id=` assignment that doesn't match `genre_ids`).
- [ ] `Compositable` concern extracted; Bundle includes it; existing Bundle
      specs pass byte-identical.
- [ ] Collection includes Compositable; `#cover_url(variant: :shelf)` resolves
      to `/composites/collection-<id>.jpg` when path is present, nil
      otherwise.
- [ ] `Composite::Builder` no longer references `Bundle` directly — receives
      any Compositable.
- [ ] `CollectionCoverRebuildJob` enqueues on collection membership change
      (game enters / leaves the collection, game's `cover_image_id` changes).
- [ ] `app/views/games/_genres_shelf.html.erb` REWRITTEN — nested outer-shelf
      + sub-shelf structure; empty buckets hidden.
- [ ] `app/views/games/_collections_shelf.html.erb` REWRITTEN — same shape,
      plus leading compound-cover tile per sub-shelf.
- [ ] `app/views/games/_genre_sub_shelf.html.erb` + `_collection_sub_shelf.html.erb`
      partials in place.
- [ ] `Games::CoverComponent` `DIMENSIONS[:shelf]` updated to 105 × 140.
- [ ] Tailwind `.game-cover--shelf` updated to 105 × 140 pixel dimensions.
- [ ] Primary-genre picker rendered on `Game#edit` when ≥ 2 genres associated;
      hidden when 0; auto-set when exactly 1.
- [ ] `Game#show` displays the primary genre name (read-only) when set.
- [ ] `PATCH /games/:slug` accepts `game[primary_genre_id]`; rejects ids that
      are not in the game's `genre_ids`.
- [ ] All sub-shelves cap at 30 games, alphabetical by title; `[see all]`
      bracketed-link appears on the `<h3>` row only when count > 30.
- [ ] `[see all]` link targets `?genre=<slug>` / `?collection=<slug>` — no
      legacy `genre_slug` references anywhere.
- [ ] Empty genres / collections hidden from outer-shelf iteration.
- [ ] Model + service + job + concern + component + view + request + 1
      system-spec scenario — all green.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm` introduced.
- [ ] No red `#cc0000` introduced outside destructive actions (the spec does
      not introduce any).
- [ ] `bundle exec rubocop` clean on touched files.
- [ ] `bundle exec brakeman -q -w2` no new warnings.

---

## Manual test recipe

Prereqs:

1. `bin/setup` to a fresh DB, then `bin/rails db:seed`.
2. Populate test data: at least one Genre with ≥ 3 Games associated (so the
   primary-genre picker has something to choose from), at least one Genre with
   exactly 0 Games (to exercise the empty-bucket-hidden rule), and at least
   two Collections — one with 1 game, one with 12 games (to exercise the
   leading compound-cover tile + the under-cap / nearing-cap rendering).
3. Cover-image ids on each Game so IGDB cover URLs resolve. The IGDB CDN
   sources `t_cover_small_2x` for the `:shelf` variant.

Smoke walk:

1. `bin/dev` → open `http://localhost:3000/games`.
2. Confirm the **Genres** outer shelf renders at the top with one `<h2>`
   labelled "Genres".
3. Inside, confirm one sub-shelf per non-empty genre, alphabetical. The
   empty-genre fixture should NOT appear (no `<h3>` for it, no "(none)"
   placeholder).
4. Each sub-shelf renders a row of game covers at 105 × 140 px (measure with
   browser dev tools — they should be visibly larger than the v1 98 × 130
   shipping size).
5. Each sub-shelf with more than 30 games shows a `[see all]` bracketed link
   on the `<h3>` row. Click it; URL becomes `/games?genre=<slug>`; the main
   listing below narrows.
6. Scroll down past the Genres outer shelf. Confirm the **Custom collections**
   outer shelf renders next, with one `<h3>` per non-empty collection.
7. Inside each collection sub-shelf, the leftmost tile is a compound cover
   (visibly a 2×2 / 3-tile Netflix / 5-tile Netflix / 2×3 mosaic depending on
   game count, served from `/composites/collection-<id>.jpg`). Subsequent
   tiles are individual game covers at `:shelf` variant.
8. Click the compound-cover tile → navigates to `/collections/<slug>`. (Note:
   the collection show page is existing; not in this spec's scope.)
9. Click `[see all]` on the long collection sub-shelf → URL becomes
   `/games?collection=<slug>`; main listing narrows.
10. Navigate to any Game `show` page that has ≥ 2 associated genres. Confirm
    the primary genre name renders (read-only) under the title or in the
    metadata block.
11. Edit the game. The "Primary genre" dropdown shows only the game's
    associated genres, with the current primary pre-selected. Change it,
    save. Re-load show — new primary renders.
12. Edit again. Remove the genre currently set as primary from the multi-
    select genre association. Save. Re-load edit — the dropdown's current
    selection should be blank (primary nilled out). Re-load show — no
    primary-genre line rendered.
13. Add a Game to a Collection via the edit form (or via a console
    `game.update!(collection: …)`). Within ~5 seconds the
    `CollectionCoverRebuildJob` runs and the compound cover updates. Confirm
    by reloading `/games` and inspecting the `/composites/collection-<id>.jpg`
    asset (mtime should be recent).

Teardown: nothing persistent introduced beyond schema columns. To reset
between test runs, `Game.update_all(primary_genre_id: nil)` re-blanks the
seed.

---

## Cross-stack scope

| Surface              | In scope |
| -------------------- | -------- |
| Rails web (`/games`) | YES — full nested-shelves rewrite |
| Rails MCP            | NO — primary-genre column is local-only; no MCP tool change in this spec. A separate follow-up may expose `primary_genre_id` on the MCP `game_update_local` tool, but it's out of scope here. |
| `pito` CLI (Rust)    | NO — the CLI's Games view does not render Genres / Collections shelves in v1; nested rendering is a CLI follow-up parked in `docs/orchestration/follow-ups.md`. |
| Cloudflare website   | NO — marketing surface untouched. |

---

## Plan delta

The following 01c plan checkboxes need un-ticking (the v1 work that ships
under them is being replaced; the new spec re-implements the surface):

- [ ] `Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`
      — was ticked with a partial-over-ViewComponent reframe note. **Un-tick**;
      the partial bodies are being rewritten end-to-end. The "partials over
      ViewComponents" reframe stays; only the partial content changes.
- [x] Alphabetical ordering — STAYS TICKED. New code preserves this.
- [x] Use existing skinned horizontal-scroll partial / classes — STAYS
      TICKED. New sub-shelves reuse the same scroll skin.
- [ ] Tile = `:shelf` cover variant (depends on `01e`) — was annotated as
      "shipped as inline 75 × 100 px tile per 50% addendum." **Un-tick**;
      this spec replaces the inline block with `Games::CoverComponent.new(
      game:, variant: :shelf)` and bumps the variant to 105 × 140 (70%).
- [ ] Component specs, system spec — was ticked with a note pointing at the
      v1 request + system specs. **Un-tick**; the v1 system spec asserts a
      flat-tile layout that no longer exists. New specs replace it.

Plan **locked decision #1** also needs updating: the line "Shelf cover
variant size: 65% of grid (≈ 152 × 203 px against the current 234 × 312
grid)" reads against a hypothetical 234 × 312 baseline that does not exist
(the real grid is 150 × 200). The line should read: "Shelf cover variant
size: **70%** of grid (105 × 140 px against the 150 × 200 grid). Architect's
revised recommendation per the nested-shelves intake. Explicit `:shelf`
variant in the cover-rendering pipeline; never browser-resize / CSS scaling."

The 01e spec body and 01e log entry both reference 65% (98 × 130) and need
amending — but that is **out of scope for this spec**. Flag for the
master agent: `01e-shelf-cover-art-variant.md` and the 2026-05-11 01e log
entry both need a follow-up edit to reflect the 70% (105 × 140) decision,
or — more cleanly — a fresh `01e-v2-shelf-cover-art-variant.md` superseding
the old one. The pito-docs agent owns that edit; the architect flags it
here so it's not forgotten.

---

## Open questions

The master agent answers these before dispatching implementation lanes.

1. **Netflix-3 compound cover: big tile left or right?** Architect
   recommendation: **left**, matches Western reading flow and puts the
   visual anchor at the entry point of the row. (The 01h composer spec
   carries this question; flagged here for awareness.)
2. **Gap between composite tiles: 1 px or no gap?** Architect
   recommendation: **1 px**. Helps separate covers with similar art styles
   (e.g. three pixel-art indies side by side). (01h composer spec carries
   this question.)
3. **Cap on the number of GENRES rendered in the outer shelf?** If a user
   ends up with 50 IGDB genres, the outer shelf becomes a 50-deep vertical
   scroll. Recommendation: **no cap**. The outer shelf scrolls vertically
   like the rest of the page; horizontal scroll is per-sub-shelf only.
4. **Cap on the number of COLLECTIONS rendered?** Same shape, same
   recommendation: **no cap**.
5. **Fallback rendering when a Collection's composite cover has not been
   built yet** (first request after a fresh seed, or while the job is
   in-flight). Options: (a) render the leading tile as a generic placeholder
   ("collection" label + bracket frame, same 105 × 140 slot); (b) skip the
   leading tile entirely and start the sub-shelf with the first game tile;
   (c) render the first game's cover in the leading slot and stamp a
   "collection" badge. Architect leans (a) — least surprising, no layout
   shift when the job completes. The 01h composer spec also carries this
   question; whichever spec lands first authoritatively answers it.
6. **Bundles outer shelf?** The Phase 14 Bundle model is the existing
   compound-cover host. Should the `/games` page also surface a "Bundles"
   outer shelf using the same nested structure (one sub-shelf per Bundle)?
   The user's intake described only Genres + Custom collections; architect
   leans **no, defer to a separate sub-spec** if the user wants Bundles
   surfaced on `/games`. Calling out so the master agent can route it.
7. **Primary-genre column on the MCP `game_update_local` tool?** The Phase
   27 plan's MCP scope (01g) accepts plural `platform_owned_ids`. Should
   `primary_genre_id` also surface on the tool? Architect leans
   **yes, as a one-line follow-up sub-spec** (separate from this v2 spec
   because it touches MCP surface, which has its own boundary rule set).
8. **`Compositable` concern naming.** Alternative names considered:
   `HasCompositeCover`, `CompositeCoverHost`. Architect picked
   `Compositable` for symmetry with Rails' standard `Resolvable` /
   `Searchable` naming. Confirm or veto.

---

## References

- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-genres-and-collections-shelves.md`
  (superseded — flat-shelves design).
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  (locked decisions; decision #1 needs the 65 → 70% edit).
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/log.md`
  (2026-05-11 01c entry — what actually shipped under v1).
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01h-collections-cover-composer.md`
  (in flight — defines the `Collections::CoverComposer` service this spec
  consumes).
- `app/services/composite/builder.rb` (existing Bundle-coupled builder,
  refactored to use `Compositable`).
- `app/services/composite/tile_cache.rb` (existing IGDB CDN tile cache;
  reused as-is).
- `app/components/games/cover_component.rb` (`:shelf` variant size bumps
  from 98 × 130 to 105 × 140).
- `app/controllers/composites_controller.rb` (auth-gated `/composites/:filename.jpg`;
  no change — existing regex accepts `collection-<id>`).
- `docs/agents/architect.md` rules A–F (bracketed links, lead paragraphs,
  pane primitives, spec pyramid, yes/no, tenant-free).
- `docs/design.md` (bracketed-link convention, no red outside destructive,
  monospace).
- `CLAUDE.md` hard rules (no JS confirm, bulk-as-foundation, secrets in
  credentials).
