# 02 — Collection cover-art compositions (N-keyed layouts + sequential regen)

> Phase 27 v2 spec. Extends the existing `Collections::CompositeLayout` from a
> 6-tile cap
> (`:empty / :passthrough / :pair / :netflix3 / :quad / :netflix5 / :six_grid`)
> to a 9-tile cap with the explicit per-count layout matrix the user pinned.
> Adds a deterministic, sequential rebuild pipeline keyed on alphabetical
> ordering — predictable build order is load-bearing for both UX (the user can
> SEE which collection is rebuilding next) and for spec assertions
> (deterministic enqueue order is testable).

---

## Goal

A Collection's composite cover renders the visual signature of its members at a
glance, scaled to the member count with a distinct shape for each N ∈ {1, 2, 3,
4, 5, 6, 7, 8, 9+}. When membership changes — game added, removed, resynced,
deleted — the composite regenerates via a Sidekiq job chain that fires in a
predictable alphabetical order so concurrent rebuilds do not stampede.

The cap stays at 9 members contributing to the composite. The 10th+ member
exists in the collection (and shows in the per-collection drill-down page) but
does NOT contribute to the cover. Membership ordering for the cover is
alphabetical by `Game.title` (case-insensitive).

---

## Scope in

- Extend `Collections::CompositeLayout` to cover counts 7, 8, and 9+ with the
  explicit pixel matrices below.
- Update `Collections::CoverComposer::MAX_TILES` from 6 to 9 and update the
  alphabetical ordering query to fetch up to 9 rows.
- Pipeline rules:
  - When a game is added to a collection, enqueue ONE rebuild for that
    collection.
  - When N games are added in a single user action (e.g. bulk "add to
    collection" from a picker), sort the N games by `LOWER(title)` ASC, then
    enqueue N rebuild jobs in that order. Each job is sequential — `job_n+1`
    waits for `job_n` to complete via Sidekiq job chaining (see Behavior below).
  - When a single game in any collection is re-synced (IGDB sync run completes),
    enqueue rebuilds for EVERY collection that game belongs to. Order:
    alphabetical by `Collection.name` ASC, sequential chain.
  - When a game is destroyed (and was a member of one or more collections),
    enqueue rebuilds for every collection it WAS in, alphabetical by
    `Collection.name`. The destruction itself nullifies `collection_id`; the job
    sees the post-destroy membership.

## Scope out

- Changing the layout for N ∈ {1..6} — the existing
  `:empty / :passthrough / :pair / :netflix3 / :quad / :netflix5 / :six_grid`
  shapes stay (the user explicitly pinned 1=full, 2=2-up, 3=Netflix, 4=2x2, 5=1
  big + 2x2 below, 6=3+3 — the existing 6 matches "3+3" semantically, verify in
  implementation; if shape differs, reconcile to match the user's pin in this
  spec).
- Cap above 9. The user explicitly stops at 9.
- Per-page drill-down ("show all members of this collection") is the existing
  collection show page; not part of this spec.

---

## Layout matrix (LOCKED — pixel boxes derived in the layout module)

Output canvas: 98 × 130 (matches `:shelf` cover variant, same as today).

### Canvas dimensions

Composites are RENDERED at 600 × 800 px (the high-res JPEG written to disk) and
DISPLAYED at the shelf tile size 98 × 130 px (the variant defined in
`### Cover Sizes`). The 600×800 render canvas is downscaled by the browser at
display time — generating at high resolution then downscaling produces sharper
edges than rendering at 98×130 directly.

The per-layout pixel decompositions below are expressed at the 98×130 display
size for readability. Multiply by 600/98 ≈ 6.12× to get the render-canvas
dimensions implementations use (e.g., `:nine_grid` cell 33×43 display → 202×264
render; rounding tolerances apply per the "last row/column absorbs remainder"
rule).

The display-size pixel positions remain the canonical SPEC for visual intent;
the render-canvas math is an implementation detail.

| N   | Layout name    | Visual shape                                |
| --- | -------------- | ------------------------------------------- |
| 0   | `:empty`       | placeholder; no composite written           |
| 1   | `:passthrough` | caller renders the lone cover directly      |
| 2   | `:pair`        | 2-up side-by-side (49×130 / 49×130)         |
| 3   | `:netflix3`    | 1 big left + 2 small stacked right          |
| 4   | `:quad`        | 2×2 grid (49×65 × 4)                        |
| 5   | `:netflix5`    | 1 big left + 2×2 grid right                 |
| 6   | `:six_grid`    | 3×2 grid (existing — confirm matches "3+3") |
| 7   | `:netflix7`    | 1 big top + 3 mid row + 3 bottom row        |
| 8   | `:eight_grid`  | 2×4 grid (rows of 4)                        |
| 9+  | `:nine_grid`   | 3×3 grid (32×43 ish per slot)               |

Concrete pixel decomposition for the new layouts (column / row sums MUST equal
canvas dimensions; the existing layouts already pass this guard):

### `:netflix5` — 1 big left + 2 × 2 grid right

Display size 98 × 130 px:

- left: 49 × 130 (full height, left half)
- right column: 49 wide, split into a 2×2 grid of 24/25 × 65 cells (right column
  inner cols `24 / 25` sums to 49; rows `65 / 65` sums to 130)

Render-canvas implementation note: the code at
`app/services/composite/layout/netflix5.rb` divides cleanly at the 600×800
render canvas — left 300×800, right 2×2 grid of uniform 150×400 cells (column
sums 300+150+150 = 600; row sums right 400+400 = 800). At that scale the right
column inner split is even (150/150), so the 24/25 rounding-remainder split
surfaces only at the 98×130 display size.

### `:six_grid` — 3 columns × 2 rows

Display size 98 × 130 px:

- columns: 33 / 33 / 32 (sums to 98)
- rows: 65 / 65 (sums to 130)
- 6 cells, each at its column × row box.

Render-canvas implementation note: the code at
`app/services/composite/layout/six_grid.rb` uses uniform 200×400 cells at the
600×800 render canvas (columns 200/200/200 sums to 600; rows 400/400 sums to
800). Downscales to within ±1px of the display-size decomposition.

### `:netflix7` — 1 big top + 3 mid + 3 bottom

```
canvas 98 × 130
big top      → 98 × 65 (full width, top half)
mid row 3 ×  → 33 × 32 / 33 × 32 / 32 × 32 (rows 0..32, sums to 33+33+32=98)
bot row 3 ×  → 33 × 33 / 33 × 33 / 32 × 33 (rows 33..65, sums to 33+33+32=98)
total height → 65 + 32 + 33 = 130
```

### `:eight_grid` — 2 columns × 4 rows

```
canvas 98 × 130
each cell    → 49 × 32 (rows 0/32/64/96 high; last row absorbs the rounding
               remainder so 32+32+32+34 = 130). Implementation MUST verify
               and document.
```

### `:nine_grid` — 3 × 3

Display size 98 × 130 px:

- columns: 33 / 33 / 32 (sums to 98)
- rows: 43 / 43 / 44 (sums to 130)

Render-canvas implementation note: the code at
`app/services/composite/layout/nine_grid.rb` uses uniform 200×267 cells at the
600×800 render canvas (cropped to 600×800), which downscales to within ±1px of
the display-size decomposition. Both formulations are correct; the display-size
pixels above are the canonical visual intent, the render-canvas approach is an
implementation choice favoring uniform cells.

The implementer MUST verify each layout via the existing
`Collections::CompositeLayout` row/column-sum spec pattern (see Phase 27 §01h
test file). No gaps, no overlaps, no off-canvas tiles.

---

## Files to change

### Layout engine

- `app/services/collections/composite_layout.rb`
  - Extend `LAYOUTS` constant with the three new symbols.
  - Extend `.choose(count)`: 7 → `:netflix7`, 8 → `:eight_grid`, 9.. →
    `:nine_grid` (replaces the existing 6.. → `:six_grid` rule — 6 stays as
    `:six_grid`, 7+ branches into the new cases).
  - Add `netflix7_boxes`, `eight_grid_boxes`, `nine_grid_boxes` private helpers
    that mirror the existing `six_grid_boxes` shape.
  - Extend `.compose(layout, tiles)` switch.
  - Update the module-level docstring matrix.

### Composer

- `app/services/collections/cover_composer.rb`
  - `MAX_TILES = 9` (was 6).
  - `ordered_games(collection)` query already orders by `LOWER(games.title)`
    - limit; bump limit to 9.
  - `safe_fetch_tile`, fingerprint logic, file path — unchanged.

### Pipeline (NEW — sequential regen orchestrator)

- `app/services/collections/composite_rebuild_queue.rb` (NEW)
  - Pure orchestrator. Public API:
    ```
    Collections::CompositeRebuildQueue.new.enqueue_for_collections(collections)
    Collections::CompositeRebuildQueue.new.enqueue_for_game_resync(game)
    Collections::CompositeRebuildQueue.new.enqueue_for_game_destroy(game,
                                                                    was_in:)
    ```
  - Sorts inputs deterministically (alphabetical by `Collection.name` for
    bulk-add and resync flows; alphabetical by `Game.title` for the single-add
    flow that passes games rather than collections).
  - Enqueues a chain of `CollectionCoverRebuildJob` runs — see Sequential chain
    pattern below.

- `app/jobs/collection_cover_rebuild_job.rb`
  - Rewrite per Behavior. Today it ONLY evicts the on-disk file; the v2 pipeline
    must (a) evict OR rebuild eagerly via
    `Collections::CoverComposer.new.call(collection)`, AND (b) enqueue the NEXT
    job in the chain when given a `chain: [...]` arg.
  - Add `lock: :until_executed, on_conflict: :log` so duplicate enqueues
    coalesce.

### Hooks (existing — rewire)

- `app/models/game.rb` —
  - `after_update_commit :evict_collection_composite_on_collection_change` today
    enqueues `CollectionCoverRebuildJob.perform_async(previous_id, current_id)`.
    Replace with a call to
    `Collections::CompositeRebuildQueue.new.enqueue_for_collections(   [previous_collection, current_collection].compact)`.
  - NEW `after_destroy_commit :enqueue_collection_rebuilds_on_destroy` —
    captures `collection_id_was` + `bundles` (if a game is in a bundle that
    surfaces composite-shaped covers, leave that alone — out of scope).
  - NEW `after_save_commit :enqueue_collection_rebuilds_on_sync` — fires when
    `igdb_synced_at` changes (which means a re-sync just landed). Walks every
    collection the game is in, enqueues a sequential rebuild chain via
    `Collections::CompositeRebuildQueue#enqueue_for_game_resync(self)`.

### Controllers / forms (call sites that bulk-add)

- The "add games to collection" flow lives in
  `app/controllers/collections/games_controller.rb` (verify path during
  implementation). After saving the N new memberships, call
  `Collections::CompositeRebuildQueue.new.enqueue_for_collections([   @collection ])`
  — single collection, but the games were added in bulk. The collection itself
  is just one row, so a single rebuild covers it. The "alphabetical by game
  title" ordering rule from the user prompt only matters when N DIFFERENT
  collections each get one game added in a single user action; in the common
  single-collection-bulk-add case the rule collapses to "one job".

---

## Behavior contracts

### Sequential chain pattern

The "wait for prior to complete" requirement means each rebuild job, on success,
enqueues the next job in the chain. The first job in the chain is enqueued by
the orchestrator; subsequent jobs are enqueued from inside the prior job's
`perform`. Argument shape:

```ruby
CollectionCoverRebuildJob.perform_async(collection_id, remaining_chain)
# remaining_chain is an Array<Integer> of collection ids to process AFTER
# this one (in the alphabetical-by-name order computed by the orchestrator).
# When perform finishes successfully, the job pops the first id off
# remaining_chain and enqueues a new run with the tail.
```

Sidekiq does NOT need batches or workflow gems for this. The simple "job
enqueues the next job" pattern is sufficient. The locked Sidekiq options
(`lock: :until_executed`) prevent duplicate enqueues from back-pressure-induced
double-fires.

Failure semantics: if a job in the chain fails after retries, the chain breaks —
remaining collections are not processed. The user-visible effect is that the
next page render falls through to the existing fingerprint-cache miss path and
rebuilds synchronously inline. This is acceptable (the same surface today
already runs synchronously on miss).

### Enqueue orderings (LOCKED)

- **Game added to a single collection**: enqueue ONE rebuild for that
  collection. No chain needed.
- **N games added to one collection in a single user action**: enqueue ONE
  rebuild for that collection (the membership write batched, one rebuild reads
  the final state). No chain needed.
- **Single game re-synced (e.g. `IgdbSyncGame#call` completes)**: walk
  `game.collections` (or the equivalent
  `Collection.joins(:games).where(games: { id: game.id })`). Sort alphabetical
  case-insensitive by `Collection.name`. Enqueue ONE chain — the first job runs
  the first collection in the chain; on completion it enqueues the next.
- **Single game destroyed**: same as resync but the input is `collection_id_was`
  plus the game's pre-destroy bundles (bundles out of scope). Sorted
  alphabetical by `Collection.name`. Enqueue a chain.
- **Multiple games added to multiple collections in one transaction** (rare —
  bulk import case): the orchestrator's `enqueue_for_collections(collections)`
  deduplicates the input set, sorts alphabetical, and enqueues a single chain.

### Composer call contract

`Collections::CoverComposer.new.call(collection) -> Pathname | nil` already
covers (a) cache hit no-op, (b) cache miss rebuild + write, (c) `:empty` /
`:passthrough` short-circuit. v2 keeps the same contract; only the upstream
layout matrix grows.

### Layout pixel-sum invariant

Each layout's `tile_boxes` MUST satisfy: every row's box widths sum to
`OUTPUT_WIDTH`, every column's box heights sum to `OUTPUT_HEIGHT`, no overlaps,
no gaps. The existing layouts pass this; the three new ones MUST be verified via
spec assertions identical to the existing pattern.

---

## Migrations

None. This spec is service + job + hook changes only. The existing
`collections.composite_cover_path` + `collections.composite_cover_checksum`
columns already cover the fingerprint cache contract.

---

## Spec coverage required

Exhaustive — service, job, model, request (where bulk-add is exercised), system
(one scenario). Happy + sad + edge + flaw.

### Layout module spec (`spec/services/collections/composite_layout_spec.rb`)

Extend the existing file:

- `.choose(7)` → `:netflix7`.
- `.choose(8)` → `:eight_grid`.
- `.choose(9)` → `:nine_grid`.
- `.choose(99)` → `:nine_grid` (clamped — the layout caps at 9 contributing
  tiles even though the collection may have more members).
- `tile_boxes(:netflix7)` returns 7 boxes; row widths sum to 98, column heights
  sum to 130; no overlaps.
- Same invariants for `:eight_grid` (8 boxes) and `:nine_grid` (9 boxes).
- `.compose(:netflix7, [nil] * 7)` returns a 98×130 `Vips::Image` filled with
  placeholder blocks at the correct boxes.
- Edge: passing the wrong tile count for a layout raises `ArgumentError`.

### Composer spec (`spec/services/collections/cover_composer_spec.rb`)

Extend the existing file:

- Collection with 7 members → composer writes a JPEG, uses `:netflix7`.
- Collection with 8 members → `:eight_grid`.
- Collection with 9 members → `:nine_grid`.
- Collection with 10+ members → `:nine_grid`, only the alphabetical first 9
  contribute (the 10th is NOT in the fingerprint).
- Fingerprint changes when membership order changes (renaming game 4 from "C" to
  "Z" should NOT change which 9 contribute because alphabetical order didn't
  change at the cap — but renaming game 9 from "I" to "A" WOULD change the
  contributing set).

### Orchestrator spec (`spec/services/collections/composite_rebuild_queue_spec.rb`)

NEW file. Covers:

- `enqueue_for_collections([c_b, c_a, c_c])` enqueues ONE job (the chain head)
  with collection ids in alphabetical order (`c_a, c_b, c_c`).
- `enqueue_for_collections([])` enqueues nothing.
- `enqueue_for_collections([dup, dup, c])` dedupes.
- `enqueue_for_game_resync(game)` enqueues a chain for every collection the game
  is currently in, alphabetical by `Collection.name`.
- `enqueue_for_game_destroy(game, was_in: [c1, c2])` enqueues a chain for the
  passed collections (regardless of post-destroy state).

### Job spec (`spec/jobs/collection_cover_rebuild_job_spec.rb`)

Extend the existing file:

- `perform(collection_id)` (no chain arg) — composes for the single collection,
  no further enqueue. Cache-hit case: no-op.
- `perform(collection_id, [next_id, third_id])` — composes for `collection_id`,
  then enqueues `CollectionCoverRebuildJob.perform_async(next_id, [third_id])`
  once. Verify exactly one new enqueue, not three.
- Failure inside composer raises; chain does NOT advance.
- `lock: :until_executed` declared in sidekiq_options.
- Edge: `collection_id` is for a deleted collection — job no-ops gracefully
  (rescue ActiveRecord::RecordNotFound, log, return).
- Edge: passing nil chain arg behaves like passing `[]`.

### Model spec (`spec/models/game_spec.rb`)

Extend:

- Saving a game with a new `collection_id` enqueues exactly one rebuild via the
  orchestrator (assert
  `Collections::CompositeRebuildQueue#enqueue_for_collections` was called with
  the old + new collection pair).
- Re-syncing a game (`igdb_synced_at` saved-change) triggers
  `enqueue_for_game_resync` exactly once.
- Destroying a game triggers `enqueue_for_game_destroy` with the pre-destroy
  collections list.

### Request spec (`spec/requests/collections/games_spec.rb` or analogue)

- Bulk-add 5 games to a collection in one POST: assert
  `CollectionCoverRebuildJob` is enqueued exactly once (one collection, one job
  — the bulk-add coalesces).

### System spec

- ONE Capybara scenario: create a collection with 7 members → visit `/games` →
  the collection sub-shelf renders the composite cover at the `:shelf` size and
  the file exists at the expected path.

---

## Open questions

1. **Does the 6-tile `:six_grid` layout already render "3+3" (3 columns × 2
   rows)?** The existing spec text says "3 × 2 grid; each row 33+33+32". That
   matches "3+3". Confirm during implementation. If the actual output is "2+2+2"
   (2 cols × 3 rows) instead, reconcile to the user's pinned "3+3" shape and
   update the layout module + spec accordingly.
2. **`enqueue_for_game_destroy` — pass pre-destroy collections from the model
   hook, OR re-query inside the orchestrator?** Architect lean: capture in the
   hook (`collection_id_was`) and pass explicitly. The model can write
   `@_pre_destroy_collection_ids = …` in a `before_destroy` and read it in the
   `after_destroy_commit`.
3. **Sidekiq uniqueness — `lock: :until_executed` requires `sidekiq-unique-jobs`
   (OSS) or Sidekiq Enterprise. Confirm gem is present; if not, the lock is a
   no-op intent declaration (per the existing `ReindexAllJob` pattern). The
   pipeline correctness still holds because the orchestrator deduplicates the
   input set.**
