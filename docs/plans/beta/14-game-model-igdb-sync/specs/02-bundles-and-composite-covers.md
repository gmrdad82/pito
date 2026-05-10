# Phase 14 §2 — Bundles + Composite Covers

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. Builds on
> Phase 14 §1's models. Composite cover building uses libvips (already in the
> stack as the Active Storage variant processor).
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 6 (note 4 §"Bundles" + §"
>   Composite cover art").
> - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md` — source of truth for
>   bundle types, IGDB-source provenance, the five composite layouts, the
>   regen-trigger checksum, and the storage path shape.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — flat
>   storage paths under `composites/` (no `tenant-{id}/` segment).
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — `Pito::AssetsRoot.path("composites", ...)` is the canonical helper for
>   composite paths post-tenant.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
>   — the `Game`, `Genre`, `Platform`, `Company` models and the IGDB
>   `Igdb::Client` this spec consumes.
> - `CLAUDE.md` — secrets in credentials, monospace 13px, bracketed-link, no JS
>   confirms.

## Goal

Add the Bundle model: a curated grouping of Games used as a video- attribution
pivot in analytics ("series", "collection", "genre", "custom"). Each Bundle has
a composite cover image stitched together from its members' IGDB covers,
regenerated whenever membership changes. Cover output lands at
`composites/<bundle_type>-<bundle_id>.jpg` (flat path per ADR 0003), sized
600×800 JPEG (3:4 ratio matching IGDB cover proportions). Five layout templates
per Note 4 (1, 2, 3, 4, 5-9, 10+).

This spec adds the data tier and the cover-builder service. The Steam- shelf
bundles UI ("/bundles") and the `video_game_link` join (which uses Bundles as
one of its link kinds) live in Phase 14 §3.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                 |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Bundle types.** Four: `series`, `collection`, `genre`, `custom`. Stored as an integer enum on `bundles.bundle_type`. Per Note 4.                                                                                                                                                                       |
| Q2  | **IGDB source provenance.** `igdb_source_type` (`franchise` / `collection` / `genre`, nullable for `custom`) + `igdb_source_id` (bigint, nullable). When set, members are seeded from IGDB at create time; the user can then add or remove members (the bundle is NOT a strict mirror). Per Note 4.      |
| Q3  | **Member ordering.** `bundle_members.position` integer column. Default order on insert is `MAX(position) + 1`. User-editable via a future drag-sort UI; this spec ships server-side support but leaves the drag-sort UX to a later polish dispatch (see Open Questions #1).                              |
| Q4  | **Composite image format + size.** 600×800 JPEG (3:4 ratio), quality 80. Source tiles fetched from IGDB's CDN at `t_cover_big` (227×320). Per Note 4.                                                                                                                                                    |
| Q5  | **Storage path.** `<PITO_ASSETS_PATH>/composites/<bundle_type>-<bundle_id>.jpg`. Flat per ADR 0003. Resolved via `Pito::AssetsRoot.path("composites", "<filename>")`.                                                                                                                                    |
| Q6  | **Layouts.** Five templates per Note 4: 1 / 2 / 3 / 4 / 5-9 / 10+. (Six entries; the layout chooser maps member-count to template name.) `single` (1 member, just resize), `pair` (2), `netflix` (3), `quad` (4), `nine_grid` (5-9), `nine_grid_with_overflow` (10+). Layouts hard-coded for v1.         |
| Q7  | **Regen trigger.** `composite_cover_checksum` = SHA-256 of the sorted list of member `cover_image_id` values + the layout name. On every relevant change (member add / remove / reorder, member's underlying `Game.cover_image_id` change), recompute the checksum; if it differs, regenerate the cover. |
| Q8  | **Synchronous vs background.** Background. Sidekiq job (`BundleCoverBuild`) per Open Questions #2. The bundle show page renders the most recent cover; a "regenerating…" indicator surfaces when the job is in flight. The composite-cover-failed fallback shows a flat `[ no cover ]` placeholder.      |
| Q9  | **Tile cache.** IGDB cover image bytes are downloaded once per `cover_image_id` and cached at `<PITO_ASSETS_PATH>/composites/_tiles/<cover_image_id>.jpg` (227×320). Cache hit → skip the IGDB CDN fetch. Cache invalidates on game re-sync if `cover_image_id` changes.                                 |
| Q10 | **libvips.** Already in the stack (`config.active_storage.variant_processor = :vips` per Phase 4). Composite builder uses `ruby-vips` directly, not via Active Storage variants — the output is a free-standing file, not an attached blob.                                                              |
| Q11 | **Bundle ↔ Game cardinality.** Many-to-many. A Game can belong to many Bundles; a Bundle has many Games. Join row: `bundle_members(bundle_id, game_id, position)`.                                                                                                                                       |
| Q12 | **Cascade.** Deleting a Bundle destroys its `bundle_members` join rows but does NOT touch the Games. Deleting a Game destroys its `bundle_members` rows AND triggers a cover regen on every affected Bundle.                                                                                             |
| Q13 | **Boolean boundary discipline.** Per CLAUDE.md, every external boolean is `"yes"` / `"no"` (forms / MCP / CLI). Internal storage Boolean.                                                                                                                                                                |

## Migration posture (LOCKED)

**Additive on the post-Phase-14-§1 schema.** This spec runs after Phase 14 §1's
migration. New tables only; no column drops. Rollback mechanically reversible.

## Files touched

### Schema / migrations

- `db/migrate/<NN>_create_bundles.rb` (new) — `bundles` and `bundle_members`
  tables.
- `db/schema.rb` — auto-regenerated.

### Models

- `app/models/bundle.rb` (new).
- `app/models/bundle_member.rb` (new).
- `app/models/game.rb` (light edit) — `has_many :bundle_members`,
  `has_many :bundles, through: :bundle_members`. Plus an `after_update_commit`
  hook that triggers cover regen on every affected Bundle when `cover_image_id`
  changes.

### Services

- `app/services/composite_cover/builder.rb` (new) — orchestrator. Single public
  method `call(bundle)` produces the 600×800 JPEG and writes it to
  `Pito::AssetsRoot.path("composites", "<bundle_type>-<id>.jpg")`. Internally:
  1. Resolves the layout name from member count.
  2. For each member's `cover_image_id`, fetches the tile (cache hit or IGDB CDN
     download).
  3. Composites the tiles per layout via `ruby-vips`.
  4. Writes the output JPEG.
  5. Stamps `bundle.composite_cover_checksum` and `bundle.composite_cover_path`.
- `app/services/composite_cover/tile_cache.rb` (new) — fetches and caches IGDB
  cover tiles. Path:
  `Pito::AssetsRoot.path("composites", "_tiles", "<cover_image_id>.jpg")`. HTTP
  via `Net::HTTP.get` against
  `https://images.igdb.com/igdb/image/upload/t_cover_big/<id>.jpg`.
  Invalidation: `evict(cover_image_id)` removes the tile (called when a Game's
  `cover_image_id` changes during re-sync).
- `app/services/composite_cover/checksum.rb` (new) — pure module.
  `Composite::Checksum.compute(member_image_ids, layout_name)` → hex SHA-256
  string. Sorts the image IDs lexically before hashing to keep the checksum
  stable across reorderings of the input array. When `position` differs but the
  member set is identical, the checksum is identical (regen not triggered) —
  re-ordering is a UX affordance only, not a cover-content change.
  > **Note:** if a future Open Question resolves to "ordering matters" (i.e.,
  > the layout reflects member position visually beyond just selection), the
  > implementation agent surfaces and the checksum input becomes the ordered
  > list. Today's layouts use top-rated / most-recent ordering for tile
  > placement; position is display-only.
- `app/services/composite_cover/layout/<name>.rb` (six new files — one per
  layout). Each defines a `compose(tiles)` class method that takes the prepared
  array of `ruby-vips` Image objects and returns the composited 600×800 Image.
  Layouts:
  - `Composite::Layout::Single` — 1 member; resize the single tile to 600×800.
  - `Composite::Layout::Pair` — 2 members; side by side, each 300×800.
  - `Composite::Layout::Netflix` — 3 members; left tile 300×800 (large), right
    column two stacked tiles 300×400 each.
  - `Composite::Layout::Quad` — 4 members; 2×2 grid (300×400 each).
  - `Composite::Layout::NineGrid` — 5-9 members; 3×3 grid (200×267 each); empty
    cells filled with a flat dark-grey background tile.
  - `Composite::Layout::NineGridWithOverflow` — 10+ members; same 3×3 layout
    with the bottom-right tile overlaid with a "+N" caption (N = total members -
    8; libvips text overlay).
- `app/services/composite_cover/layout_chooser.rb` (new) — given an integer
  member count, returns the layout class. Boundary cases:
  - 0 members → raises ArgumentError (caller should ensure ≥1).
  - 1 → `Single`
  - 2 → `Pair`
  - 3 → `Netflix`
  - 4 → `Quad`
  - 5..9 → `NineGrid`
  - 10..∞ → `NineGridWithOverflow`

### Jobs

- `app/jobs/bundle_cover_build.rb` (new) — Sidekiq job wrapping
  `Composite::Cover::Builder#call`. Single argument `bundle_id`. On network
  failure (tile fetch) Sidekiq retries with backoff. On bundle deleted
  mid-build, no-op gracefully.
- `app/jobs/bundle_cover_invalidate.rb` (new) — fires when a member Game's
  `cover_image_id` changes. Looks up every affected Bundle, evicts the old tile
  from the cache, enqueues `BundleCoverBuild` per Bundle.

### Controllers

- `app/controllers/bundles_controller.rb` (new) — full RESTful surface: `index`,
  `show`, `new`, `create`, `edit`, `update`, `destroy`. Plus member actions:
  - `add_member` — `POST /bundles/:id/members` with `params[:game_id]`. Adds the
    game; recomputes checksum; if changed, enqueues cover rebuild.
  - `remove_member` — `DELETE /bundles/:id/members/:game_id`. Same flow.
  - `seed_from_igdb` — `POST /bundles/:id/seed_from_igdb`. Runs only when
    `igdb_source_type` + `igdb_source_id` are set; pulls the IGDB-side members
    and adds any not already present (additive, not destructive).
- The action-confirmation framework (`/deletions/bundle/:ids`) wires `bundle`
  into `Confirmable::TYPES` so destroy goes through the shared screen.

### Routes

- `config/routes.rb` (light edit) —
  `resources :bundles do member do post :seed_from_igdb; end; resources :members, only: %i[create destroy], controller: "bundle_members"; end`.
  Plus `Confirmable` registration for the `bundle` type (the implementation
  agent edits `app/lib/confirmable.rb` or its equivalent — verify the file path
  during the sweep).
- `app/controllers/bundle_members_controller.rb` (new) — handles the nested
  `add_member` / `remove_member` actions if the implementation agent prefers a
  separate controller; otherwise the actions live on `BundlesController`.
  Architect's preference: separate controller, so the bundle-detail page's
  add-member form and the table's inline-remove buttons hit a focused surface.

### Views

- `app/views/bundles/index.html.erb` — Steam-shelf-style bundle row. (Most of
  the index UX lands in Phase 14 §3 — the file is created here as a thin
  placeholder.)
- `app/views/bundles/show.html.erb` (new) — bundle detail page. Composite cover
  at top, member list with [ remove ] inline, [ add member ] form.
- `app/views/bundles/new.html.erb` (new) — create form. Picks `bundle_type`,
  `name`, optional `igdb_source_type` / `igdb_source_id` for IGDB-seeded
  bundles.
- `app/views/bundles/edit.html.erb` (new) — edit form. Editable: `name`. NOT
  editable: `bundle_type`, `igdb_source_type`, `igdb_source_id` (those are
  immutable post-create — see Open Questions #3).
- `app/views/bundles/_form.html.erb` (new) — shared form partial.
- `app/views/bundle_members/_member_row.html.erb` (new) — single-row partial for
  the member table.
- `app/views/shared/_composite_cover.html.erb` (new) — small partial rendering
  the composite cover image at one of three sizes (full 600×800, card 300×400,
  thumb 150×200). Falls back to the `[ no cover ]` placeholder when
  `composite_cover_path` is blank.

### Stimulus controllers

- `app/javascript/controllers/bundle_member_picker_controller.js` (new) —
  Game-search type-ahead for the [ add member ] form. Reuses the IGDB-search
  pattern OR pulls from local `Game.all` (architect's call — see Open Questions
  #4).

### Confirmable / action-screen wiring

- `app/lib/confirmable.rb` (or wherever `Confirmable::TYPES` lives — the
  implementation agent enumerates) — add `"bundle"` to the whitelist; declare
  `cancel_path`, `model_for`, `scope_for`, `label_for` for the new type. The
  destruction route (`/deletions/bundle/:ids`) automatically picks it up.

### Tests

See §"Test sweep". New / edited spec files:

- `spec/models/bundle_spec.rb` (new)
- `spec/models/bundle_member_spec.rb` (new)
- `spec/models/game_spec.rb` (light edit — add `has_many :bundles` associations
  and the `after_update_commit` cover-invalidate hook)
- `spec/factories/bundles.rb` (new)
- `spec/factories/bundle_members.rb` (new)
- `spec/services/composite_cover/builder_spec.rb` (new — exercises the full
  pipeline with stubbed IGDB CDN and a real libvips composite)
- `spec/services/composite_cover/tile_cache_spec.rb` (new)
- `spec/services/composite_cover/checksum_spec.rb` (new)
- `spec/services/composite_cover/layout_chooser_spec.rb` (new)
- `spec/services/composite_cover/layout/single_spec.rb` (new)
- `spec/services/composite_cover/layout/pair_spec.rb` (new)
- `spec/services/composite_cover/layout/netflix_spec.rb` (new)
- `spec/services/composite_cover/layout/quad_spec.rb` (new)
- `spec/services/composite_cover/layout/nine_grid_spec.rb` (new)
- `spec/services/composite_cover/layout/nine_grid_with_overflow_spec.rb` (new)
- `spec/jobs/bundle_cover_build_spec.rb` (new)
- `spec/jobs/bundle_cover_invalidate_spec.rb` (new)
- `spec/requests/bundles_spec.rb` (new)
- `spec/requests/bundle_members_spec.rb` (new)
- `spec/system/bundle_show_spec.rb` (new — Capybara smoke of the member add /
  remove flow)
- `spec/fixtures/files/cover_tile.jpg` (new — a 227×320 JPEG seed image used to
  mock IGDB CDN responses for libvips integration)

### Out of scope (this spec)

- Steam-shelf bundle index UX — Phase 14 §3.
- `video_game_link` join + analytics attribution — Phase 14 §3.
- MCP tool surface (`bundle_*`, `bundle_member_*`) — Phase 14 §3.
- CLI parity — work unit 10.
- Per-bundle layout override (`bundles.layout_override`) — future hook per
  Note 4.
- Drag-sort UI for member ordering — see Open Questions #1.

## Schema

### `bundles` table (new)

| Column                     | Type       | Null | Default | Index                  | Notes                                                                                               |
| -------------------------- | ---------- | ---- | ------- | ---------------------- | --------------------------------------------------------------------------------------------------- |
| `id`                       | `bigint`   | NOT  | (pk)    | —                      | Local PK.                                                                                           |
| `bundle_type`              | `integer`  | NOT  | 0       | btree                  | Enum: `series: 0`, `collection: 1`, `genre: 2`, `custom: 3`.                                        |
| `name`                     | `string`   | NOT  | —       | —                      | Display name.                                                                                       |
| `igdb_source_type`         | `integer`  | NULL | —       | —                      | Enum: `franchise: 0`, `collection: 1`, `genre: 2`. NULL for `custom` bundles.                       |
| `igdb_source_id`           | `bigint`   | NULL | —       | btree (where not null) | The IGDB-side ID. Composite-unique with `igdb_source_type` (one local bundle per IGDB-source pair). |
| `composite_cover_path`     | `string`   | NULL | —       | —                      | Relative to `PITO_ASSETS_PATH`. Always under `composites/`. NULL until first build.                 |
| `composite_cover_checksum` | `string`   | NULL | —       | —                      | SHA-256 hex. NULL until first build.                                                                |
| `created_at`               | `datetime` | NOT  | —       | —                      |                                                                                                     |
| `updated_at`               | `datetime` | NOT  | —       | —                      |                                                                                                     |

Composite unique index: `(igdb_source_type, igdb_source_id)` where both are
non-null. Allows multiple `(NULL, NULL)` rows for `custom` bundles.

### `bundle_members` table (new)

| Column       | Type       | Null | Default | Index                         |
| ------------ | ---------- | ---- | ------- | ----------------------------- |
| `id`         | `bigint`   | NOT  | (pk)    | —                             |
| `bundle_id`  | `bigint`   | NOT  | —       | btree, FK → bundles (cascade) |
| `game_id`    | `bigint`   | NOT  | —       | btree, FK → games (cascade)   |
| `position`   | `integer`  | NOT  | 0       | —                             |
| `created_at` | `datetime` | NOT  | —       | —                             |
| `updated_at` | `datetime` | NOT  | —       | —                             |

Composite unique on `(bundle_id, game_id)`. Composite btree on
`(bundle_id, position)` for ordered fetches.

### Foreign keys

- `bundle_members.bundle_id → bundles.id` (`ON DELETE CASCADE`).
- `bundle_members.game_id → games.id` (`ON DELETE CASCADE`).

## Models

### `Bundle`

```ruby
class Bundle < ApplicationRecord
  enum bundle_type: { series: 0, collection: 1, genre: 2, custom: 3 },
       prefix: :type
  enum igdb_source_type: { franchise: 0, source_collection: 1, source_genre: 2 },
       prefix: :igdb_source

  has_many :bundle_members, -> { order(:position) }, dependent: :destroy
  has_many :games, through: :bundle_members

  validates :name, presence: true, length: { maximum: 255 }
  validates :bundle_type, presence: true
  validates :igdb_source_id, uniqueness: { scope: :igdb_source_type, allow_nil: true }
  validate :igdb_source_pair_consistency

  after_save :enqueue_cover_build_if_changed

  def composite_cover_url
    return nil if composite_cover_path.blank?
    # Built relative to a future /composites/<filename> route or via a
    # signed URL helper. Implementation agent picks; recommendation:
    # serve via a `/composites/:filename.jpg` route on the Rails app
    # with sendfile / X-Accel-Redirect (single install, no CDN needed).
    "/composites/#{File.basename(composite_cover_path)}"
  end

  def needs_cover_rebuild?
    expected = Composite::Checksum.compute(
      bundle_members.includes(:game).map { |bm| bm.game.cover_image_id }.compact,
      Composite::LayoutChooser.choose(bundle_members.size).layout_name
    )
    composite_cover_checksum != expected
  end

  private

  def igdb_source_pair_consistency
    if type_custom? && (igdb_source_type.present? || igdb_source_id.present?)
      errors.add(:igdb_source_type, "must be blank for custom bundles")
    end
    if !type_custom? && igdb_source_type.blank? != igdb_source_id.blank?
      errors.add(:igdb_source_id, "must be set when igdb_source_type is set")
    end
  end

  def enqueue_cover_build_if_changed
    BundleCoverBuild.perform_async(id) if needs_cover_rebuild?
  end
end
```

The `igdb_source_type` enum integer values are reused from Note 4's listing. The
Rails enum prefix is `igdb_source` to avoid collision with the IGDB resource
names (`franchise` / `collection` / `genre` — the latter would collide with
`Game#genres` if unprefixed). The implementation agent verifies in the test
suite that `Bundle.igdb_source_franchise` and `bundle.igdb_source_franchise?`
work.

### `BundleMember`

```ruby
class BundleMember < ApplicationRecord
  belongs_to :bundle
  belongs_to :game

  validates :game_id, uniqueness: { scope: :bundle_id }
  validates :position, numericality: { only_integer: true,
                                       greater_than_or_equal_to: 0 }

  before_validation :assign_position, on: :create

  after_create_commit :enqueue_cover_rebuild
  after_destroy_commit :enqueue_cover_rebuild

  private

  def assign_position
    return if position.present? && position != 0
    self.position = (bundle.bundle_members.maximum(:position) || -1) + 1
  end

  def enqueue_cover_rebuild
    BundleCoverBuild.perform_async(bundle_id)
  end
end
```

### `Game` (light edit)

```ruby
# Phase 14 §2 additions — added to the Phase 14 §1 model body.
has_many :bundle_members, dependent: :destroy
has_many :bundles, through: :bundle_members

after_update_commit :invalidate_bundle_covers_if_image_changed

private

def invalidate_bundle_covers_if_image_changed
  return unless saved_change_to_cover_image_id?
  BundleCoverInvalidate.perform_async(id)
end
```

## Service: composite cover builder

### `Composite::Cover::Builder`

```ruby
module Composite
  module Cover
    class Builder
      OUTPUT_WIDTH  = 600
      OUTPUT_HEIGHT = 800
      JPEG_QUALITY  = 80

      def initialize(tile_cache: TileCache.new)
        @tile_cache = tile_cache
      end

      def call(bundle)
        members = bundle.bundle_members.includes(:game).order(:position)
        cover_image_ids = members.map { |bm| bm.game.cover_image_id }.compact

        if cover_image_ids.empty?
          bundle.update!(composite_cover_path: nil, composite_cover_checksum: nil)
          return nil
        end

        layout = LayoutChooser.choose(cover_image_ids.size)
        tiles = cover_image_ids.map { |cid| @tile_cache.fetch(cid) }
        composite = layout.compose(tiles, total_member_count: members.size)

        path = Pito::AssetsRoot.path("composites",
                                     "#{bundle.bundle_type}-#{bundle.id}.jpg")
        FileUtils.mkdir_p(path.dirname)
        composite.jpegsave(path.to_s, Q: JPEG_QUALITY, strip: true)

        relative = path.relative_path_from(Pito::AssetsRoot.root).to_s
        new_checksum = Checksum.compute(cover_image_ids, layout.layout_name)
        bundle.update!(composite_cover_path: relative,
                       composite_cover_checksum: new_checksum)
        path
      end
    end
  end
end
```

### `Composite::Cover::TileCache`

```ruby
module Composite
  module Cover
    class TileCache
      TILE_SIZE = "t_cover_big" # 227×320 per IGDB CDN
      BASE_URL  = "https://images.igdb.com/igdb/image/upload"

      def fetch(cover_image_id)
        path = Pito::AssetsRoot.path("composites", "_tiles",
                                     "#{cover_image_id}.jpg")
        return Vips::Image.new_from_file(path.to_s) if path.exist?

        FileUtils.mkdir_p(path.dirname)
        url = "#{BASE_URL}/#{TILE_SIZE}/#{cover_image_id}.jpg"
        bytes = Net::HTTP.get(URI(url))
        File.binwrite(path, bytes)
        Vips::Image.new_from_file(path.to_s)
      end

      def evict(cover_image_id)
        path = Pito::AssetsRoot.path("composites", "_tiles",
                                     "#{cover_image_id}.jpg")
        File.delete(path) if path.exist?
      end
    end
  end
end
```

Spec-mockable via dependency injection on `Builder.new(tile_cache: …)`.

### `Composite::Cover::Layout::*`

Each layout class:

```ruby
module Composite::Cover::Layout
  class Pair
    def self.layout_name; "pair"; end
    def self.compose(tiles, total_member_count: nil)
      raise ArgumentError, "expected 2 tiles" unless tiles.size == 2
      left  = tiles[0].thumbnail_image(300, height: 800, crop: :centre)
      right = tiles[1].thumbnail_image(300, height: 800, crop: :centre)
      left.join(right, :horizontal)
    end
  end
end
```

(Full implementations per Note 4's layout descriptions. The
`NineGridWithOverflow` layout uses `Vips::Image.text(...)` to overlay the "+N"
caption on the bottom-right tile.)

## Job: `BundleCoverBuild`

```ruby
class BundleCoverBuild
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return if bundle.nil? # bundle deleted mid-build, no-op

    Composite::Cover::Builder.new.call(bundle)
  end
end
```

## Job: `BundleCoverInvalidate`

```ruby
class BundleCoverInvalidate
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return if game.nil?

    # Evict the old tile from the cache (it's now stale).
    if game.cover_image_id_previously_was.present?
      Composite::Cover::TileCache.new.evict(game.cover_image_id_previously_was)
    end

    # Enqueue rebuild for every bundle this game belongs to.
    game.bundles.find_each { |b| BundleCoverBuild.perform_async(b.id) }
  end
end
```

(Note: `cover_image_id_previously_was` is provided by
`saved_change_to_cover_image_id`'s before-value when called inside the
`after_update_commit` callback. The job enqueues from the callback so the data
is still in `saved_changes`. If the implementation agent prefers an explicit
argument shape — passing the old `cover_image_id` directly into the job — that's
acceptable; spec encodes the chosen shape.)

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows `bundles` table with all columns from §"bundles
      table" present.
- [ ] `db/schema.rb` shows `bundle_members` table with all columns from
      §"bundle_members table" present.
- [ ] FK `bundle_members.bundle_id → bundles.id` ON DELETE CASCADE.
- [ ] FK `bundle_members.game_id → games.id` ON DELETE CASCADE.
- [ ] Composite unique index on `bundles.(igdb_source_type,     igdb_source_id)`
      where both are non-null.
- [ ] Composite unique index on `bundle_members.(bundle_id,     game_id)`.
- [ ] Migration runs cleanly; rollback mechanically reversible.

### Models

- [ ] `Bundle.bundle_types` returns the four-symbol enum hash.
- [ ] `Bundle.igdb_source_types` returns the three-symbol enum hash.
- [ ] `Bundle#type_custom?`, `#type_series?`, etc. all work.
- [ ] `Bundle` validates `name` presence + ≤ 255.
- [ ] `Bundle` validates `igdb_source_type`/`igdb_source_id` consistency.
- [ ] `Bundle.create!(bundle_type: :custom, name: "Soulslikes")` saves.
- [ ] `Bundle.create!(bundle_type: :series, igdb_source_type: :franchise, igdb_source_id: 1, name: "Zelda")`
      saves.
- [ ] Composite unique constraint enforced (second create with same pair raises
      `ActiveRecord::RecordNotUnique`).
- [ ] `BundleMember.position` auto-assigned on create as `MAX(position) + 1`.
- [ ] `Game#bundles` returns through-join associations.
- [ ] `Game` after_update_commit hook fires when `cover_image_id` changes; does
      NOT fire when other columns change.

### Services

- [ ] `Composite::Cover::TileCache#fetch(id)` returns a `Vips::Image`.
- [ ] First fetch hits IGDB CDN; subsequent fetches read from
      `<assets>/composites/_tiles/<id>.jpg`.
- [ ] `evict(id)` removes the tile.
- [ ] `Composite::Cover::Checksum.compute(image_ids, layout)` returns a hex
      SHA-256 string deterministically.
- [ ] `LayoutChooser.choose(N)` returns the right class per the
      `1/2/3/4/5-9/10+` table.
- [ ] `LayoutChooser.choose(0)` raises ArgumentError.
- [ ] Each layout class produces a 600×800 image when given the correct number
      of input tiles.
- [ ] `Composite::Cover::Builder#call(bundle)` writes a valid 600×800 JPEG to
      `<assets>/composites/<type>-<id>.jpg`.
- [ ] After `call`, `bundle.composite_cover_path` and
      `bundle.composite_cover_checksum` are stamped.
- [ ] On a member set with NO `cover_image_id` values (all members lack cover
      art), `call` clears the path + checksum and writes no file.

### Jobs

- [ ] `BundleCoverBuild` enqueues on `:default`.
- [ ] `BundleCoverBuild#perform(missing_id)` no-ops gracefully.
- [ ] `BundleCoverInvalidate#perform(game_id)` evicts the old tile and enqueues
      rebuild for every bundle the game belongs to.

### Controllers

- [ ] `GET /bundles` renders 200.
- [ ] `GET /bundles/:id` renders the show page with the composite cover (or
      fallback).
- [ ] `POST /bundles` with valid params creates a bundle.
- [ ] `POST /bundles/:id/members` with valid game_id adds the member, enqueues
      `BundleCoverBuild`.
- [ ] `DELETE /bundles/:id/members/:game_id` removes the member, enqueues
      `BundleCoverBuild`.
- [ ] `POST /bundles/:id/seed_from_igdb` (only for IGDB-source bundles) seeds
      members from IGDB.
- [ ] `/deletions/bundle/:ids` renders the action-screen.
- [ ] `POST /deletions/bundle/:ids` destroys; cascades to bundle_members.

### Storage

- [ ] After cover build, the file at
      `<PITO_ASSETS_PATH>/composites/<type>-<id>.jpg` exists and is a valid
      JPEG.
- [ ] After bundle destroy, the cover file is removed (cleanup hook on
      `before_destroy` — implementation agent decides whether to keep or sweep;
      recommendation: sweep, plus a follow-up orphan-cleanup rake task).
- [ ] No file path contains `tenant-` (verified post-tenant-drop).

### Tests

- [ ] `bundle exec rspec spec/models/bundle_spec.rb` green.
- [ ] `bundle exec rspec spec/models/bundle_member_spec.rb` green.
- [ ] `bundle exec rspec spec/services/composite_cover/` green.
- [ ] `bundle exec rspec spec/jobs/bundle_cover_*` green.
- [ ] `bundle exec rspec spec/requests/bundles_spec.rb` green.
- [ ] `bundle exec rspec spec/requests/bundle_members_spec.rb` green.
- [ ] `bundle exec rspec spec/system/bundle_show_spec.rb` green.

## Test sweep (exhaustive)

### `Bundle` model unit specs

**Associations:**

- `has_many :bundle_members, dependent: :destroy`
- `has_many :games, through: :bundle_members`
- Member ordering: `bundle.bundle_members` returns rows ordered by `position`

**Enums:**

- `Bundle.bundle_types` matches the documented hash
- `Bundle.igdb_source_types` matches
- Each predicate works: `type_series?`, `type_collection?`, `type_genre?`,
  `type_custom?`, `igdb_source_franchise?`, `igdb_source_source_collection?`
  (yes the prefix doubles — see Open Questions #5), `igdb_source_source_genre?`

**Validations:**

- `name`: presence + ≤ 255
- `bundle_type`: presence (default :series — 0)
- `igdb_source_type` + `igdb_source_id` consistency:
  - `custom` + both nil: valid
  - `custom` + igdb_source_type set: invalid
  - `custom` + igdb_source_id set: invalid
  - non-custom + both set: valid
  - non-custom + only one set: invalid
  - non-custom + both nil: valid (allows starting empty, seeding later — see
    Open Questions #6)
- `igdb_source_id` uniqueness scoped to `igdb_source_type`:
  - Two `series` bundles with `igdb_source_type: :franchise`,
    `igdb_source_id: 1`: second invalid
  - Two `custom` bundles with both nil: both valid
  - Two `series` bundles with `franchise: 1` and `franchise: 2`: both valid

**Scopes:**

- `Bundle.where(bundle_type: :series)` filters correctly

**Methods:**

- `composite_cover_url` returns nil when path blank
- `composite_cover_url` returns the well-formed `/composites/...` URL when path
  present
- `needs_cover_rebuild?` true on a fresh bundle (no checksum yet)
- `needs_cover_rebuild?` false right after a successful build
- `needs_cover_rebuild?` true after a member's `cover_image_id` changes
- `needs_cover_rebuild?` true after a member is added
- `needs_cover_rebuild?` true after a member is removed

**Callbacks:**

- `after_save :enqueue_cover_build_if_changed` enqueues `BundleCoverBuild` when
  checksum differs
- Does NOT enqueue when only `name` changes (checksum unchanged)

### `BundleMember` model unit specs

- `belongs_to :bundle`
- `belongs_to :game`
- `(bundle_id, game_id)` uniqueness
- `position` numericality, integer, ≥ 0
- `before_validation :assign_position` sets position to MAX+1 on create;
  preserves explicit position values
- `after_create_commit` enqueues `BundleCoverBuild`
- `after_destroy_commit` enqueues `BundleCoverBuild`
- Cascade-on-delete from Bundle removes BundleMember rows but preserves Games
- Cascade-on-delete from Game removes BundleMember rows but preserves Bundle
  (the Bundle's checksum changes; rebuild fires)

### `Composite::Cover::TileCache` specs

- First `fetch(id)` GET against
  `images.igdb.com/igdb/image/upload/t_cover_big/<id>.jpg`
- Second `fetch(id)` reads from `<assets>/composites/_tiles/<id>.jpg` with no
  HTTP call (mock `Net::HTTP.get` returns instrumented)
- `evict(id)` removes the tile file
- `evict(missing_id)` no-ops gracefully
- HTTP timeout propagates as Net::OpenTimeout
- Non-200 response (404 from CDN) raises `Composite::Cover::TileFetchError`
- The file written is a valid 227×320 JPEG (verify via `Vips::Image#width`)

### `Composite::Cover::Checksum` specs

- `compute(["a", "b"], "pair")` returns a hex string of length 64
- `compute(["b", "a"], "pair") == compute(["a", "b"], "pair")` (sort invariance)
- `compute([], "single")` returns a deterministic hash for empty input
- `compute(["a"], "single") != compute(["a"], "pair")` (layout differs →
  checksum differs)
- `compute(["a", "b"], "pair") != compute(["a", "c"], "pair")`
- nil entries in the array filtered out before hashing

### `Composite::Cover::LayoutChooser` specs

- `choose(0)` raises ArgumentError
- `choose(1)` returns `Single`
- `choose(2)` returns `Pair`
- `choose(3)` returns `Netflix`
- `choose(4)` returns `Quad`
- `choose(5)` returns `NineGrid`
- `choose(9)` returns `NineGrid`
- `choose(10)` returns `NineGridWithOverflow`
- `choose(100)` returns `NineGridWithOverflow`
- `choose(-1)` raises ArgumentError
- `choose("3")` raises ArgumentError (integer required)

### Layout specs (one per layout class)

For each `Composite::Cover::Layout::*`:

- Output dimensions are exactly 600×800
- Output is a `Vips::Image`
- Wrong tile count raises ArgumentError (e.g., `Pair.compose(tiles_3)`)
- Tiles smaller than the expected size are upscaled to fill (libvips
  `thumbnail_image` with `crop: :centre`)
- Tiles larger than the expected size are cropped centrally
- (NineGridWithOverflow only) The "+N" overlay text appears on the bottom-right
  tile; verify by extracting the overlay region and asserting non-empty pixels
  (smoke test, not pixel-perfect)

### `Composite::Cover::Builder` specs

(Use `spec/fixtures/files/cover_tile.jpg` as the seed tile, mock
`TileCache#fetch` to return `Vips::Image.new_from_file(fixture)`.)

- 1-member bundle: file written; dimensions 600×800
- 2-member bundle: file written; dimensions 600×800
- 3-member: same
- 4-member: same
- 9-member: same; uses `NineGrid` layout
- 10-member: same; uses `NineGridWithOverflow` layout; overflow text shows "+2"
  (i.e., 10 - 8)
- 0-member bundle: file NOT written; `composite_cover_path` and
  `composite_cover_checksum` cleared; returns nil
- Members with no `cover_image_id` (game.cover_image_id is nil) are filtered
  out; if the remaining set is non-empty, builds with the filtered set
- Filename pattern: `<bundle_type>-<bundle_id>.jpg` exactly
- File is written under `Pito::AssetsRoot.path("composites", ...)` (NOT under
  any tenant prefix)
- After build, `bundle.composite_cover_checksum` matches
  `Checksum.compute(member_image_ids, layout_name)`
- Re-running `call` on a bundle with unchanged members produces the same
  checksum and overwrites the file with identical bytes (test by comparing pre-
  and post- file checksums of the JPEG)

### `BundleCoverBuild` job specs

- `perform(id)` calls `Composite::Cover::Builder#call`
- `perform(missing_id)` no-ops
- Enqueued on `:default`
- Default retry count: 5
- `Composite::Cover::TileFetchError` is retried (Sidekiq backoff)

### `BundleCoverInvalidate` job specs

- `perform(game_id)` evicts the previous `cover_image_id` from cache
- Enqueues `BundleCoverBuild` once per bundle the game belongs to
- `perform(missing_id)` no-ops
- A game in 0 bundles: no enqueues

### `BundlesController` request specs

**`GET /bundles` (happy):**

- 200, renders index view (placeholder layout for §2; full Steam- shelf in §3)

**`GET /bundles/:id`:**

- 200, renders show view
- Composite cover image rendered when path present
- `[ no cover ]` placeholder when path blank
- Member list rendered with each game's title + cover thumbnail
- 404 when bundle does not exist

**`POST /bundles` (custom):**

- `bundle_type=custom, name="Soulslikes"` → 302 to show; bundle persisted
- Custom bundle with `igdb_source_type` set: 422 (consistency validation)

**`POST /bundles` (IGDB-seeded):**

- `bundle_type=series, igdb_source_type=franchise, igdb_source_id=1, name="Zelda"`
  → 302; bundle persisted; `seed_from_igdb` NOT auto-called
- Same shape but missing `igdb_source_id`: 422

**`PATCH /bundles/:id`:**

- Edit `name` only: 302; persisted
- Smuggle `bundle_type` change: silently dropped (form does not surface the
  field; verify the controller `permit` excludes it)
- Smuggle `igdb_source_type` change: silently dropped

**`DELETE /bundles/:id`:**

- Goes through `/deletions/bundle/:ids` action screen first (no immediate
  destroy on direct DELETE)
- After confirm: bundle destroyed; bundle_members cascade-destroyed; composite
  cover file removed from disk

**`POST /bundles/:id/members`:**

- `params[:game_id]` valid: 302 (or Turbo Stream); BundleMember created;
  `BundleCoverBuild` enqueued
- Duplicate member: 422 (uniqueness violation surfaces as a flash alert)
- Game does not exist: 404

**`DELETE /bundles/:id/members/:game_id`:**

- Member exists: 302; row destroyed; rebuild enqueued
- Member does not exist: 404

**`POST /bundles/:id/seed_from_igdb`:**

- IGDB-source bundle, IGDB returns 5 games: 5 BundleMember rows created (only
  those NOT already present); rebuild enqueued
- Custom bundle: 422 with flash "no IGDB source"
- IGDB API failure: 503 with flash; bundle unchanged

### Edge cases (full sweep)

- Bundle with 1 member, member's cover changes: rebuild enqueued
- Bundle with 9 members, add one (10th): rebuild enqueued; layout changes from
  `NineGrid` to `NineGridWithOverflow`
- Bundle with 10 members, remove one (back to 9): rebuild enqueued; layout
  changes back
- Two bundles share a Game; the Game's cover_image_id changes: both bundles'
  rebuilds enqueued
- A Game is destroyed: all bundles containing it have their bundle_member row
  removed AND their cover rebuilt
- A Bundle's name changes: cover NOT rebuilt
- A Bundle's `bundle_type` changes (if mutation were allowed — currently not):
  would change the filename pattern — but mutation is forbidden by the form
  (Open Questions #3); spec asserts the controller does not permit `bundle_type`
  on update
- IGDB CDN returns 404 for a `cover_image_id`: tile fetch raises
  `TileFetchError`; the build job retries (Sidekiq); on persistent failure, the
  bundle's cover stays at the previous version (or blank, on first build) and
  `last_sync_error`-style reporting surfaces (architect calls out that bundles
  do NOT have a `last_sync_error` column today; the build job logs the error to
  Sidekiq retry buffer; see Open Questions #7)
- Bundle with 100 members: `NineGridWithOverflow` builds with "+92" caption
- Filename collision: a custom bundle with id=42 and a series bundle with id=42
  produce different filenames (`custom-42.jpg` vs `series-42.jpg`); spec asserts
  no overwrite
- Smuggle attempt: PATCH `/bundles/:id` with
  `composite_cover_path: "../../etc/passwd"`: silently dropped by strong params
- Race condition: two simultaneous member-add operations both fire
  `BundleCoverBuild`. Sidekiq deduplication is OUT of scope for v1; the second
  build overwrites the first's output. Both produce valid JPEGs (idempotent).
  Spec asserts no exception under parallel run.
- Disk full during write: `jpegsave` raises; spec asserts the job re-raises
  (Sidekiq retry); no partial file left behind (libvips writes atomically to a
  temp file)

## Manual playbook (post-implementation)

1. **Migrate.**
   ```bash
   bin/rails db:migrate
   ```
2. **Add a few games via the Phase 14 §1 IGDB flow.** At least 4 games for the
   layout test bench.
3. **Visit `/bundles`.** Confirm empty state.
4. **Create a custom bundle.** Click `[ + ]` (or whatever the bundle- create
   entry copy ends up being). Enter name "soulslikes", `bundle_type: custom`.
   Submit.
5. **Add 3 games as members.** On the bundle show page, type-ahead each game
   name; click `[ add ]`. Confirm BundleMember rows appear. Confirm cover
   regenerates within ~3-5 seconds (Sidekiq).
6. **Verify cover on disk.**
   ```bash
   ls $PITO_ASSETS_PATH/composites/
   ```
   Confirm one `custom-<id>.jpg` file exists. Open in an image viewer; confirm
   600×800 with the Netflix layout (3 members).
7. **Add a 4th game.** Confirm the cover regenerates with the Quad layout.
8. **Remove the first game.** Confirm the cover regenerates back to Netflix.
9. **Test the IGDB-seeded path.** Create a `series` bundle pointing at the Zelda
   franchise (`igdb_source_id` from a prior add). Click `[ seed from igdb ]`.
   Confirm members populate.
10. **Test cover invalidation on game re-sync.** Click `[ resync ]` on a game in
    a bundle. If IGDB has updated the cover, confirm the bundle's cover
    regenerates. Otherwise, confirm no rebuild fires (checksum unchanged).
11. **Delete a bundle.** Click `[ delete ]`. Confirm action-screen fires.
    Submit. Confirm bundle + bundle_members gone; composite cover file removed
    from disk.
12. **Run the suite.**
    ```bash
    bundle exec rspec
    ```

## Cross-stack scope

| Surface         | Status                                             |
| --------------- | -------------------------------------------------- |
| Rails web app   | **In scope.** Primary lane.                        |
| MCP rack app    | **Skipped here.** `bundle_*` MCP tools land in §3. |
| Doorkeeper      | **Untouched.**                                     |
| `pito` CLI      | **Skipped.** Work unit 10.                         |
| Astro / website | **N/A.**                                           |

## Copy questions to escalate

1. **Page heading on `/bundles`.** "bundles" vs "shelves" vs "groups".
2. **Empty-state copy on `/bundles` (no rows).** "no bundles yet." vs "no
   bundles yet. [ + bundle ] to create one."
3. **`[ + bundle ]` create button label.** vs `[ new bundle ]` vs
   `[ create bundle ]`.
4. **Bundle-type selector copy.** "type" vs "kind". Options: `series`,
   `collection`, `genre`, `custom`. Confirm the four labels are correct case
   (lowercase per design).
5. **IGDB-seed copy on the new-bundle form.** "seed from igdb" vs "import from
   igdb" vs "pull from igdb".
6. **`[ seed from igdb ]` button on the show page.** Confirm or align with the
   create-form copy.
7. **`[ no cover ]` placeholder on the show page.** Aligns with §1's game-cover
   placeholder; confirm same string.
8. **Composite-cover-failed fallback inline copy.** "couldn't build cover; will
   retry on next change." vs "no cover yet."
9. **"+N" overlay caption format.** "+2" (just the number) vs "+2 more" vs "and
   2 more". Note 4 says "+N"; confirm short.
10. **Member-add type-ahead empty state.** "no games match" vs "search your
    library".
11. **Member-remove inline button.** `[ x ]` vs `[ remove ]` vs `[ - ]`.
12. **Bundle action-screen copy** (delete confirmation). Reuse existing
    `Confirmable` shared copy or customize per type? Recommendation: shared.

## Open questions (architect cannot decide)

1. **Drag-sort UI for member ordering.** Recommendation: defer to a polish
   dispatch. Initial v1 ordering: insertion order (`MAX(position) + 1`). The
   user can still re-order programmatically via a future
   `PATCH /bundles/:id/members/:id` action; ship the server-side support but
   skip the drag-sort Stimulus controller. Master agent confirms.

2. **Synchronous vs background cover building.** Recommendation: background
   (Sidekiq). The build is sub-second for ≤4 tiles and ~2s for 9 tiles, but the
   IGDB CDN tile fetch can spike to several seconds on cold cache. Putting the
   work in Sidekiq keeps the request-cycle snappy AND lets retries handle CDN
   flakes. The user sees a "regenerating…" indicator on the show page until the
   build completes (Turbo Stream from the job).

3. **Mutating `bundle_type` post-create.** Recommendation: forbid. Changing the
   type would change the filename, requiring a file rename. The simpler shape is
   "delete and recreate." The form does not expose the field on edit. Master
   agent confirms.

4. **Member-picker source — local Game library or IGDB live search?**
   Recommendation: local library. The bundle is curated from pito's owned games;
   if the user wants an IGDB game they don't own, they add it to their library
   first (Phase 14 §1's flow). This keeps the bundle-add UX fast (no
   rate-limited IGDB call per keystroke). Master agent confirms.

5. **Enum naming collision.** `Bundle.igdb_source_types` includes `collection` —
   but `bundle_types` also includes `collection`. Even with the `igdb_source`
   prefix, the predicate name is `igdb_source_collection?` which is verbose but
   unambiguous. Alternative: rename the enum values to avoid overlap (e.g.,
   `igdb_franchise`, `igdb_collection`, `igdb_genre`). Recommendation: keep the
   natural names + accept the verbose predicate. Master agent picks.

6. **Empty IGDB-source bundle.** Allow creating an IGDB-source bundle without
   immediately calling `seed_from_igdb`? Recommendation: yes (the validation
   only requires consistency, not non-emptiness). The user can seed later.
   Master agent confirms.

7. **Bundle-level `last_sync_error` column.** Should bundles carry a sync-error
   column like Games do? The error sources: `seed_from_igdb` (IGDB API failure),
   `BundleCoverBuild` (tile fetch failure / libvips error). Recommendation: add
   a single `last_error` text column to `bundles` in this phase, surface inline
   on the show page. Master agent confirms.

8. **Bundle on-disk-cover cleanup on destroy.** Recommendation: add a
   `before_destroy` callback that removes the file if it exists. Plus a
   follow-up rake task (`pito:bundles:reap_orphans`) for any old files left over
   from prior bugs. Master agent confirms.

9. **`/composites/:filename.jpg` route — auth or open?** The rest of the app is
   auth-gated. Recommendation: auth-gated. The composite covers are user data,
   not public assets. Use `before_action :require_session`. (Single install +
   flat path: no IDOR concern since there's no per-tenant scoping.) Master agent
   confirms.

10. **libvips version pinning.** `ruby-vips` is in the Gemfile (via Active
    Storage variant processor); the binary is the user's install. Test
    environments need libvips installed. Phase 14 §1 introduces no new gem, so
    the implementation agent verifies `Gemfile.lock` carries `ruby-vips`
    already. If not, a follow-up Gemfile change lands.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. `/bundles` page heading → `bundles` (lowercase).
2. Empty state → `no bundles yet. [ add bundle ] to create one.` (Note: per the
   project's bracketed-link convention, use `[ add bundle ]` NOT `[ + bundle ]`
   — no redundant context.)
3. Create button label → `[ add bundle ]`.
4. Bundle-type selector → label `type` (lowercase). Options `series`,
   `collection`, `genre`, `custom` (lowercase).
5. IGDB-seed copy on the new-bundle form → `seed from igdb`.
6. Show-page button → `[ seed from igdb ]`.
7. `[ no cover ]` placeholder → matches Spec 01.
8. Composite-cover-failed inline →
   `couldn't build cover; will retry on next change.`
9. "+N" overlay format → `+2` (just the number).
10. Member-add type-ahead empty → `no games match`.
11. Member-remove inline button → `[ remove ]` (verb-based, no symbol).
12. Bundle delete action-screen → reuse the shared `Confirmable` copy.

### Open-question decisions

1. **Drag-sort UI.** Defer to a polish dispatch. Initial v1 ordering: insertion
   order via `MAX(position) + 1`. Server-side support for
   `PATCH /bundles/:id/members/:id` ships in this phase; the drag- sort Stimulus
   controller does not.
2. **Sync vs background cover building.** Background (Sidekiq). User sees a
   "regenerating…" indicator on the show page until the build completes (Turbo
   Stream from the job).
3. **Mutating `bundle_type` post-create.** Forbid. The form does not expose the
   field on edit. To change type, user deletes and recreates.
4. **Member-picker source.** Local Game library only. If the user wants an IGDB
   game they don't own, they add it via Spec 01's flow first.
5. **Enum naming collision** (`bundle_types` and `igdb_source_types` both have
   `collection`). Keep the natural names. Predicate names like
   `igdb_source_collection?` are verbose but unambiguous.
6. **Empty IGDB-source bundle (created without seed).** Allow. Validation
   requires consistency, not non-emptiness. User can seed later.
7. **Bundle-level `last_error` column.** Yes, add. Single `last_error` text
   column on `bundles`. Surface inline on the show page.
8. **On-disk cover cleanup on destroy.** Add a `before_destroy` callback that
   removes the file if it exists. Plus a follow-up `pito:bundles:reap_orphans`
   rake task for any old files left from prior bugs.
9. **`/composites/:filename.jpg` route.** Auth-gated.
   `before_action :require_session`. Composite covers are user data, not public
   assets.
10. **libvips version pinning.** No pin. Standard test posture; the binary is
    the user's install. Test environments install libvips via apt or brew per
    the dev setup. If a future deploy issue surfaces, revisit.

## Implementation lane assignment

Single lane: **rails-impl**. Touches:

- `db/migrate/`, `db/schema.rb`
- `app/models/`, `app/services/composite_cover/`, `app/jobs/`,
  `app/controllers/`, `app/views/bundles/`, `app/views/bundle_members/`,
  `app/views/shared/`, `app/javascript/controllers/`
- `app/lib/confirmable.rb` (or wherever the registry lives)
- `config/routes.rb`
- `spec/**`

No `extras/cli/`, no `extras/website/`, no `docs/` (docs-keeper follow-up after
validation).

## Reviewer checkpoints (post-implementation)

1. `bundle exec rspec` — green.
2. `bundle exec rubocop` — green or no new violations.
3. `bundle exec brakeman -q` — green or no new findings.
4. `git grep 'tenant\|Tenant' app/models/bundle*.rb app/services/composite_cover/`
   → zero matches.
5. `git grep 'tenant-' app/services/composite_cover/` → zero matches (flat-path
   verification).
6. Manual playbook §1-§12.
7. After bundle delete, no orphan file at
   `<PITO_ASSETS_PATH>/composites/<type>-<id>.jpg`.
8. Spec file count delta logged in `log.md`.
