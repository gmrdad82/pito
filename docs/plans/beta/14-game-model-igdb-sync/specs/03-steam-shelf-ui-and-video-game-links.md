# Phase 14 §3 — Steam-Shelf UI + `video_game_link` Join + MCP Tools

> **Status:** dispatched 2026-05-10. Lanes: **rails** (primary) + **mcp**
> (sub-lane). Builds on Phase 14 §1 (Game model + IGDB) and §2 (Bundles +
> composite covers).
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 6 §"Steam-shelf game listing
>   UI" + work unit 9 (MCP tool catalog expansion). Per-domain coverage matrix
>   posture from Resolved ambiguities #2 / #3.
> - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md` — note 4 §"Linking games
>   & bundles to videos" + §"Analytics integration".
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
>   `tenant_id`; multi-user means everyone sees everything.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — `app` scope for
>   every game / bundle MCP tool.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12 §"Out of scope" item: "Game ↔ Video links — work unit 6 / Phase
>   14". This spec is the work unit 6 deliverable for the Video side.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
>   — Game / Genre / Platform / Company models.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/02-bundles-and-composite-covers.md`
>   — Bundle / BundleMember models.
> - `CLAUDE.md` — bracketed-link convention, monospace 13px, no JS confirms,
>   yes/no booleans at every external boundary.

## Goal

Wrap the Game + Bundle data model in a Steam-shelf-style listing UX ("/games"
and "/bundles" become long, scannable, image-forward surfaces; bundles appear as
shelves at the top of the games index when configured). Add the
`video_game_link` polymorphic join table that ties Videos to Games AND/OR
Bundles (per Note 4) so the analytics phase (work unit 5 / Phase 13) can
attribute subscriber gain / watch time / CTR to game and bundle scope. Land the
MCP tool surface for game / bundle management so Claude Mobile can drive the
domain.

This spec is the surface-and-integration tier on top of §1 and §2. It makes the
data tier user-facing and analytics-ready.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                   |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Steam-shelf shape.** Horizontal-scrolling rows of cover-art tiles. Each row is a "shelf" (e.g., "Recently played", "By Bethesda", "Bundles", "All games"). Mouse-wheel + drag-scroll support. Per-tile hover surfaces the title + release_year + IGDB rating in a small caption strip. Per Note 4 + the user's Steam-style direction in the realignment. |
| Q2  | **Page split.** `/games` (the games index) carries the primary shelves: Bundles row at top (composite covers), then per-row partitions (recently played, by genre, by platform, all games). `/bundles` is the bundle picker — flat list of every bundle with its composite cover. `/games/:id` and `/bundles/:id` are the detail pages.                    |
| Q3  | **Pane integration.** Games and bundles do NOT integrate with the workspace pane system (Channels / Videos panes). They live as standalone listing pages. The user opens a Game or Bundle by clicking its tile; no multi-pane workspace for games in v1. (See Open Questions #1 for future hooks.)                                                         |
| Q4  | **`video_game_link` cardinality.** Many-to-many. A Video can be linked to multiple Games AND/OR multiple Bundles. A Game can be linked to multiple Videos. A Bundle can be linked to multiple Videos. Per Note 4: "Polymorphic link table — a video can be tagged with multiple games and/or bundles."                                                     |
| Q5  | **`video_game_link` polymorphism shape.** Single table with a `link_type` enum (`game` / `bundle`) and two nullable foreign keys (`game_id`, `bundle_id`). Constraint: exactly one of `game_id` / `bundle_id` is non-null per row. Per Note 4 §"Linking games & bundles to videos" exact schema.                                                           |
| Q6  | **`is_primary` flag.** Per Note 4: each link can be primary or secondary ("for videos covering one main thing + side mentions"). Boolean column. The analytics layer (Phase 13) reads this for primary-only vs even-split attribution. Default `false`.                                                                                                    |
| Q7  | **Tenant-free.** No `tenant_id`. Per ADR 0003.                                                                                                                                                                                                                                                                                                             |
| Q8  | **MCP scope.** Every game / bundle MCP tool gates on `app`. Two-step `confirm: yes/no` for write tools (CLAUDE.md hard rule). Per ADR 0004.                                                                                                                                                                                                                |
| Q9  | **CLI parity.** Out of scope. Realignment work unit 10. The MCP surface is canonical for non-web access in this phase; CLI parity follows in a separate dispatch.                                                                                                                                                                                          |
| Q10 | **Boolean boundary discipline.** `is_primary`, `confirm`, etc. are `"yes"` / `"no"` strings on the wire. Internal Boolean.                                                                                                                                                                                                                                 |
| Q11 | **Analytics integration.** This spec ships the data + the link-management UX. The actual analytics queries (subscribers gained per game, watch time per game, etc.) live in Phase 13 (analytics work unit 5). This spec verifies the join is queryable but does NOT compute aggregates.                                                                    |
| Q12 | **Studio-deep-link parity.** Phase 12's Studio deep-link partial (`shared/_studio_link.html.erb`) reused on the video-side surface where game-tagging integrates with the existing pre-publish checklist game-ok box. The checklist BOX stays manual (per Phase 12 Q2); but the video edit form now surfaces a "linked games / bundles" section.           |

## Migration posture (LOCKED)

**Additive on the post-Phase-14-§2 schema.** New `video_game_links` table; light
edits to `videos.show.html.erb` and the index views. No column drops, no table
renames.

If Phase 12 or §1 / §2 is missing in the install when this spec lands, STOP —
the implementation agent confirms prerequisites first.

## Files touched

### Schema / migrations

- `db/migrate/<NN>_create_video_game_links.rb` (new) — `video_game_links` table.
- `db/schema.rb` — auto-regenerated.

### Models

- `app/models/video_game_link.rb` (new) — polymorphic-ish link row.
- `app/models/video.rb` (light edit) — `has_many :video_game_links`,
  `has_many :linked_games, through: :video_game_links, source: :game`,
  `has_many :linked_bundles, through: :video_game_links, source: :bundle`.
- `app/models/game.rb` (light edit) — `has_many :video_game_links`,
  `has_many :videos, through: :video_game_links`. Plus a callback hook on
  `video_game_link` create/destroy that recomputes `hours_of_footage_cached`
  (sum of linked-video durations / 3600).
- `app/models/bundle.rb` (light edit) — same shape as Game.

### Controllers

- `app/controllers/games_controller.rb` (light edit) — extend `index` to load
  shelf-shaped data (recently played, by genre, bundles row, all games). The
  action returns multiple ordered collections rather than a flat list.
- `app/controllers/bundles_controller.rb` (light edit, post §2) — extend `index`
  to render the bundle-shelf UI.
- `app/controllers/videos_controller.rb` (light edit, post Phase 12) — extend
  the video edit form view bag with linked games / bundles. Ad/remove links via
  the new `video_game_links_controller`.
- `app/controllers/video_game_links_controller.rb` (new) — RESTful surface
  scoped to a parent video. Routes:
  - `POST /videos/:video_id/links` — add a link. Body picks `link_type` (`game`
    / `bundle`), `linked_id` (game_id or bundle_id), `is_primary` (`yes` /
    `no`).
  - `PATCH /videos/:video_id/links/:id` — flip `is_primary`.
  - `DELETE /videos/:video_id/links/:id` — remove the link.
  - The action-screen pattern is reused for delete (single row delete uses
    `/deletions/video_game_link/:ids` per the bulk-as- foundation rule).

### Routes

- `config/routes.rb` (light edit) —
  `resources :videos do resources :links, only: %i[create update destroy], controller: "video_game_links"; end`.
  Plus `Confirmable` registration for `video_game_link` (so single-row deletes
  go through the action screen).

### Views

- `app/views/games/index.html.erb` (heavy rewrite) — Steam-shelf UX. Section
  structure:
  1. **Bundles shelf** (only when `Bundle.exists?`) — horizontal- scrolling row
     of bundle composite covers. Click → bundle show.
  2. **Recently played** — games ordered by `played_at DESC NULLS LAST`,
     limit 12.
  3. **By genre** — for each genre present in the user's library, a shelf of
     games in that genre (limit 12 per shelf, ordered by
     `igdb_rating DESC NULLS LAST`).
  4. **By platform owned** — for each `platform_owned`, a shelf of games owned
     on that platform.
  5. **All games** — flat alphabetical (or release_year DESC, architect picks;
     recommendation: release_year DESC). Render as a wrapping grid.

  Each shelf is a `<section class="shelf">` with a heading and a
  horizontal-scroll container. Each tile is a `<a class="tile">` wrapping the
  cover image (using the `_igdb_cover.html.erb` partial from §1). Hover surfaces
  the caption strip via CSS.

- `app/views/games/_shelf.html.erb` (new) — partial for one shelf row. Takes
  `title`, `games`, `more_link` (optional "see all").
- `app/views/games/_tile.html.erb` (new) — partial for one game tile.
- `app/views/bundles/index.html.erb` (heavy rewrite) — flat grid of bundle
  composite covers. Each tile shows the composite + the bundle name + member
  count.
- `app/views/bundles/_tile.html.erb` (new) — partial for one bundle tile.
- `app/views/videos/edit.html.erb` (light edit, post-Phase-12) — add a "Linked
  games / bundles" fieldset. The fieldset shows current links (with `[ remove ]`
  per row + `[ ★ primary ]` toggle) and an `[ + add link ]` button that opens an
  inline picker.
- `app/views/videos/_links_section.html.erb` (new) — the linked-
  games-and-bundles fieldset partial.
- `app/views/video_game_links/_link_row.html.erb` (new) — single row in the
  links table, shows tile thumbnail, link kind, primary badge, action buttons.
- `app/views/shared/_steam_shelf.html.erb` (new) — generic shelf primitive
  reusable across game / bundle index views. Takes a collection and a
  `tile_partial:` reference.

### Stimulus controllers

- `app/javascript/controllers/steam_shelf_controller.js` (new) — drag-scroll +
  mouse-wheel-horizontal scroll on shelf rows. Listens to `wheel` events with
  `deltaY` and translates to `scrollLeft += deltaY` when the cursor is over a
  shelf. NO `confirm()` / `alert()` / `prompt()`. Pure UI affordance.
- `app/javascript/controllers/link_picker_controller.js` (new) — type-ahead
  picker for the video edit form's [ + add link ] button. Sources from local
  `Game` and `Bundle`. No IGDB calls.
- `app/javascript/controllers/index.js` — register both controllers.

### MCP tools

All gated on `app` scope (per ADR 0004). All write tools take `confirm: "yes"` /
`"no"` (CLAUDE.md hard rule).

- `app/mcp/tools/game_search.rb` (new) — read-only; returns local Game rows
  matching the query. Proxies to `Game.where("title ILIKE ?", "%#{q}%")`.
  Limit 25.
- `app/mcp/tools/game_add_from_igdb.rb` (new) — write. Adds a Game by IGDB ID.
  Two-step `confirm`. Enqueues `GameIgdbSync`.
- `app/mcp/tools/game_resync.rb` (new) — write. Enqueues `GameIgdbSync` for an
  existing game. Two-step `confirm`.
- `app/mcp/tools/game_update_local.rb` (new) — write. Updates the local-only
  fields (`platform_owned_id`, `played_at`, `notes`, `hours_of_footage_manual`).
  Two-step `confirm`.
- `app/mcp/tools/game_destroy.rb` (new) — write. Two-step `confirm`. Cascades
  through join tables.
- `app/mcp/tools/bundle_search.rb` (new) — read-only.
- `app/mcp/tools/bundle_create.rb` (new) — write. Two-step `confirm`.
- `app/mcp/tools/bundle_update.rb` (new) — write. Updates `name` only
  (`bundle_type` and `igdb_source_*` immutable post-create per §2 Q3). Two-step
  `confirm`.
- `app/mcp/tools/bundle_destroy.rb` (new) — write. Two-step `confirm`.
- `app/mcp/tools/bundle_member_add.rb` (new) — write. Two-step `confirm`.
  Triggers `BundleCoverBuild`.
- `app/mcp/tools/bundle_member_remove.rb` (new) — write. Same.
- `app/mcp/tools/bundle_seed_from_igdb.rb` (new) — write. Two- step `confirm`.
  Pulls members from IGDB.
- `app/mcp/tools/video_link_game.rb` (new) — write. Creates a `video_game_link`
  row with `link_type: game`. Two-step `confirm`. `is_primary` arg.
- `app/mcp/tools/video_link_bundle.rb` (new) — write. Same with
  `link_type: bundle`.
- `app/mcp/tools/video_unlink.rb` (new) — write. Removes a link. Two-step
  `confirm`. Bulk-friendly: takes a list of link IDs.
- `app/mcp/tools/video_link_set_primary.rb` (new) — write. Flips `is_primary` on
  a link. Two-step `confirm`.

The implementation agent registers each tool in `app/mcp/registry.rb` (or
wherever the MCP catalog lives — the agent enumerates) and updates the
scope-per-tool table in `docs/mcp.md` (light edit, owned by docs-keeper after
validation).

### Confirmable wiring

- `app/lib/confirmable.rb` (or its location) — add `"video_game_link"` to
  `Confirmable::TYPES` so single-row link deletes route through
  `/deletions/video_game_link/:ids`.

### Tests

- `spec/models/video_game_link_spec.rb` (new)
- `spec/models/video_spec.rb` (light edit — add link associations)
- `spec/models/game_spec.rb` (light edit — add link associations
  - footage-cache callback)
- `spec/models/bundle_spec.rb` (light edit — add link associations)
- `spec/factories/video_game_links.rb` (new)
- `spec/requests/games_spec.rb` (heavy edit — Steam-shelf index expectations,
  additive on §1's request specs)
- `spec/requests/bundles_spec.rb` (heavy edit — bundle-shelf index)
- `spec/requests/video_game_links_spec.rb` (new)
- `spec/system/games_steam_shelf_spec.rb` (new — Capybara smoke of shelf
  rendering + horizontal scroll)
- `spec/system/video_link_picker_spec.rb` (new — Capybara smoke of adding /
  removing a video↔game link)
- `spec/mcp/tools/game_search_spec.rb` (new)
- `spec/mcp/tools/game_add_from_igdb_spec.rb` (new)
- `spec/mcp/tools/game_resync_spec.rb` (new)
- `spec/mcp/tools/game_update_local_spec.rb` (new)
- `spec/mcp/tools/game_destroy_spec.rb` (new)
- `spec/mcp/tools/bundle_search_spec.rb` (new)
- `spec/mcp/tools/bundle_create_spec.rb` (new)
- `spec/mcp/tools/bundle_update_spec.rb` (new)
- `spec/mcp/tools/bundle_destroy_spec.rb` (new)
- `spec/mcp/tools/bundle_member_add_spec.rb` (new)
- `spec/mcp/tools/bundle_member_remove_spec.rb` (new)
- `spec/mcp/tools/bundle_seed_from_igdb_spec.rb` (new)
- `spec/mcp/tools/video_link_game_spec.rb` (new)
- `spec/mcp/tools/video_link_bundle_spec.rb` (new)
- `spec/mcp/tools/video_unlink_spec.rb` (new)
- `spec/mcp/tools/video_link_set_primary_spec.rb` (new)

### Out of scope (this spec)

- CLI parity — work unit 10.
- Analytics aggregations — Phase 13.
- Calendar / Notifications integration — work units 7 / 8.
- IGDB live search inside the link picker (we use the local library for picker
  sources to keep the UX fast).
- Drag-sort UI for bundle members — §2 Open Questions #1.

## Schema

### `video_game_links` table (new)

| Column       | Type       | Null | Default | Index                           | Notes                                                                            |
| ------------ | ---------- | ---- | ------- | ------------------------------- | -------------------------------------------------------------------------------- |
| `id`         | `bigint`   | NOT  | (pk)    | —                               | Local PK.                                                                        |
| `video_id`   | `bigint`   | NOT  | —       | btree, FK → videos (cascade)    |                                                                                  |
| `link_type`  | `integer`  | NOT  | —       | btree                           | Enum: `game: 0`, `bundle: 1`.                                                    |
| `game_id`    | `bigint`   | NULL | —       | btree, FK → games (cascade)     | Set when `link_type = game`. NULL otherwise.                                     |
| `bundle_id`  | `bigint`   | NULL | —       | btree, FK → bundles (cascade)   | Set when `link_type = bundle`. NULL otherwise.                                   |
| `is_primary` | `boolean`  | NOT  | false   | btree (where is_primary = true) | Whether this link is the video's primary game/bundle (analytics weighting hint). |
| `created_at` | `datetime` | NOT  | —       | —                               |                                                                                  |
| `updated_at` | `datetime` | NOT  | —       | —                               |                                                                                  |

Composite unique indexes:

- `(video_id, game_id)` UNIQUE WHERE `game_id IS NOT NULL` — prevents a Video
  being linked to the same Game twice.
- `(video_id, bundle_id)` UNIQUE WHERE `bundle_id IS NOT NULL` — same for
  bundles.

CHECK constraint:

- `(link_type = 0 AND game_id IS NOT NULL AND bundle_id IS NULL) OR  (link_type = 1 AND bundle_id IS NOT NULL AND game_id IS NULL)`

The implementation agent decides between a Postgres CHECK constraint
(authoritative) and an ActiveRecord `validate :exactly_one_target` custom
validator (sufficient at the model layer). Recommendation: both — the DB CHECK
is defense-in-depth; the model validator gives nice error messages.

### Foreign keys

- `video_game_links.video_id → videos.id` (`ON DELETE CASCADE`).
- `video_game_links.game_id → games.id` (`ON DELETE CASCADE`).
- `video_game_links.bundle_id → bundles.id` (`ON DELETE CASCADE`).

## Models

### `VideoGameLink`

```ruby
class VideoGameLink < ApplicationRecord
  enum link_type: { game: 0, bundle: 1 }, prefix: :link

  belongs_to :video
  belongs_to :game, optional: true
  belongs_to :bundle, optional: true

  validate :exactly_one_target
  validates :game_id, uniqueness: { scope: :video_id, allow_nil: true }
  validates :bundle_id, uniqueness: { scope: :video_id, allow_nil: true }

  after_create_commit :recompute_game_footage_cache
  after_destroy_commit :recompute_game_footage_cache

  def target
    link_game? ? game : bundle
  end

  private

  def exactly_one_target
    if link_game? && (game_id.blank? || bundle_id.present?)
      errors.add(:base, "game link must have game_id and no bundle_id")
    end
    if link_bundle? && (bundle_id.blank? || game_id.present?)
      errors.add(:base, "bundle link must have bundle_id and no game_id")
    end
  end

  def recompute_game_footage_cache
    if link_game? && game.present?
      total = game.videos.sum(:duration_seconds)
      game.update_column(:hours_of_footage_cached, (total / 3600.0).round)
    end
    # Bundles do not carry a hours_of_footage_cached column today —
    # the analytics phase will derive bundle aggregates on the fly.
  end
end
```

### `Video` (light edit, on top of Phase 12)

```ruby
has_many :video_game_links, dependent: :destroy
has_many :linked_games,   through: :video_game_links, source: :game
has_many :linked_bundles, through: :video_game_links, source: :bundle

scope :linked_to_game,   ->(game)   { joins(:video_game_links).where(video_game_links: { game_id: game.id }) }
scope :linked_to_bundle, ->(bundle) { joins(:video_game_links).where(video_game_links: { bundle_id: bundle.id }) }
```

### `Game` (light edit, on top of §1)

```ruby
has_many :video_game_links, dependent: :destroy
has_many :videos, through: :video_game_links
```

### `Bundle` (light edit, on top of §2)

```ruby
has_many :video_game_links, dependent: :destroy
has_many :videos, through: :video_game_links
```

## Steam-shelf UX

### `/games` index

Controller:

```ruby
def index
  @bundles_shelf = Bundle.order(updated_at: :desc).limit(10)
  @recently_played = Game.where.not(played_at: nil).order(played_at: :desc).limit(12)
  @genres_shelves = Genre.joins(:games).distinct.limit(8).map do |g|
    [g, g.games.order(igdb_rating: :desc).limit(12)]
  end
  @platforms_shelves = Platform.joins(:owned_by_games).distinct.map do |p|
    [p, p.owned_by_games.order(release_year: :desc).limit(12)]
  end
  @all_games = Game.order(release_year: :desc).page(params[:page]).per(48)
end
```

(The `Platform.owned_by_games` association is added in Phase 14 §1's `Platform`
model:
`has_many :owned_by_games, class_name: "Game", foreign_key: :platform_owned_id`.)

View structure (per `index.html.erb`):

```erb
<%= render "shelf", title: "bundles", collection: @bundles_shelf,
                    tile_partial: "bundles/tile", more_link: bundles_path %>

<%= render "shelf", title: "recently played", collection: @recently_played,
                    tile_partial: "games/tile" %>

<% @genres_shelves.each do |(genre, games)| %>
  <%= render "shelf", title: genre.name.downcase, collection: games,
                      tile_partial: "games/tile" %>
<% end %>

<% @platforms_shelves.each do |(platform, games)| %>
  <%= render "shelf", title: platform.name.downcase, collection: games,
                      tile_partial: "games/tile" %>
<% end %>

<section class="all-games-grid">
  <h2>all games</h2>
  <div class="grid">
    <% @all_games.each do |game| %>
      <%= render "tile", game: game %>
    <% end %>
  </div>
  <%= paginate @all_games %>
</section>
```

CSS shape (added to `app/assets/tailwind/application.css` or the project's CSS
asset path — verify): each `.shelf` is a horizontal flex container with
`overflow-x: auto`. Each `.tile` is a fixed- width (e.g., 150×200) cover-image
link with hover caption. Per design.md: monospace 13px, `cursor: pointer`, no
animation, no red unless destructive. The shelf scrollbar uses the design
system's neutral border tokens.

### `/bundles` index

Flat wrapping grid of bundle tiles. Each tile renders the composite cover
(300×400) + bundle name + member count below. Click → bundle show page.

### `/games/:id` and `/bundles/:id`

Detail pages already covered by §1 (game show) and §2 (bundle show). This spec
adds:

- A "linked videos" section to each detail page: lists every `Video` that has a
  `video_game_link` pointing at this Game / Bundle. Each row: `[ video title ]`
  link to the video page + `[ ★ ]` badge if the link is primary.
- A "[ link a video ]" CTA that opens a Turbo Frame picker selecting from
  `Video.published`. Submits to `POST /videos/:video_id/links` with
  `link_type` + this resource's ID.

(The reverse direction — adding a game/bundle link from the video edit page —
lives on the video edit form per §"Views" above.)

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows `video_game_links` table with all columns from
      §"video_game_links table" present.
- [ ] FK `video_game_links.video_id → videos.id` ON DELETE CASCADE.
- [ ] FK `video_game_links.game_id → games.id` ON DELETE CASCADE.
- [ ] FK `video_game_links.bundle_id → bundles.id` ON DELETE CASCADE.
- [ ] Composite unique index on `(video_id, game_id)` WHERE
      `game_id IS NOT NULL`.
- [ ] Composite unique index on `(video_id, bundle_id)` WHERE
      `bundle_id IS NOT NULL`.
- [ ] DB CHECK constraint enforcing exactly-one-target invariant.
- [ ] Migration runs cleanly; rollback mechanically reversible.

### Models

- [ ] `VideoGameLink.link_types` returns the two-symbol enum hash.
- [ ] `VideoGameLink#exactly_one_target` validator rejects a row with both
      `game_id` and `bundle_id` set.
- [ ] Same validator rejects a row with neither set.
- [ ] `(video_id, game_id)` uniqueness enforced (pre-DB at the model layer; DB
      layer as defense-in-depth).
- [ ] `(video_id, bundle_id)` uniqueness enforced.
- [ ] `Video#linked_games` returns through-join Games.
- [ ] `Video#linked_bundles` returns through-join Bundles.
- [ ] `Game#videos` returns through-join Videos.
- [ ] `Bundle#videos` returns through-join Videos.
- [ ] `VideoGameLink#target` returns `game` for game links, `bundle` for bundle
      links.
- [ ] `after_create_commit` recomputes `Game#hours_of_footage_cached` when the
      link is to a Game.
- [ ] `after_destroy_commit` recomputes the same.

### Controllers

- [ ] `GET /games` renders shelf-shaped layout.
- [ ] `GET /bundles` renders bundle grid.
- [ ] `POST /videos/:video_id/links` with
      `link_type=game,     linked_id=<game_id>, is_primary=no` creates a link.
- [ ] `POST` with `link_type=bundle, linked_id=<bundle_id>` creates a bundle
      link.
- [ ] `POST` with both `game_id` and `bundle_id` smuggled returns 422.
- [ ] `POST` with duplicate (same video + same target): 422.
- [ ] `PATCH /videos/:video_id/links/:id` flips `is_primary`.
- [ ] `DELETE /videos/:video_id/links/:id` goes through
      `/deletions/video_game_link/:id` action screen.
- [ ] After confirmed delete: link gone; `Game#hours_of_footage_cached`
      recomputed.

### MCP tools

- [ ] Every tool listed in §"MCP tools" registered in the catalog.
- [ ] Every tool gated on `app` scope.
- [ ] Every write tool implements two-step `confirm: yes/no`.
- [ ] Boundary booleans (`confirm`, `is_primary`) accept "yes" / "no" strings
      and are NOT accepted as `true` / `false` (CLAUDE.md hard rule).
- [ ] Each tool validates its scope (a bearer token without `app` scope cannot
      invoke any of them).
- [ ] `docs/mcp.md` scope-per-tool table updated with the new tools (docs-keeper
      handles after validation).

### Steam-shelf UX

- [ ] Bundles shelf renders only when at least one Bundle exists.
- [ ] Recently played shelf renders only games with `played_at` not null.
- [ ] Genre shelves render one shelf per genre with at least 1 game.
- [ ] Platform shelves render one shelf per platform with at least 1 owned game.
- [ ] All-games grid paginates (48 per page).
- [ ] Hover on a tile shows the title + release_year + IGDB rating.
- [ ] Mouse-wheel scroll horizontally on a shelf works (manual verification).
- [ ] Bracketed-link convention applied to "see all" / shelf headings.
- [ ] No red color anywhere on the shelves (red reserved for destructive — none
      present).
- [ ] Cursor is `pointer` on every clickable element.

### Tests

- [ ] `bundle exec rspec spec/models/video_game_link_spec.rb` green.
- [ ] `bundle exec rspec spec/models/video_spec.rb` green (additive).
- [ ] `bundle exec rspec spec/models/game_spec.rb` green (additive).
- [ ] `bundle exec rspec spec/models/bundle_spec.rb` green (additive).
- [ ] `bundle exec rspec spec/requests/games_spec.rb` green.
- [ ] `bundle exec rspec spec/requests/bundles_spec.rb` green.
- [ ] `bundle exec rspec spec/requests/video_game_links_spec.rb` green.
- [ ] `bundle exec rspec spec/system/games_steam_shelf_spec.rb` green.
- [ ] `bundle exec rspec spec/system/video_link_picker_spec.rb` green.
- [ ] `bundle exec rspec spec/mcp/tools/` green for every new tool spec.

## Test sweep (exhaustive)

### `VideoGameLink` model unit specs

**Associations:**

- `belongs_to :video`
- `belongs_to :game, optional: true`
- `belongs_to :bundle, optional: true`

**Enum:**

- `link_types` matches `{game: 0, bundle: 1}`
- `link_game?` / `link_bundle?` predicates work

**Validations — `exactly_one_target`:**

- `link_type=game, game_id=set, bundle_id=nil` → valid
- `link_type=bundle, bundle_id=set, game_id=nil` → valid
- `link_type=game, game_id=nil` → invalid
- `link_type=game, game_id=set, bundle_id=set` → invalid
- `link_type=bundle, game_id=set, bundle_id=set` → invalid
- `link_type=bundle, bundle_id=nil` → invalid
- `link_type=game, bundle_id=set, game_id=nil` → invalid (mismatch)

**Uniqueness:**

- Same `(video_id, game_id)` rejected
- Different `video_id` same `game_id`: allowed
- Same `video_id` different `game_id`: allowed
- Same shape for bundle links

**`is_primary`:**

- Default false
- Multiple primaries on a single video allowed (analytics-side decision — see
  Open Questions #2)

**`target`:**

- `target` returns the `game` for game links
- `target` returns the `bundle` for bundle links

**Callbacks — `recompute_game_footage_cache`:**

- After create on a game link with a video having `duration_seconds=600`:
  `game.hours_of_footage_cached` becomes 0 (600/3600=0.16, rounded → 0)
- After create on a game link with `duration_seconds=7200`:
  `game.hours_of_footage_cached` becomes 2
- Multiple linked videos sum: 3600 + 5400 + 1800 = 10800 → 3
- After destroy: recomputed; cache decreases
- Bundle links do NOT touch the game cache

**Edge cases:**

- Smuggling both game_id and bundle_id at the DB layer (raw SQL insert):
  rejected by the CHECK constraint
- A video linked to a game; the game is destroyed: link cascades
- A video linked to a bundle; the bundle is destroyed: link cascades
- A video destroyed: all its links cascade

### `Video` model unit specs (additive)

- `has_many :video_game_links, dependent: :destroy`
- `has_many :linked_games, through: :video_game_links, source: :game`
- `has_many :linked_bundles, through: :video_game_links, source: :bundle`
- `Video.linked_to_game(g)` scope returns videos linked to g
- `Video.linked_to_bundle(b)` scope returns videos linked to b

### `Game` model unit specs (additive)

- `has_many :videos, through: :video_game_links`
- `Game#hours_of_footage_cached` recomputes on link create / destroy
- Manual override (`hours_of_footage_manual`) precedence: when manual is set,
  `hours_of_footage` returns manual

### `Bundle` model unit specs (additive)

- `has_many :videos, through: :video_game_links`
- (No footage cache on Bundle — Phase 13 derives bundle-scope metrics on the
  fly.)

### `GamesController` request specs (additive on §1)

**`GET /games` (Steam-shelf rendering):**

- 200, renders shelf-shaped layout
- Bundles shelf present when bundles exist; absent when no bundles
- Recently-played shelf renders games with `played_at` set, ordered by
  `played_at DESC`
- Genres shelves render one section per genre
- Platforms shelves render one section per platform_owned with ≥1 game
- All-games grid paginated; first page has up to 48 games
- Empty library: only the empty-state copy visible (no shelves)

### `BundlesController` request specs (additive on §2)

**`GET /bundles` (grid rendering):**

- 200, renders flat grid
- Each tile shows composite cover (or `[ no cover ]`) + name + member count
- Tiles ordered by updated_at desc

### `VideoGameLinksController` request specs (new file)

**`POST /videos/:video_id/links` (game link, happy):**

- `link_type=game, linked_id=<game_id>, is_primary=no` → 302 (or Turbo Stream);
  link persisted
- 422 on `linked_id` referencing nonexistent Game
- 422 on duplicate link (same video + same game)
- 422 on smuggled `bundle_id` along with `game_id`
- `is_primary=yes` persists as `true`

**`POST` (bundle link, happy):**

- Same shape with `link_type=bundle`

**`POST` (validation):**

- `link_type=game` without `linked_id`: 422
- `link_type=invalid_value`: 422

**`PATCH /videos/:video_id/links/:id`:**

- Flip `is_primary` from false to true: 302; persisted
- Flip from true to false: 302; persisted
- 404 on missing link

**`DELETE /videos/:video_id/links/:id`:**

- Bare DELETE without action-screen flow: 422 (must go through /deletions/...) —
  verify the controller does NOT short-circuit the bulk-as-foundation
  discipline. Recommendation: the `[ remove ]` button on the link row routes to
  `/deletions/video_game_link/:id` (the action screen), which POSTs back to the
  controller's destroy action with confirmation proven.
- After action-screen confirmation: link destroyed; cascade callbacks fire

### MCP tool specs

For each tool, cover (in `spec/mcp/tools/<name>_spec.rb`):

- Tool registered in catalog with the correct name
- Tool's declared scope is `:app`
- Authenticated request without `app` scope → 401-equivalent
- Authenticated request with `app` scope + valid args → success
- Authenticated request with invalid args → validation error payload
- (Write tools) `confirm: "no"` returns a preview / hint payload
- (Write tools) `confirm: "yes"` performs the action
- (Write tools) `confirm` missing → treated as "no" (preview)
- Boolean smuggling: `confirm: true` (boolean, not string) → 422 with clear "use
  'yes' or 'no'" message
- Boolean smuggling: `is_primary: 1` → 422
- Side-effects asserted via factory state:
  - `game_add_from_igdb`: Game row created; `GameIgdbSync` enqueued
  - `bundle_member_add`: BundleMember row created; `BundleCoverBuild` enqueued
  - `video_link_game`: VideoGameLink row created; cache recomputed
  - etc.

(One spec file per tool — count: 16 new MCP tool specs.)

### System specs

**`spec/system/games_steam_shelf_spec.rb`:**

- Visit `/games` with a populated library
- Bundles shelf visible
- Recently-played shelf visible
- Click a tile → navigate to game show
- Hover on a tile → caption strip visible (Capybara `find` on the caption
  element after hover; if Capybara doesn't reliably mock hover, drop to a unit
  test of the CSS class application)

**`spec/system/video_link_picker_spec.rb`:**

- Visit `/videos/:id/edit`
- Click `[ + add link ]`
- Type a game name in the picker
- Select a game → link row appears
- Click `[ remove ]` on the link row → action-screen page
- Confirm → link gone; row removed
- Edge: try to add the same game twice → flash error

### Edge cases (full sweep)

- Video linked to 5 games and 2 bundles: detail page lists all 7 links
- Video has no links: edit form shows empty state in the links fieldset
- Game linked to 100 videos: `Game#videos.count` returns 100;
  `Game#hours_of_footage_cached` correctly summed
- Bundle linked to videos that are linked to its members: no double-linking
  enforced (game-level link and bundle-level link on the same video are
  independent records)
- Smuggled IGDB ID: a write tool that takes `game_id` is given an IGDB-side ID
  (not local PK): 404 with clear error
- Multi-user (post-tenant-drop): User A creates a link; User B sees the same
  link. No isolation; the surface is shared.
- A Game with no `cover_image_id` rendered in a shelf: shows the `[ no cover ]`
  placeholder
- A Bundle with no `composite_cover_path` rendered in the grid: shows the
  `[ no cover ]` placeholder
- Large library (10,000 games): `/games` renders within the acceptable budget.
  Implementation agent verifies via index query plans (Postgres EXPLAIN); shelf
  queries should be sub- 100ms with the `release_year` and `played_at` indexes.

## Manual playbook (post-implementation)

1. **Migrate.**
   ```bash
   bin/rails db:migrate
   ```
2. **Populate test data.** Add 5+ games via Phase 14 §1's IGDB flow. Create 2
   bundles via §2's flow.
3. **Visit `/games`.** Confirm bundles shelf at top, then per-genre and
   per-platform shelves, then all-games grid. Confirm horizontal scroll + hover
   captions.
4. **Visit `/bundles`.** Confirm the grid layout. Confirm composite covers
   render.
5. **Edit a video.** Visit `/videos/:id/edit`. Add a link to one of the games
   via the link-picker. Confirm a row appears in the "Linked games / bundles"
   fieldset. Toggle `[ ★ primary ]`. Confirm the badge.
6. **Add a bundle link.** From the same edit form, add a bundle link. Confirm
   both kinds coexist in the fieldset.
7. **Remove a link.** Click `[ remove ]`. Confirm the action- screen page.
   Submit. Confirm the row is gone.
8. **Verify game footage cache.** Open the linked game's show page. Confirm
   `hours_of_footage` reflects the linked video's duration.
9. **MCP smoke.** From Claude Mobile (or curl against `mcp.pitomd.com`):
   - `game_search` with q="zelda" → returns matches
   - `game_add_from_igdb` with confirm=no → preview
   - `game_add_from_igdb` with confirm=yes → game added
   - `video_link_game` with confirm=no → preview
   - `video_link_game` with confirm=yes → link created
10. **Run the suite.**
    ```bash
    bundle exec rspec
    ```

## Cross-stack scope

| Surface         | Status                                                         |
| --------------- | -------------------------------------------------------------- |
| Rails web app   | **In scope.** Primary lane.                                    |
| MCP rack app    | **In scope.** 16 new tools.                                    |
| Doorkeeper      | **Untouched.**                                                 |
| `pito` CLI      | **Skipped.** Work unit 10. Each new tool's CLI parity follows. |
| Astro / website | **N/A.**                                                       |

### Per-domain coverage matrix (per realignment Resolved ambiguity #2)

| Action                      | Web | MCP  | CLI     |
| --------------------------- | --- | ---- | ------- |
| Search games (local)        | yes | yes  | unit 10 |
| Search IGDB                 | yes | no\* | unit 10 |
| Add game from IGDB          | yes | yes  | unit 10 |
| Re-sync game                | yes | yes  | unit 10 |
| Edit local-only game fields | yes | yes  | unit 10 |
| Destroy game                | yes | yes  | unit 10 |
| List bundles                | yes | yes  | unit 10 |
| Show bundle                 | yes | yes  | unit 10 |
| Create bundle               | yes | yes  | unit 10 |
| Edit bundle (name)          | yes | yes  | unit 10 |
| Destroy bundle              | yes | yes  | unit 10 |
| Add bundle member           | yes | yes  | unit 10 |
| Remove bundle member        | yes | yes  | unit 10 |
| Seed bundle from IGDB       | yes | yes  | unit 10 |
| Link video to game          | yes | yes  | unit 10 |
| Link video to bundle        | yes | yes  | unit 10 |
| Unlink                      | yes | yes  | unit 10 |
| Set link primary            | yes | yes  | unit 10 |

\* IGDB live search via MCP would mean exposing the IGDB-search flow as a tool
(`igdb_search`), not just the local Game search. Open Questions #3 covers
whether to ship that. Recommendation: defer to a polish dispatch.

## Copy questions to escalate

1. **Shelf headings.** "bundles" / "recently played" / "<genre>" / "<platform>"
   / "all games" — confirm lowercase per design.
2. **"see all" / "more" link copy** on the right edge of each shelf. "see all"
   vs "more" vs "[ all ]".
3. **Hover caption format.** "Title (2017) ★ 95" vs "Title • 2017 • 95" vs
   "Title — 2017 — 95".
4. **Link picker empty state** ("no games match"). vs "search your library" vs
   "type to filter".
5. **Link primary badge.** `★` vs `[ primary ]` vs `[ ★ ]`.
6. **`[ + add link ]` button on the video edit form.** vs `[ link a game ]` vs
   `[ + game/bundle ]`.
7. **Action-screen copy for video_game_link delete.** Reuse shared Confirmable
   copy or customize?
8. **Bundle-cover-failed fallback inline copy on tiles.** "no cover" vs "—" vs
   blank.
9. **Empty `/games` page copy.** "no games yet. [ search igdb ] to add one."
   (carries through from §1).
10. **Empty `/bundles` page copy.** "no bundles yet. [ + bundle ] to create
    one."
11. **MCP tool descriptions.** Each tool's description string needs to be
    picked. Recommendation: terse, action-oriented ("add a game by its IGDB
    id"), max ~80 chars.
12. **Confirm-yes-no MCP tool error messages.** "missing confirm: pass yes or
    no" vs "set confirm: 'yes' to perform; 'no' to preview".

## Open questions (architect cannot decide)

1. **Pane integration for Games / Bundles.** Recommendation: skip in v1. Games
   and bundles are listing-and-detail pages; no multi-pane workspace. If the
   user wants side-by-side bundle comparison later, a polish dispatch adds it.
   Master agent confirms.

2. **Multiple primaries per video allowed.** Recommendation: yes. The analytics
   layer (Phase 13) decides whether to treat "multiple primaries" as a
   normalization rule or a configuration option. Spec encodes the permissive
   shape. Master agent confirms.

3. **`igdb_search` MCP tool.** Should we expose IGDB live search to Claude
   Mobile, separately from the local-library `game_search`? The use case: a user
   asks Claude on mobile "what's the IGDB ID for Hollow Knight Silksong" and
   wants the answer without leaving Claude. Recommendation: ship it as a thin
   proxy in this phase (`Mcp::Tools::IgdbSearch`); read-only, `app` scope,
   returns IGDB hits with their IDs. Master agent confirms.

4. **Should `video_game_link` carry a `created_by_user_id` column?** ADR 0003
   §"Decision" lists `created_by_user_id` on user-authored rows for an audit
   trail. Links are user- authored. Recommendation: yes, add
   `created_by_user_id` nullable; populate from `Current.user`. Master agent
   confirms.

5. **Does the shelf controller need pagination per shelf, or is "limit 12"
   enough?** Recommendation: limit 12 + a "[ see all ]" link to a per-genre /
   per-platform game listing. The "see all" destination is `/games?genre=<id>`
   or `/games?platform_owned=<id>` — a filtered all-games view. Implementation
   agent decides whether to ship the filter routes here or defer;
   recommendation: ship the filter routes (cheap; one extra query parameter).

6. **Caching shelves.** Each shelf is one query against `games` joined to a
   reference table. With 10k games, a typical install might have 50 genres × 12
   games + 10 platforms × 12 games ≈ 720 game rows fetched per index render.
   Recommendation: skip caching in v1; verify EXPLAIN plans are sub-100ms. If a
   real-world install slows down, add Russian-doll fragment caching keyed on
   `Game.maximum(:updated_at)`. Master agent confirms.

7. **Multi-user concurrency on link create.** Two users add the same link
   concurrently: one wins, the other gets a 422 on the uniqueness violation.
   Recommendation: surface the 422 as a clean flash ("already linked") rather
   than a crash. Spec verifies the flow.

8. **Permissions on `[ remove ]` link rows.** Per ADR 0003, anyone logged in has
   full access. No per-user permissions in v1. Spec asserts this explicitly:
   User B can remove a link created by User A.

9. **`hours_of_footage_cached` recompute on Video destroy.** The Video →
   VideoGameLink CASCADE handles the join row removal, but does the
   after_destroy_commit on VideoGameLink fire? Recommendation: yes (CASCADE
   triggers AR callbacks if `dependent: :destroy` is on the association). Verify
   with a spec.

10. **MCP tool surface for the analytics-side queries** (e.g., "subs gained per
    game"). Out of scope here; lives in Phase 13's analytics MCP catalog
    dispatch. This phase ships the join (data tier) so Phase 13 can query it.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. Shelf headings → Lowercase: `bundles`, `recently played`, `<genre>`,
   `<platform>`, `all games`.
2. See-all link → `[ see all ]` (bracketed).
3. Hover caption format → `Title (2017) ★ 95`.
4. Link picker empty state → `no games match`.
5. Link primary badge → `★` (single star symbol).
6. `[ add link ]` button on video edit form → `[ add link ]` (NOT
   `[ + add link ]`; per bracketed-link memory, no redundant context).
7. video_game_link delete action-screen → reuse shared `Confirmable` copy.
8. Bundle-cover-failed tile fallback → `—` (em dash; matches TTB convention).
9. Empty `/games` page copy → carries through from Spec 01:
   `no games yet. [ search igdb ] to add one.`
10. Empty `/bundles` page copy → carries through from Spec 02:
    `no bundles yet. [ add bundle ] to create one.`
11. MCP tool descriptions → Terse, action-oriented (e.g.,
    `add a game by its IGDB id`). Max ~80 chars. Implementation agent picks
    per-tool descriptions inline; surfaces any non-obvious choices.
12. Confirm-yes-no MCP error → `set confirm: 'yes' to perform; 'no' to preview.`

### Open-question decisions

1. **Pane integration for Games / Bundles.** Skip in v1. Listing- and-detail
   pages, no multi-pane workspace.
2. **Multiple primaries per video.** Yes (permissive shape). Phase 13 analytics
   decides whether multi-primary is normalized or flagged.
3. **`igdb_search` MCP tool.** Ship it. Read-only thin proxy over IGDB live
   search. `app` scope. Returns IGDB hits with their IDs.
4. **`created_by_user_id` on `video_game_links`.** Yes, add nullable column;
   populate from `Current.user`. Per ADR 0003 audit-trail posture.
5. **Pagination per shelf.** Limit 12 + `[ see all ]` to a filter route
   (`/games?genre=<id>` or `/games?platform_owned=<id>`). Ship the filter routes
   in this phase.
6. **Shelf caching.** Skip in v1. Verify EXPLAIN plans are sub-100ms. If slow at
   scale, add Russian-doll fragment caching keyed on `Game.maximum(:updated_at)`
   later.
7. **Multi-user concurrency on link create.** Surface uniqueness 422 as a clean
   flash (`already linked`). Spec verifies the flow.
8. **Permissions on `[ remove ]`.** Per ADR 0003: anyone logged in has full
   access. Spec asserts: User B can remove a link created by User A.
9. **`hours_of_footage_cached` recompute on Video destroy.** Yes, the
   after_destroy_commit on `VideoGameLink` fires through the CASCADE if
   `dependent: :destroy` is set on the association. Spec verifies via test.
10. **MCP analytics tools** (e.g., "subs gained per game"). Out of scope. Lives
    in Phase 13's analytics MCP catalog dispatch (future).

## Implementation lane assignment

Two lanes:

1. **rails-impl** (or `pito-rails-impl`) — schema, models, controllers, views,
   Stimulus, system specs.
2. **mcp-impl** (or `pito-mcp-impl`) — every new MCP tool + tool specs.
   Coordinates with rails-impl on shared model methods.

The two lanes can run in parallel after the schema migration lands. Master agent
dispatches rails-impl first (it owns the migration), then mcp-impl in parallel
with the rails-impl post-migration work.

Lanes touch:

- rails-impl: `db/migrate/`, `db/schema.rb`, `app/models/`, `app/controllers/`,
  `app/views/`, `app/javascript/controllers/`, `app/lib/confirmable.rb`,
  `config/routes.rb`, `spec/models/`, `spec/requests/`, `spec/system/`
- mcp-impl: `app/mcp/tools/`, `app/mcp/registry.rb`, `spec/mcp/tools/`

## Reviewer checkpoints (post-implementation)

1. `bundle exec rspec` — green.
2. `bundle exec rubocop` — green or no new violations.
3. `bundle exec brakeman -q` — green or no new findings.
4. `git grep 'tenant\|Tenant' app/models/video_game_link.rb app/mcp/tools/{game_,bundle_,video_link_}*`
   → zero matches.
5. `git grep 'true\|false' app/mcp/tools/{game_,bundle_, video_link_}*` for
   boolean handling — verify each one accepts "yes" / "no" strings on the wire
   and converts internally.
6. Manual playbook §1-§10.
7. MCP tool catalog count delta logged in `log.md`. Expected: 16 new tools (+
   optional `igdb_search` per Open Questions #3).
8. Spec file count delta logged in `log.md`. Expected: ~25 new spec files
   (model, request, system, MCP).
9. Production-style multi-user check: log in as User A, create a link; log out;
   log in as User B (second seeded user, if the Phase 8 reseed established one —
   otherwise create one in the manual playbook); confirm User B sees and can
   remove User A's link.
