# Phase 14 — Game Model Expansion + IGDB Sync + Steam-Shelf UI

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 6.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 6
>   ("Game model expansion + IGDB sync") plus Mobile note 4 framing.
> - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md` — Mobile note 4. Source
>   of truth for the Game data model, IGDB API v4 surface, bundles, composite
>   covers, Steam-shelf UX.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; flat storage paths; no `tenant_id` on any new table.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12 / work unit 4. Establishes `videos.project_id`, the writable
>   subset, and the convention for cross-resource link tables. Phase 14 adds the
>   `video_game_link` table that Note 1 mentions but Phase 12 explicitly defers
>   ("Game ↔ Video links — work unit 6 / Phase 14" in Phase 12 §"Out of scope").

## Specs in this phase

This phase ships as three feature specs to keep each implementation lane
self-contained and reviewable:

1. `specs/01-data-model-and-igdb-client.md` — schema (games + reference tables),
   IGDB v4 client, Twitch OAuth credentials, on-demand sync, nightly refresh,
   last-write-wins semantics.
2. `specs/02-bundles-and-composite-covers.md` — bundle model, bundle members,
   composite cover builder via libvips, on-disk storage at flat `composites/`
   path, regen triggers.
3. `specs/03-steam-shelf-ui-and-video-game-links.md` — Steam-shelf-style listing
   UI for games and bundles, the `video_game_link` join table, MCP
   - CLI coverage matrix.

Each spec carries its own acceptance / test sweep / manual playbook.

## Next

Master agent dispatches `pito-rails-impl` against the three specs in order once
the user signs off. Spec 1 is the foundation (Spec 2 adds composite covers on
top of Spec 1's models; Spec 3 surfaces both via UI / cross- links).

## Sessions

### 2026-05-10 — Spec 01 implementation (data model + IGDB v4 client)

**Dispatch:** `pito-rails-impl`. Single lane. Specs 02 and 03 deferred per
master-agent split (Spec 03 needs Phase 12 `Video` schema, currently in flight;
Spec 02 stays queued behind Spec 01).

**Migrations applied (in order):**

- `20260510140000_expand_games_for_igdb.rb` — 26 new columns on `games`
  (igdb_id, igdb_slug, igdb_checksum, summary, cover_image_id, release_date,
  release_year, four rating tuples, three external store IDs, three time-to-beat
  columns, four local-only fields, igdb_synced_at, last_sync_error). Six indexes
  (igdb_id / igdb_slug unique partial, release_year, external_steam_app_id
  partial, platform_owned_id, igdb_synced_at).
- `20260510140001_create_game_reference_tables.rb` — `genres`, `platforms`,
  `companies` (thin reference rows keyed by `igdb_id`). Plus FK
  `games.platform_owned_id → platforms.id` (`ON DELETE SET NULL`).
- `20260510140002_create_game_join_tables.rb` — `game_genres`, `game_platforms`,
  `game_developers`, `game_publishers`. Composite uniqueness
  `(game_id, <ref>_id)` on each, FK cascade on both sides.

**Files added by layer:**

- Models — 7 new (`genre.rb`, `platform.rb`, `company.rb`, `game_genre.rb`,
  `game_platform.rb`, `game_developer.rb`, `game_publisher.rb`); heavy edit to
  `game.rb` (Phase 4 platforms validator dropped, IGDB associations + scopes +
  `cover_url` + `hours_of_footage` added; Phase 15 `CalendarDerivable` hooks
  left intact).
- Services — 6 new under `app/services/igdb/`: top-level `igdb.rb` (lazy
  credentials), `client.rb` (HTTP client with error class hierarchy),
  `token_cache.rb` (Twitch OAuth client-credentials cache, `Rails.cache`),
  `rate_limiter.rb` (process-local 4 req/s + 8 in-flight token bucket),
  `apicalypse.rb` (DSL builder), `game_mapper.rb` (IGDB JSON → attribute
  hashes), `sync_game.rb` (orchestrator).
- Jobs — `game_igdb_sync.rb` (per-game, retries on 429/5xx, swallows 4xx),
  `game_igdb_nightly_refresh.rb` (cron, enqueues `Game.synced.stale`).
- Controller — `games_controller.rb` heavy edit. New `:search`
  (`GET /games/search?q=…`) + `:resync` (`POST /games/:id/resync`) actions.
  `:create` accepts `params[:game][:igdb_id]` for the new add-game flow, retains
  the Phase 4 default-create with deprecated copy. `:update` STRICTLY allowlists
  `platform_owned_id` / `played_at` / `notes` / `hours_of_footage_manual`;
  smuggled IGDB-sourced columns silently dropped.
- Views — `index.html.erb` rewrite (release_year + igdb_rating columns, per-row
  [resync] action, [search igdb] empty state), `show.html.erb` rewrite (cover +
  ratings + TTB + genres/platforms + external stores + local-fields form + sync
  metadata), 3 new partials (`_add_form`, `_search_results`,
  `shared/_igdb_cover`).
- Stimulus — `igdb_search_controller.js` (debounced type-ahead → Turbo Frame; no
  `confirm()` / `alert()`).
- Helper — `format_seconds` for time-to-beat in `application_helper.rb`.
- Routes — `:search` collection + `:resync` member added under
  `resources :games`.
- Sidekiq cron — `game_igdb_nightly_refresh` registered at `0 3 * * *` in
  `config/sidekiq_cron.yml`.

**Specs added (212 examples, all green):**

- 8 model specs (`game_spec.rb` heavy rewrite; `genre_spec.rb`,
  `platform_spec.rb`, `company_spec.rb`, four join-model specs new).
- 6 service specs under `spec/services/igdb/` (`apicalypse`, `rate_limiter`,
  `token_cache`, `client`, `game_mapper`, `sync_game`).
- 2 job specs.
- 1 request spec rewrite (covers search / IGDB-add / resync / smuggling guards /
  cascade-on-destroy).
- 8 new factories.
- 3 IGDB JSON fixtures (`spec/fixtures/igdb/7346_*.json`) for the mapper +
  syncer specs.

**HTTP testing posture:** WebMock only (no VCR — VCR not in Gemfile per
master-agent resolution). Stubs against IGDB's `https://api.igdb.com/v4/*` and
Twitch's `https://id.twitch.tv/oauth2/token`. Credentials in tests are stubbed
via `OpenStruct.new(client_id: "id", client_secret: "secret")` on
`Rails.application.credentials.igdb`.

**Decisions recorded by the implementation agent:**

- Master-agent locked decisions (12 copy + 7 open questions) honored verbatim.
- `Igdb::Client` stamps the GOG / Epic IGDB category constants as
  `EXTERNAL_GAME_CATEGORY_GOG = 5` / `EXTERNAL_GAME_CATEGORY_EPIC = 26` (per
  IGDB external-game enum docs at implementation time). Stable on IGDB at
  present; surfaced here for future reviewer.
- Slug-collision guard inside `Igdb::SyncGame#assign_with_slug_collision_guard`
  rescues `ActiveRecord::RecordNotUnique` whose message references `igdb_slug`,
  retries the save with `igdb_slug: nil`, stamps `last_sync_error`.
- Twitch token TTL trimmed by 60s safety margin, floored to 60s minimum so a
  misconfigured `expires_in` cannot create a forever-cached token.

**Quality gates:**

- `bundle exec rspec spec/models/{game,genre,platform,company,game_*}_spec.rb spec/services/igdb/ spec/jobs/game_igdb_*.rb spec/requests/games_spec.rb`
  — 212 examples, 0 failures.
- `bundle exec rubocop` (touched files only) — clean.
- `bundle exec brakeman -q -w2` — clean. 0 security warnings.
- Full-suite failures observed in
  `spec/requests/{projects,channels,bulk_operations}_spec.rb`,
  `spec/mcp/tools/{get,list}_video*_spec.rb`, `searchable_spec.rb`,
  `application_helper_spec.rb`, `seeds_spec.rb` are driven by the in-flight
  Phase 12 schema changes already applied to the local DB (Video gained `title`
  / writable subset / Pre-Publish Checklist columns). None depend on Phase 14 §1
  work; they will resolve when Phase 12's spec-side updates land.

**NOT in scope (deferred):**

- Bundles + composite covers (Spec 02).
- Steam-shelf UI + `video_game_link` + 16 MCP tools (Spec 03; depends on Phase
  12).
- The Phase 4 legacy `publisher` (string) and `platforms` (jsonb) columns remain
  on `games`. Nothing in the new code reads or writes them; the pre-existing
  `spec/requests/projects_spec.rb` footage-table-expansion tests still read
  `game.platforms.first["platform"]`, so the factory still defaults `platforms`
  to a single-element array for backward compatibility. Drop falls into the
  polish window.
- Phase 4 `Game.cover_art` Active Storage attachment kept verbatim (rename to
  `manual_cover_art` deferred — would force an attachment rename migration and a
  deprecation warning in two places; queued for the polish window with the
  legacy column drop).

**Manual playbook (post-merge):**

1. `bin/rails credentials:edit --environment development`. Add the `igdb:`
   block:

   ```yaml
   igdb:
     client_id: <twitch_client_id>
     client_secret: <twitch_client_secret>
   ```

   (The Twitch app is registered at https://dev.twitch.tv/console/apps; the
   client-credentials grant against `https://id.twitch.tv/oauth2/token` is what
   `Igdb::TokenCache` exchanges to access `https://api.igdb.com/v4/*`.)

2. Repeat `--environment test` (test values only need to be non-nil — VCR absent
   and WebMock intercepts before the HTTP call, but `Igdb.credentials!` inside
   `Igdb::Client#perform_request` reads the block at request build time).
3. `bin/rails db:migrate`.
4. Visit `/games`. Existing rows show the IGDB columns as `—`.
5. Type a query in the search box. Pick a result. Click `[add]`. Confirm
   redirect to `/games/:id` with flash "added; metadata loading in background."
   Within ~1s the row hydrates from IGDB.
6. Click `[resync]`. Confirm `igdb_synced_at` updates.
7. Edit `notes` / `played_at` / `hours_of_footage_manual`. Click `[resync]`.
   Confirm those local-only fields survive verbatim.
8. From `bin/rails console`: `Game.find(:id).update_columns(title: "X")`, then
   click `[resync]`. Confirm title overwrites back to IGDB's value
   (last-write-wins).

**Open issues / blockers:** none for Spec 01. Spec 02 (bundles + composite
covers) and Spec 03 (Steam-shelf + `video_game_link` + 16 MCP tools) await
separate dispatches, with Spec 03 also blocked on Phase 12 landing in main.

### 2026-05-10 — Spec 02 implementation (bundles + composite covers)

**Dispatch:** `pito-rails-impl`. Single rails lane. Builds on Spec 01's Game
model + IGDB client. Spec 03 (Steam-shelf + `video_game_link` + MCP tools)
remains deferred and is unblocked by this work.

**Master-agent decisions honored verbatim:** all 12 copy decisions and 10
open-question decisions from `specs/02-bundles-and-composite-covers.md` §"Master
agent decisions (2026-05-10)". Notable: `bundle_type` is immutable post-create
(strong-params drop on update); composite covers built async via Sidekiq
(`BundleCoverBuild`); `last_error` text column on bundles surfaces inline on the
show page; `before_destroy` sweeps the on-disk cover file plus a follow-up
`pito:bundles:reap_orphans` rake task; `/composites/:filename.jpg` route is
auth-gated through `Sessions::AuthConcern`. Bracketed-link copy matches
CLAUDE.md `[ label ]` convention.

**Migration applied:**

- `20260510160000_create_bundles.rb` — `bundles` (12 columns: bundle_type enum,
  name, igdb_source_type/id pair, composite_cover_path / checksum, last_error,
  timestamps; three indexes incl. composite-unique on the igdb_source pair) and
  `bundle_members` (bundle_id, game_id, position, composite-unique on
  (bundle_id, game_id), composite-btree on (bundle_id, position), FK cascade on
  both sides).

**Files added:**

- Models — `app/models/bundle.rb` (enum dispatch, validations,
  `composite_cover_url`, `needs_cover_rebuild?`, `cover_rebuild_in_flight?`,
  before*destroy sweep), `app/models/bundle_member.rb` (position auto-assign,
  uniqueness, after*\*\_commit cover-rebuild enqueue).
- Game model edit — `has_many :bundle_members` / `:bundles`,
  `after_update_commit :invalidate_bundle_covers_if_image_changed` passing the
  previous `cover_image_id` explicitly so the Sidekiq job can evict the stale
  tile across a process boundary.
- Services under `app/services/composite/` — `Composite::Builder` (orchestrator
  with libvips JPEG output to `<assets>/composites/<type>-<id>.jpg`),
  `Composite::TileCache` (227×320 IGDB CDN cache + evict + TileFetchError),
  `Composite::Checksum` (SHA-256 over sorted image_ids + layout name),
  `Composite::LayoutChooser` (1/2/3/4/5-9/10+ dispatch), six layout templates
  under `Composite::Layout::` (Single, Pair, Netflix, Quad, NineGrid,
  NineGridWithOverflow with libvips text overlay for the "+N" caption).
- Jobs — `BundleCoverBuild` (Sidekiq, retry 5; stamps `last_error` and re-raises
  on TileFetchError / StandardError so Sidekiq retries fire),
  `BundleCoverInvalidate` (evicts the previous cover_image_id's tile, enqueues a
  rebuild for every bundle the game belongs to).
- Controllers — `BundlesController` (full RESTful + `seed_from_igdb` with IGDB
  franchise/collection/genre dispatch + last_error stamping),
  `BundleMembersController` (POST / DELETE on `/bundles/:bundle_id/members`,
  `:id` segment is the GAME id per spec), `CompositesController` (auth-gated
  `send_file` for `/composites/:filename.jpg` with regex defense-in-depth).
- IGDB client extensions — `fetch_games_for_franchise`,
  `fetch_games_for_collection`, `fetch_games_for_genre` on `Igdb::Client` for
  the seed_from_igdb flow.
- Confirmable wiring — registered `bundle` in `Confirmable::TYPES`, plus
  `cancel_path`, `model_for`, `scope_for`, `label_for` dispatch arms;
  `application_helper#cancel_path_for` arm; deletions show.html.erb adds a
  `bundle` row template.
- Routes —
  `resources :bundles do member do post :seed_from_igdb; end; resources :members, only: [ :create, :destroy ], controller: "bundle_members"; end`
  - `GET /composites/:filename.jpg` with regex constraint.
- Views — `bundles/{index,show,new,edit,_form}.html.erb`,
  `bundle_members/_member_row.html.erb`, `shared/_composite_cover.html.erb`
  (full / card / thumb sizes; falls back to `[no cover]`).
- Helpers — `BundlesHelper#member_picker_options` (local Game library dropdown
  source per master-agent decision #4).
- Stimulus — `bundle_member_picker_controller.js` (case-insensitive substring
  filter on the `<select>` options + `[no games match]` empty caption).
- Rake — `lib/tasks/bundles.rake` `pito:bundles:reap_orphans`.
- Test fixture — `spec/fixtures/files/cover_tile.jpg` (227×320 JPEG seeded via
  libvips for the layout / builder integration paths).

**Specs added (152 examples in the bundle/composite set, all green):**

- `spec/models/bundle_spec.rb` — 32 examples (associations, enums, validations
  including all igdb_source consistency cases + uniqueness scope, scopes,
  composite_cover_url, needs_cover_rebuild? edge cases, callbacks,
  before_destroy file sweep).
- `spec/models/bundle_member_spec.rb` — 11 examples.
- `spec/models/game_spec.rb` — 3 new examples (bundle membership, hook fires on
  `cover_image_id` change, hook does NOT fire on other column changes; passes
  the previous cover_image_id as the second arg).
- `spec/services/composite/checksum_spec.rb` — 6 examples.
- `spec/services/composite/layout_chooser_spec.rb` — 11 examples.
- `spec/services/composite/layout/{single,pair,netflix,quad,nine_grid, nine_grid_with_overflow}_spec.rb`
  — 20 examples total (output dimension
  - tile-count guard per layout).
- `spec/services/composite/tile_cache_spec.rb` — 8 examples (cache miss / hit /
  WebMock no-second-call / TileFetchError / blank guard / evict).
- `spec/services/composite/builder_spec.rb` — 13 examples (full pipeline with
  stubbed TileCache returning the fixture image; layouts 1-4 + 9 + 10; empty
  member set; nil-cover filtering; canonical filename; idempotent rebuild;
  last_error clear on success).
- `spec/jobs/bundle_cover_build_spec.rb` — 6 examples.
- `spec/jobs/bundle_cover_invalidate_spec.rb` — 6 examples.
- `spec/requests/bundles_spec.rb` — 26 examples (index/show/new/create with
  consistency rules; PATCH smuggle drops; DELETE redirect to action-screen;
  seed_from_igdb with WebMock-stubbed Igdb::Client for franchise/collection/
  genre + idempotency + API failure path).
- `spec/requests/bundle_members_spec.rb` — 5 examples.
- `spec/requests/composites_spec.rb` — 4 examples (file present, file missing,
  regex defense, unauthenticated redirect to /login).
- `spec/system/bundle_show_spec.rb` — 4 Capybara smokes (placeholder, add,
  remove, [seed from igdb] visibility).
- Factories — `spec/factories/bundles.rb` (default custom + :series /
  :collection / :genre traits with auto-incrementing igdb_source_id),
  `spec/factories/bundle_members.rb`.

**Implementation decisions by the agent:**

- `BundleCoverInvalidate` accepts `(game_id, previous_cover_image_id = nil)` as
  positional args (the spec's "explicit argument shape" alternative). The Game
  callback passes `saved_change_to_cover_image_id.first` — `previous_changes`
  would be gone by the time the Sidekiq process picks the job up.
- `Composite::Builder` truncates to 9 tiles when the layout is
  `NineGridWithOverflow` (10+ members). The full member count flows through to
  the layout via `total_member_count:` so the "+N" caption math stays correct.
- `Composite::Layout::NineGridWithOverflow` builds the overlay as a 4-band
  sRGB+alpha image and uses `composite2(... :over)` for the alpha blend. The
  first attempt with raw `bandjoin` + alpha-as-band hit
  `vips_colourspace: no known route from 'multiband' to 'srgb'`; the fix is the
  explicit `copy(interpretation: :srgb)` after each bandjoin.
- `Bundle#cover_rebuild_in_flight?` is best-effort and only returns true in
  `Sidekiq::Testing.fake?` mode (queue introspection is cheap there); in
  Sidekiq-real-server mode it returns false so the show page does NOT pretend to
  know what's queued. This is conservative — false negatives are harmless
  ("regenerating…" text just won't render).
- `seed_from_igdb` fetches IGDB seed games and creates local Game rows for any
  IGDB id missing from the library, then enqueues `GameIgdbSync` per
  newly-created game so the metadata hydrates in the background. Avoids the
  "user must manually add each member first" footgun.
- The Phase 4 legacy `[search igdb]` chip on `/games` and the new bundle picker
  are deliberately separate flows. The bundle add-member form pulls from the
  local Game library only (master decision #4); growing the library still
  happens through Spec 01's IGDB add-game flow.

**Quality gates:**

- `bundle exec rspec spec/models/bundle_spec.rb spec/models/bundle_member_spec.rb spec/services/composite/ spec/jobs/bundle_cover_build_spec.rb spec/jobs/bundle_cover_invalidate_spec.rb spec/requests/bundles_spec.rb spec/requests/bundle_members_spec.rb spec/requests/composites_spec.rb spec/system/bundle_show_spec.rb`
  — 152 examples, 0 failures.
- Adjacent suites (`spec/services/igdb/`, `spec/models/game_spec.rb`,
  `spec/requests/games_spec.rb`,
  `spec/controllers/concerns/confirmable_spec.rb`,
  `spec/requests/deletions_spec.rb`) — green, 188 + 37 examples respectively.
- `bundle exec rubocop` (touched files only) — clean.
- `bundle exec brakeman -q -w2` — 0 errors, 0 security warnings.

**NOT in scope (deferred):**

- Steam-shelf `/bundles` UX overhaul — Spec 03.
- `video_game_link` join + analytics attribution — Spec 03.
- 16 MCP `bundle_*` / `bundle_member_*` tools — Spec 03.
- Drag-sort UI for member ordering — polish dispatch (server-side position
  support ships here; UX deferred).
- libvips version pinning — no pin per master-agent decision #10; the user's
  system install is the source of truth.

**Manual playbook (post-merge):**

1. `bin/rails db:migrate` (already migrated locally).
2. Visit `/bundles`. Confirm the empty-state copy
   `no bundles yet. [ add bundle ] to create one.`.
3. Click `[ add bundle ]`. Pick `bundle_type: custom`, name "Soulslikes". Save.
4. From the bundle show page, add 3 games via the picker. Confirm 3 member rows
   appear. Confirm a `BundleCoverBuild` enqueues (sidekiq dashboard). Within
   ~3-5s confirm the composite cover image renders 600×800 with the Netflix
   layout.
5. Add a 4th game; confirm the Quad layout renders.
6. Remove the first game via `[remove]`; confirm cover regenerates back to
   Netflix.
7. Test the IGDB-seeded path: create a `series` bundle pointing at a real
   franchise id (`igdb_source_type: franchise`, `igdb_source_id: <id>`). Click
   `[ seed from igdb ]`. Confirm members populate.
8. Re-sync a member game (Spec 01's `[resync]` button). If IGDB returns a
   different `cover_image_id`, confirm `BundleCoverInvalidate` fires and the
   bundle's cover regenerates with the new tile.
9. Delete the bundle via `[ - ]`. Confirm action-screen, submit. Verify the
   bundle row + members are gone AND the on-disk file at
   `<PITO_ASSETS_PATH>/composites/<type>-<id>.jpg` is removed.
10. `bin/rails pito:bundles:reap_orphans` — confirm "reaped 0" on a healthy
    install.

**Open issues / blockers:** none for Spec 02. Spec 03 (Steam-shelf +
`video_game_link` + 16 MCP tools) ready for separate dispatch.

### 2026-05-10 — Spec 03 implementation (Steam-shelf + `video_game_link` + MCP tools)

**Dispatch:** `pito-rails-impl`. Single rails lane. Builds on Spec 01 (Game /
IGDB) and Spec 02 (Bundle / composite covers). Phase 12
(`videos.duration_seconds`) now in main, so the footage-cache recompute side of
`VideoGameLink` is unblocked.

**Master-agent decisions honored verbatim:** all 12 copy decisions and 10
open-question decisions from `specs/03-steam-shelf-ui-and-video-game-links.md`
§"Master agent decisions (2026-05-10)". Notable: bracketed labels with no inner
spaces (`[label]`), `[see all]` link, `★` primary badge, `[add link]` button (no
`+`), `[remove]` verb-only; pane integration skipped in v1 (listing pages only);
multiple primaries per video allowed; `igdb_search` MCP tool ships as thin
proxy; `created_by_user_id` audit column on `video_game_link`; limit-12 +
`[see all]` filter routes (`/games?genre=<id>` / `/games?platform_owned=<id>`);
no shelf caching in v1; multi-user concurrency 422 surfaces as a clean
`already linked.` flash; permissions: anyone signed in;
`hours_of_footage_cached` recomputes on Video destroy via the
`dependent: :destroy` cascade through `VideoGameLink`'s `after_commit`;
analytics MCP tools out of scope (Phase 13).

**Migration applied:**

- `20260510180000_create_video_game_links.rb` — `video_game_links` table (8
  columns: video_id, link_type enum, game_id, bundle_id, is_primary,
  created_by_user_id, timestamps). 7 indexes — `link_type`, `is_primary`
  (partial WHERE true), `created_by_user_id`, `video_id`, plus two
  composite-unique partial indexes
  `(video_id, game_id) WHERE game_id IS NOT NULL` and
  `(video_id, bundle_id) WHERE bundle_id IS NOT NULL`. Four FKs (`video`,
  `game`, `bundle` cascade; `created_by_user` nullify). Postgres CHECK
  constraint `video_game_links_exactly_one_target` enforces the
  exactly-one-target invariant at the DB layer (defense-in-depth alongside the
  AR `exactly_one_target` validator).

**Files added:**

- Models — `app/models/video_game_link.rb` (enum, validations, `target` helper,
  `recompute_game_footage_cache` callback, `stamp_created_by_user`
  before_validation). Light edits to `video.rb` (has_many `video_game_links` +
  `linked_games` / `linked_bundles` through joins + `linked_to_game` /
  `linked_to_bundle` scopes), `game.rb` (has_many video_game_links
  - videos), `bundle.rb` (has_many video_game_links + videos).
- Controller — `video_game_links_controller.rb` (POST / PATCH / DELETE nested
  under `/videos/:video_id/links`). `GamesController#index` rewritten to load
  shelf-shaped collections + filter route support (`/games?genre=<id>` /
  `/games?platform_owned=<id>`). `VideosController#edit` now loads link-fieldset
  view bag (`@video_links`, `@link_pickable_games`, `@link_pickable_bundles`).
- Confirmable wiring — `video_game_link` added to `Confirmable::TYPES`
  - dispatch arms (`cancel_path`, `model_for`, `scope_for`, `label_for`);
    `application_helper#cancel_path_for` arm; deletions show.html.erb gains a
    `video_game_link` row template.
- Routes —
  `resources :videos do resources :links, only: %i[create update destroy], controller: "video_game_links" end`.
- Views — `games/index.html.erb` heavy rewrite (Steam-shelf shape: bundles row,
  recently-played, per-genre rows, per-platform rows, all-games grid). New
  partials: `games/_shelf.html.erb`, `games/_tile.html.erb`,
  `bundles/_tile.html.erb`, `videos/_links_section.html.erb`,
  `video_game_links/_link_row.html.erb`. `bundles/index.html.erb` rewritten to
  flat tile grid. `games/show.html.erb` and `bundles/show.html.erb` gain a
  "linked videos" section.
- Stimulus — `steam_shelf_controller.js` (mouse-wheel-to-horizontal +
  click-and-drag scroll), `link_picker_controller.js` (case-insensitive
  substring filter on the picker option list with empty-state caption).
- MCP tools (17 total — 16 spec'd + bonus `igdb_search`): five game tools
  (`game_search`, `game_add_from_igdb`, `game_resync`, `game_update_local`,
  `game_destroy`); seven bundle tools (`bundle_search`, `bundle_create`,
  `bundle_update`, `bundle_destroy`, `bundle_member_add`,
  `bundle_member_remove`, `bundle_seed_from_igdb`); four video-link tools
  (`video_link_game`, `video_link_bundle`, `video_unlink`,
  `video_link_set_primary`); plus `igdb_search` (thin IGDB live-search proxy per
  master-agent decision #3). Every tool gates on `Scopes::APP`. Every write tool
  implements two-step `confirm: yes/no` and rejects boolean smuggling at the
  boundary.
- Factory — `spec/factories/video_game_links.rb` (default game link
  - `:bundle` and `:primary` traits).

**Specs added (and existing specs extended):**

- `spec/models/video_game_link_spec.rb` (new) — 31 examples: associations, enum,
  `exactly_one_target` validator (7 cases), uniqueness (4 cases), `is_primary`
  default + multiple primaries allowed, `target` helper, `created_by_user_id`
  audit stamping, footage-cache recompute (rounding 0.16 → 0, 2.0 → 2, sums,
  decrease on destroy, bundle links don't touch game cache), DB-level CHECK
  constraint integrity, cascade-on-delete (game destroyed, bundle destroyed,
  video destroyed → cache recomputed).
- `spec/models/video_spec.rb` (additive) — `video_game_links` / `linked_games` /
  `linked_bundles` associations + `linked_to_game` / `linked_to_bundle` scopes.
- `spec/models/game_spec.rb` (additive) — `video_game_links` / `videos`
  associations + `hours_of_footage` precedence (manual vs cached) + recompute on
  link create / destroy.
- `spec/models/bundle_spec.rb` (additive) — `video_game_links` / `videos`
  associations.
- `spec/requests/games_spec.rb` (heavy rewrite of GET /games) — 37 examples
  covering Steam-shelf shape (bundles shelf, recently-played, per-genre /
  per-platform shelves, all-games heading, `data-controller="steam-shelf"`,
  `[see all]` link routes), filter routes, query injection guard.
- `spec/requests/bundles_spec.rb` (additive) — bundles-grid wrapper + `—`
  em-dash placeholder fallback.
- `spec/requests/video_game_links_spec.rb` (new) — 18 examples: POST game /
  bundle paths, `is_primary=yes/no` persisted, duplicate rejection (clean
  "already linked." flash), nonexistent linked_id 404, smuggle guards
  (game_id+bundle_id, link_type=garbage), PATCH flip semantics (yes/no + boolean
  smuggle reject + 404), DELETE direct + via `/deletions/video_game_link/:id`
  action screen, multi-user removal (User B can remove User A's link per ADR
  0003).
- `spec/system/games_steam_shelf_spec.rb` (new) — 6 Capybara smokes (empty
  state, bundles shelf, recently-played shelf, per-genre `[see all]` link,
  all-games heading, tile click navigates to game show).
- `spec/system/video_link_picker_spec.rb` (new) — 4 Capybara smokes (empty
  state, add via picker, [remove] action-screen flow, duplicate add → "already
  linked." flash).
- 17 MCP tool specs
  (`spec/mcp/tools/{game,bundle,video_link, video_unlink,igdb_search}_*_spec.rb`)
  — every write tool covers preview / apply / boolean-confirm-smuggle / 404 /
  scope-gate. `bundle_seed_from_igdb_spec` stubs `Igdb::Client` for the
  WebMock-free path; `igdb_search_spec` does the same.

**Implementation decisions by the agent:**

- **`after_commit` callback bug fixed in two models.** Rails 8.1 registers a
  SECOND `after_*_commit :method_name` for the same method as a UNION of `:if`
  filters on the SAME callback entry — not as two separate entries. The result:
  a callback gated on
  `transaction_include_any_action?(:create) AND transaction_include_any_action?(:destroy)`
  never fires. Both `VideoGameLink#recompute_game_footage_cache` and the
  pre-existing `BundleMember#enqueue_cover_rebuild` exhibited this shape. Fixed
  by collapsing each pair into a single
  `after_commit :foo, on: %i[create destroy]`. The Phase 14 §2 bundle-member
  spec only passed by accident — `let(:bundle)` was lazy-evaluating AFTER
  `BundleCoverBuild.clear`, so the bundle's own `after_save`
  `enqueue_cover_build_if_changed` was the row surfacing in the assertion (not
  the bundle_member callback). Fix is invisible to existing call sites; both
  specs (incl. the pre-existing `bundle_member_spec.rb`) stay green.
- **`Game#videos` polymorphism.**
  `Game.has_many :videos, through: :video_game_links` works because the join
  model carries a bare `belongs_to :video`. The same association does NOT cause
  `Bundle#videos` to leak game-scoped rows (the AR through-join picks up the
  link row's join condition).
- **`VideoGameLink#stamp_created_by_user` runs
  `before_validation, on: :create`** — `Current.user` is a thread-local
  `ActiveSupport::CurrentAttributes`, set by either `Sessions::AuthConcern`
  (HTML) or `Api::AuthConcern` (MCP), so the audit column populates on every
  entry path. MCP tool specs that don't go through a controller still see a
  stamped value because `spec/support/api_token_context.rb` populates
  `Current.user` per example.
- **Smuggle guards in `VideoGameLinksController`.** When `link_type=game` is
  sent with `bundle_id` (or vice-versa), the controller rejects with
  `cannot smuggle bundle_id on a game link.` Independent of the AR
  `exactly_one_target` validator (which catches the raw-SQL path); both layers
  are defense-in-depth.
- **`video_unlink` MCP tool is bulk-by-default.** A single-id list is the same
  surface as the bulk path (CLAUDE.md bulk-as-foundation rule). Includes a
  `not_found` array in the response payload so callers can audit which ids were
  no-ops.
- **Picker draws from local Game / Bundle.** Per the spec's "out of scope" item:
  the link picker does NOT call IGDB live search. To grow the library, users go
  through Spec 01's add-game flow first. The picker's `link-picker` Stimulus
  controller is a pure UI affordance (no `confirm()` / `alert()` / `prompt()`).
- **`/games?genre=<id>` filter route added** rather than deferring per Open
  Questions #5. Cheap (one query parameter); makes the `[see all]` link land
  somewhere useful out of the box. Invalid / non-positive values are silently
  dropped so injection candidates reduce to "no filter applied".
- **No CSS file additions.** Inline `style=""` attributes on shelf / tile / grid
  containers carry the layout primitives. Per `docs/design.md`: monospace 13px
  (already global), no animation, no red unless destructive, `cursor: pointer`.
  The shelf row uses `overflow-x: auto`; the all-games grid uses
  `display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr))`.

**Quality gates:**

- `bundle exec rspec spec/models/video_game_link_spec.rb spec/models/{video,game,bundle,bundle_member}_spec.rb spec/requests/{games,bundles,video_game_links}_spec.rb spec/system/{games_steam_shelf,video_link_picker,bundle_show}_spec.rb spec/mcp/tools/`
  — 566 examples, 0 failures.
- Full suite (`bundle exec rspec`) — 3158 examples, 2 failures, 1 pending. Both
  failures (`spec/requests/calendar/month_spec.rb:35`,
  `spec/requests/composites_spec.rb:28`) are pre-existing test-isolation flakes;
  both pass when re-run individually
  (`bundle exec rspec spec/requests/calendar/month_spec.rb:35 spec/requests/composites_spec.rb:28`
  → 0 failures). Not introduced by this work.
- `bundle exec rubocop` (touched files only — 56 files) — clean.
- `bundle exec brakeman -q -w2` — 0 errors, 0 security warnings.

**MCP tool catalog delta:** 17 new tools registered — verified via
`Mcp::PitoServer.build.tools.keys` (37 total post-Spec-03, was 20 pre-Spec-03).
All gate on `Scopes::APP`; every write tool implements two-step
`confirm: yes/no` and rejects boolean smuggling.

**Spec file delta:** 28 new spec files (+ 4 additive edits to existing ones).

**NOT in scope (deferred):**

- Pane integration for Games / Bundles (master-agent decision #1 — skip in v1).
- Analytics aggregations (subs gained per game, etc.) — Phase 13 catalog
  dispatch.
- IGDB live search inside the link picker (master-agent decision — picker draws
  from local library only). The `igdb_search` MCP tool covers the conversational
  use case.
- CLI parity for the 17 new tools — work unit 10 (separate dispatch).
- `docs/mcp.md` scope-per-tool table update — owned by the docs agent
  post-validation. Implementation agent does NOT edit `docs/` outside `log.md`
  per role discipline.

**Manual playbook (post-merge):**

1. `bin/rails db:migrate` (already migrated locally).
2. Visit `/games`. With ≥1 IGDB-synced game and ≥1 bundle, confirm the bundles
   shelf at top, then per-genre / per-platform shelves, then the all-games grid.
   Hover a tile — confirm the title + release-year + IGDB rating in the `title`
   attribute.
3. Click `[see all]` on a per-genre shelf. Confirm the URL becomes
   `/games?genre=<id>` and the all-games grid shows only that genre's games.
4. Visit `/bundles`. Confirm the wrapping tile grid (no table).
5. Edit a video at `/videos/:id/edit`. Scroll to the "linked games / bundles"
   fieldset. Type a game name in the picker; click the `[game]` row. Confirm a
   link row appears above. Click `[★]` to flip primary; confirm the badge
   updates.
6. Add a bundle link via the same picker. Confirm both kinds coexist. Click
   `[remove]` on one; confirm the action-screen page; submit; confirm the row is
   gone.
7. Open the linked game's show page. Confirm the "linked videos" section lists
   the video; if the link is primary, confirm the `[★]` badge.
8. Verify game footage cache. Set the linked video's `duration_seconds` to e.g.
   7200, save. Re-link. Confirm `Game#hours_of_footage_cached` rounds to 2.
9. MCP smoke (from Claude Mobile or curl):
   - `game_search { q: "zelda" }` → returns matches.
   - `game_add_from_igdb { igdb_id: 7346, confirm: "no" }` → preview.
   - `game_add_from_igdb { igdb_id: 7346, confirm: "yes" }` → game added.
   - `video_link_game { video_id, game_id, confirm: "no" }` → preview.
   - `video_link_game { video_id, game_id, confirm: "yes" }` → link created.
   - `igdb_search { q: "Hollow Knight Silksong" }` → IGDB live hits.
10. `bundle exec rspec` from a clean state (DB reset between runs) → green.

**Open issues / blockers:** none. Phase 14 — Spec 01 + Spec 02 + Spec 03 —
complete. Reviewer agent dispatch optional. Phase 13 (analytics catalog) is the
next dispatch that depends on Phase 14's data tier.

### 2026-05-10 — Game show row-1 details pane sized to 640px

**Discussion:** The game show page details pane was sitting at the wide-pane
size (904px), which paired with the 280px cover row 1 to consume more
horizontal real estate than the read-only details payload needs. User
requested a mid-size pane (bigger than the default 452px, smaller than 904px)
specific to this page for now — promotable later if other pages adopt the
same geometry.

**Implemented:**

- `app/assets/tailwind/application.css` — new `.pane--game-detail` modifier
  (`flex: 0 0 640px; width: 640px;`) defined alongside `.pane--narrow`. Picks
  up the zebra rhythm via the base `.pane` rule. Mobile breakpoint extended
  to collapse it to `88vw` (and apply `scroll-snap-align: start` inside a
  `.pane-strip`) like the other pane modifiers.
- `app/views/games/show.html.erb` — row 1 right pane swapped from
  `.pane.pane--wide` → `.pane.pane--game-detail`. Total row-1 width
  280 + 640 = 920px, fits standard workspace. Rows 2 (sync) and 3 (linked
  videos) keep `.pane--wide` — only row 1 changes.
- `spec/requests/games_spec.rb` — pane-modifier comment updated to describe
  the row-1 geometry; the `it "uses the narrow + game-detail + wide pane
  modifiers"` example now asserts all three classes appear in the rendered
  markup. The earlier `pane--wide` assertion stays satisfied because rows 2
  and 3 still render `.pane--wide`.

**Files touched:**

- `app/assets/tailwind/application.css`
- `app/views/games/show.html.erb`
- `spec/requests/games_spec.rb`

**Quality gates:**

- `bundle exec rspec spec/requests/games_spec.rb` — 54 examples, 0 failures.
  (One transient flake on the `/games` empty-state assertion — unrelated to
  this work; created by a parallel agent's IGDB-search modal restructure —
  cleared on rerun.)
- `bin/rubocop spec/requests/games_spec.rb` — clean (CSS / ERB are not in
  rubocop's scope on this project).
- `bin/brakeman -q -w2` — Errors: 0, Security Warnings: 0.

**Coordination:** complementary to the parallel game-show / edit split agent
(`ae939b4ba59b253e9`); confirmed the row-1 right pane is the only pane
touched by this lane and the show page's three-row structure (cover +
details, sync, linked videos) is preserved untouched.

**Open issues / blockers:** none. Page-specific name `.pane--game-detail`
chosen per spec; promote to a generic `.pane--medium` if a second page
adopts the same 640px geometry.
