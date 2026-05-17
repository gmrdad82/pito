# Phase 27 — log

## [skipci] 2026-05-17 — v2 spec 05 Games index shelves-only (pito-rails)

Implements v2 spec 05 — `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/05-games-index-shelves-only.md`. Collapses `/games` to a single shelves layout. Drops the three-mode display switcher (grid / list / shelves-by-letter), the per-mode partials, the `Users::GamesPreferencesController`, the `User#preferred_games_display_mode` enum + backing column, and the `?display=` query-param resolver. Replaces them with one stack of shelves: filter row → bundles → recently-played → genres outer shelf → collections outer shelf → per-letter shelves. The genre short-name mapping was rewritten to the spec's locked table (RPG, FPS, JRPG, Sim, MOBA, Platformer, VN, Card, Hack/Slash, etc.) — unknown genres fall through to the IGDB canonical name unchanged.

### What landed

- `app/views/games/index.html.erb` — rewritten to the new contract. Page title + `[+]` → filter row → bundles (when present) → recently-played (when present) → hairline → genres outer shelf (when populated) → hairline → collections outer shelf (when populated) → hairline → letter shelves wrapper. The empty-state path stays a single `<p class="text-muted">no games yet…</p>`. The `display:` query-string passthrough on the filter row's `query_string_overrides:` hash is gone; only `genre:` and `collection:` survive.
- `app/views/games/_letter_shelves.html.erb` (NEW) — wraps the controller's `@letter_buckets` array. One `<section class="shelf shelf--letter">` per non-empty letter bucket. Heading is the bucket key as `<h3>`. Tiles render through `Games::CoverComponent` at the `:shelf` variant (98 × 130). Every shelf carries `data-controller="steam-shelf"` so the wheel-to-horizontal drag-scroll affordance is inherited. The `<section class="all-games-shelves-by-letter">` wrapper survives as the back-compat hook target (e.g. the `_letter_shelves` width-clamp CSS rule already keyed on the class).
- `app/controllers/games_controller.rb` — `index` action drops `@display_mode = resolved_display_mode`, drops the per-platform `@platforms_shelves` computation (the per-platform shelves were never carried into the new layout per the spec's render contract), and adds a private `build_letter_buckets(scope)` helper that produces an `Array` of `[letter, [Game, ...]]` tuples in render order (`A..Z` first, `#` bucket last). Buckets fill from `scope.to_a.group_by` with the letter rule (first char uppercased when in `[A-Z]`, else `#`); each bucket sorts by `LOWER(title)` with `id` as a stable tiebreak. The legacy `resolved_display_mode` method retired.
- `app/models/user.rb` — drops the `attribute :preferred_games_display_mode` + `enum :preferred_games_display_mode {…}` declaration. The column is gone (see migration below); the enum class methods and instance predicates retire with it. A documentary comment block stays in place noting the v2 spec 05 retirement.
- `app/helpers/genres_helper.rb` — rewrites `SHORT_NAMES` (renamed from `GENRE_SHORT_NAMES`) to match the spec's locked mapping table: `RPG`, `JRPG`, `FPS`, `MOBA`, `RTS`, `TBS`, `Sim`, `Sport`, `Racing`, `Fighting`, `Adventure`, `Platformer`, `Puzzle`, `Strategy`, `Pinball`, `Arcade`, `Music`, `Hack/Slash`, `Quiz`, `Tactical`, `VN`, `Indie`, `Card`. Both `Shooter` and `First-person Shooter` collapse to `FPS`; both `Point-and-click` and `Adventure` collapse to `Adventure`. The legacy `ACRONYM_LABELS` constant + the lowercase-rule fallthrough retired — unmapped genres now return their IGDB canonical name unchanged (the spec's locked semantics).
- `config/routes.rb` — drops the `namespace :users do resource :games_preferences, only: :update end` block. The endpoint is gone.
- `db/migrate/20260516232156_drop_preferred_games_display_mode_from_users.rb` (NEW) — `remove_column :users, :preferred_games_display_mode`. Reversible (`down` re-adds the integer column with the historical default `0`).

### Deletions

- `app/views/games/_grid_mode.html.erb` (deleted).
- `app/views/games/_list_mode.html.erb` (deleted).
- `app/views/games/_shelves_by_letter_mode.html.erb` (deleted).
- `app/views/games/_display_mode_switcher.html.erb` (deleted).
- `app/controllers/users/games_preferences_controller.rb` (deleted; `app/controllers/users/` directory removed because it became empty).
- `spec/requests/users/games_preferences_spec.rb` (deleted; `spec/requests/users/` directory removed because it became empty).
- `spec/system/games_display_modes_spec.rb` (deleted — every example asserted display-mode switcher behavior that no longer exists).
- `spec/system/games_list_mode_bulk_spec.rb` (deleted — same reason; bulk-select scaffold for the list-mode partition retires with the partition).
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` (deleted).
- `spec/views/games/_grid_mode.html.erb_spec.rb` (deleted).
- `spec/views/games/_list_mode.html.erb_spec.rb` (deleted).
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` (deleted).

### Tests added / updated

- `spec/views/games/_letter_shelves.html.erb_spec.rb` (NEW) — 14 examples covering: happy single-bucket render (section + heading + tile + steam-shelf wiring + `data-letter` attribute + outer wrapper class), happy multi-bucket order preservation, digit-titled `#` bucket position (heading present + pinned to end), tile order preservation, edge empty buckets array (renders nothing), edge bucket-with-zero-games defensive fallthrough, no JS confirm / no `<script>` flaw guards.
- `spec/views/games/index.html.erb_spec.rb` (NEW) — 14 examples covering: empty-install happy path (empty-state copy, title + `[+]`, filter row always present, no letter shelves wrapper, no bundles / genres shelves), happy full library (letter shelves wrapper present, exactly N letter shelves stamped, title-before-filter-row order, filter-row-before-letter-shelves order, no `<h2>all</h2>` heading, no `data-display-mode=` attribute, no display-mode switcher), happy bundles + recently-played order.
- `spec/helpers/genres_helper_spec.rb` — rewritten end-to-end. 29 examples covering the new `SHORT_NAMES` mapping (frozen, RPG / JRPG / FPS / Sim / MOBA / Platformer / VN / Card / Hack/Slash / Point-and-click / RTS + TBS), string input, Genre instance input (model + persisted), and nil / blank / non-string / non-Genre edge cases.
- `spec/models/user_spec.rb` — replaces the `preferred_games_display_mode enum (Phase 27 — 01d)` describe with a `Phase 27 v2 spec 05 — preferred_games_display_mode removed` describe (4 examples asserting the absence of the predicate methods, the attribute reader, the class-level enum mapping, and the column on `User.column_names`).
- `spec/requests/games_spec.rb` — extensive edits: drops the `<h2>all</h2>` heading-order and `data-display-mode=` assertions, drops the per-platform `[see all]` test, drops the entire `display mode resolution (Phase 27 §01d)` describe block (16 examples retired), drops the `display=list` chip-href preservation example, rewrites the contradiction notice assertion (no longer asserts an empty-grid muted copy — the listing wrapper is suppressed instead), updates the genre short-label assertions to the new mapping (`Adventure` stays `Adventure`; `rpg` / `platformer` fall through unchanged), rewrites the hairline ordering assertion to the new "hairline-leads-each-section" contract, marks the `+1 edition` index assertion as a known-gone surface (the badge's canonical surface is the game show page now). Adds a new `Phase 27 v2 spec 05 — shelves-only layout` describe with 8 examples (one section per non-empty letter, hidden letters, `#` bucket at end, `?display=list` / `?display=grid` / `?display=shelves_by_letter` ignored, no `data-display-mode=` anywhere, no switcher rendered).
- `spec/system/games_index_spec.rb` — updates the v1 nested-shelves describes to the new genre-short-name mapping (`Adventure` stays `Adventure`), replaces `section.all-games-grid` selectors with `section.all-games-shelves-by-letter`, switches text-content assertions to `data-tile-game-id` selectors (the cover-only `Games::CoverComponent` tiles don't render visible title text), updates the contradiction system assertion to "listing wrapper suppressed", updates the `[see all]` navigation assertion to the new letter-shelves wrapper, updates the platform-logo system spec (spec 07 scope) to scope tile lookups to the recently-played shelf (where `_tile.html.erb` still renders the platform-logo footer) and seed each test game with `played_at` so it lands there.
- `spec/system/games_steam_shelf_spec.rb` — drops the `all-games` heading + `data-display-mode="grid"` assertion (heading + partition retired), adds a negative assertion for both, updates the genre `<h3>` text to `Adventure`.
- `spec/system/games_multi_version_spec.rb` — switches `have_content("Pragmata")` text assertions on `/games` to `have_css("[data-tile-game-id=...]")` because the new layout's cover tiles emit only `<img>` (no visible title text). The `+1 edition` text assertion is dropped — the badge moved off the index surface.
- `spec/system/keyboard_grid_navigation_spec.rb` — rewrites the `/games (tile grid)` describe. The flat all-games tile grid retired with the display-mode switcher; the new layout's shelves use the `steam-shelf` Stimulus controller, NOT the keyboard tile-grid surface. The describe now asserts the absence of `data-keyboard-grid` and `data-keyboard-tile` hooks on `/games`.
- `spec/views/games/_genre_sub_shelf.html.erb_spec.rb` — updates the `<h3>adventure</h3>` assertions to `<h3>Adventure</h3>` (one-to-one mapping per the new short-name table).
- `spec/views/games/_genres_shelf.html.erb_spec.rb` — same `<h3>adventure</h3>` → `<h3>Adventure</h3>` update; replaces the "lowercase rule" passthrough example with a "unmapped genre returns canonical name unchanged" example.

### Targeted spec result

- `spec/requests/games_spec.rb` — 155 examples, 0 failures.
- `spec/views/games/` — 174 examples, 0 failures.
- `spec/components/games/` — 188 examples, 0 failures.
- `spec/helpers/genres_helper_spec.rb` — 29 examples, 0 failures.
- `spec/models/user_spec.rb` — 71 examples, 0 failures.
- `spec/system/games_index_spec.rb` + `spec/system/games_steam_shelf_spec.rb` + `spec/system/keyboard_grid_navigation_spec.rb` — 46 examples, 0 failures (with `--tag type:system`).
- `spec/system/games_multi_version_spec.rb` + `spec/system/games_platform_ownerships_spec.rb` — 15 examples, 0 failures (with `--tag type:system`).
- Per the CI hiatus, no full suite run was attempted.

### Static analysis

- `bin/brakeman -q -w2` → 0 security warnings, 0 errors, 1 pre-existing ignored entry. Five obsolete ignore entries surface in the working tree — unrelated to this spec (pre-existing).

### localStorage cleanup verification

- The display-mode switcher was a pure `button_to` form set (no Stimulus controller, no localStorage key, no Turbo data attribute), so no JS state needed cleanup. `grep -rn localStorage /home/catalin/Dev/pito/app/javascript/` returns only the calendar + theme controllers; no games-related localStorage keys exist (and never did). The retirement is one-pass clean.

### Scrollbar CSS scope

- The repo-wide 6 px scrollbar was already in place before this spec dispatched (commit `c630afa` from 2026-05-16 moved every `::-webkit-scrollbar` rule to `width: 6px; height: 6px;` on both axes — globally on the unscoped rule, plus scoped overrides on `dialog`-rooted scrollable surfaces). The audit pass for spec 05 was a no-op: every surface already renders at the locked 6 px size with the themed muted thumb. No CSS was touched in this dispatch.

### Files touched

- Modified: `app/controllers/games_controller.rb`, `app/models/user.rb`, `app/helpers/genres_helper.rb`, `app/views/games/index.html.erb`, `config/routes.rb`, `spec/requests/games_spec.rb`, `spec/views/games/_genre_sub_shelf.html.erb_spec.rb`, `spec/views/games/_genres_shelf.html.erb_spec.rb`, `spec/system/games_index_spec.rb`, `spec/system/games_steam_shelf_spec.rb`, `spec/system/games_multi_version_spec.rb`, `spec/system/keyboard_grid_navigation_spec.rb`, `spec/helpers/genres_helper_spec.rb`, `spec/models/user_spec.rb`, `db/schema.rb` (auto-bumped by `db:migrate`).
- Added: `app/views/games/_letter_shelves.html.erb`, `db/migrate/20260516232156_drop_preferred_games_display_mode_from_users.rb`, `spec/views/games/_letter_shelves.html.erb_spec.rb`, `spec/views/games/index.html.erb_spec.rb`.
- Deleted: `app/views/games/_grid_mode.html.erb`, `app/views/games/_list_mode.html.erb`, `app/views/games/_shelves_by_letter_mode.html.erb`, `app/views/games/_display_mode_switcher.html.erb`, `app/controllers/users/games_preferences_controller.rb`, `spec/requests/users/games_preferences_spec.rb`, `spec/system/games_display_modes_spec.rb`, `spec/system/games_list_mode_bulk_spec.rb`, `spec/views/games/_display_mode_switcher.html.erb_spec.rb`, `spec/views/games/_grid_mode.html.erb_spec.rb`, `spec/views/games/_list_mode.html.erb_spec.rb`, `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`. Empty parent directories `app/controllers/users/` and `spec/requests/users/` removed.

### Contract decisions for downstream specs (06 will read this)

- **No `?display=` query-string is honored.** The controller dropped the resolver; any saved bookmark to `/games?display=<mode>` 200s but the layout is the single shelves-only render. Filter row's `query_string_overrides:` hash carries only `genre:` and `collection:` keys.
- **Letter shelves use `Games::CoverComponent` (`:shelf` variant, 98 × 130).** No visible title text on tiles — assertions targeting the listing must use `data-tile-game-id` rather than `have_content`. The `+N editions` badge and the platform-logo footer (spec 07) live on the legacy `_tile.html.erb` partial, which now only renders in the bundles + recently-played shelves. The game show page is the canonical surface for the editions badge.
- **Per-platform shelves retired.** The `@platforms_shelves` controller assignment is gone; the `owned_on=<slug>` filter-row token is the canonical platform filter.
- **`<h2>all</h2>` heading retired.** No "all-games partition" sentinel exists in the new layout; the letter shelves wrapper is the whole listing.
- **Genre short labels follow `GenresHelper::SHORT_NAMES`.** RPG, JRPG, FPS, MOBA, RTS, TBS, Sim, Sport, Racing, Fighting, Adventure, Platformer, Puzzle, Strategy, Pinball, Arcade, Music, Hack/Slash, Quiz, Tactical, VN, Indie, Card. Both `Shooter` and `First-person Shooter` collapse to `FPS`; both `Point-and-click` and `Adventure` collapse to `Adventure`. Unmapped names return the IGDB canonical name unchanged (case preserved).

### Plan-checkbox status

The v2 specs directory (`specs-v2/`) is a polish-dispatch overlay on the original Phase 27 sub-spec checkboxes; `plan.md` does not enumerate a checkbox for spec 05 specifically (the 01a–01g checkboxes track the original phase scope). No checkboxes flipped — the v2 dispatch lands as a log entry per established Phase 27 convention (see prior `v2 spec 01`, `v2 spec 03`, and `v2 spec 04` entries below).

### Open / deferred

- The `[+N editions]` badge no longer renders on the index. The game show page surface still carries it. If a follow-up wants the badge on the index again, options are: (a) extend `Games::CoverComponent` with an optional badge overlay, or (b) bring the legacy `_tile.html.erb` partial back into the letter shelves' tile slot. Out of scope here.
- The platform-logo tile footer (spec 07) is now only visible in the recently-played + bundles shelves on `/games`. If spec 07 wants the footer on every tile, the same component-extension path applies. Out of scope here.
- Spec 06 (filters revamp) lands the next slice of work into this surface; the filter row's internal layout is its lane.

## [skipci] 2026-05-17 — v2 spec 03 Game resync job (pito-rails)

Implements v2 spec 03 — `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/03-game-resync-job.md`. Hardens the existing `GameIgdbSync` Sidekiq job into the canonical resync surface: Sidekiq uniqueness lock (`lock: :until_executed, on_conflict: :log` — intent declaration; Pito is on Sidekiq OSS so the `games.resyncing` Boolean is the real mutex), live Turbo-Stream broadcast that swaps the show page's sync-status pane from the dot-loader back to the idle `[resync]` button without a refresh, and an explicit collection cover-art fan-out call to `Collections::CompositeRebuildQueue#enqueue_for_game_resync(game)` on the success path. Field partition (IGDB-sourced vs ownership-sourced) is reinforced in the model docstring and asserted by a paranoid job-level spec.

### What landed

- `app/jobs/game_igdb_sync.rb` — added `sidekiq_options lock: :until_executed, on_conflict: :log` alongside the existing `queue: :default, retry: 5`. Introduces a `success` flag that gates the post-sync collection fan-out (only fires on a clean `Igdb::SyncGame#call` return — NOT on `ValidationError` / `RateLimited` / `ServerError`). Calls `Collections::CompositeRebuildQueue.new.enqueue_for_game_resync(game.reload)` BEFORE the `resyncing` flag flips false so the rebuild reads the freshly-resynced row's `cover_image_id`. Both the fan-out call and the broadcast are wrapped in `rescue StandardError → nil` so a Redis hiccup or Collection lookup glitch cannot trip Sidekiq retry on an otherwise-successful sync. Adds a `broadcast_resync_state(game_id)` private helper that mirrors `ReindexAllJob#broadcast_voyage_section` — re-renders the `games/_sync_status` partial and replaces target `game_sync_status_<id>` on stream `"game_resync:<id>"`. The broadcast fires from the `ensure` block so it lands once per run (post-clear), whether the sync succeeded, failed retryably, or failed validation-wise.
- `app/views/games/_sync_status.html.erb` (NEW) — extracted the show-page Row 2 sync pane into a partial keyed on `game:`. Wrapper `<div id="game_sync_status_<id>">` is the Turbo-Stream replace target. Renders the dot-loader sync-indicator when `game.resyncing?` is true; otherwise renders the `synced X ago.` / `not synced yet.` label + the `[resync]` button (gated on `game.igdb_id.present?`).
- `app/views/games/show.html.erb` — added `<%= turbo_stream_from "game_resync:#{@game.id}" %>` at the top of the page (permanent subscription, so a CLI / MCP-initiated resync lands in the open browser tab without a refresh). The Row 2 sync pane body is now a single `<%= render "sync_status", game: @game %>` call. The legacy inline `<h2>sync</h2>` + dot-loader / button branches moved into the partial verbatim.
- `app/models/game.rb` — docstring overhaul. Pins the field partition: IGDB-sourced columns + joins (overwritten by every re-sync, last-write-wins) and ownership-sourced columns + joins (NEVER touched by sync). Notes the enforcement points: `Igdb::SyncGame#call` (writes only IGDB columns) and `GamesController#local_only_params` (allowlists only ownership / notes / footage / version inputs). Adds a pointer to the new model spec assertion that runs a sync and asserts the ownership attribute hash is unchanged.

### Tests

- `spec/jobs/game_igdb_sync_spec.rb` — extended from 12 → 26 examples. New describe blocks: `"collection cover-art fan-out"` (6 examples — success-path enqueue, no-enqueue on `ValidationError` / `RateLimited` / `ServerError`, flag-still-cleared when fan-out raises, no-re-raise when fan-out raises), `"live broadcast"` (4 examples — success / `ValidationError` / retryable failure all broadcast; broadcast errors swallowed without leaking out of `ensure`), `"ownership-sourced field partition"` (1 paranoid example — runs a no-op sync against a row with all ownership fields set, asserts the post-sync attribute hash + `game_platform_ownerships` rows are byte-equal), `"edge cases"` (1 example — deleted game id mid-flight no-ops). Sidekiq-options block extended with `lock: :until_executed` + `on_conflict: :log` assertions (symbol equality — Sidekiq stores option symbols verbatim).
- `spec/views/games/_sync_status.html.erb_spec.rb` (NEW) — 9 examples. Wrapper id, dot-loader branch (controller + frame attributes present; `[resync]` button absent), idle branch (`[resync]` present; sync-indicator absent; `synced X ago.` label; `not synced yet.` fallback; post-sync caveat copy), local-only-game branch (no `igdb_id` → no `[resync]` button + `not synced yet.` label).
- `spec/requests/games_spec.rb` — extended the existing `POST /games/:id/resync` describe with a `"JSON variant"` sub-block: 202 Accepted + `enqueued_jid` on the happy path; 409 Conflict + `error: "already_resyncing"` when the mutex is held. The existing HTML paths (3 examples) and 404 path stay.

### Verification

- `bundle exec rspec spec/jobs/game_igdb_sync_spec.rb spec/views/games/_sync_status.html.erb_spec.rb` — 36 examples / 0 failures.
- `bundle exec rspec spec/views/games/show.html.erb_spec.rb` — 6 / 0 (unchanged; partial extraction is transparent to the show view spec).
- `bundle exec rspec spec/requests/games_spec.rb -e "GET /games/:id" -e "resync"` — 42 / 0 across the GET show + POST resync surfaces. The two new JSON-variant resync examples pass alongside the existing 3 HTML resync examples.
- `bundle exec rspec spec/models/game_spec.rb spec/services/collections/composite_rebuild_queue_spec.rb spec/jobs/collection_cover_rebuild_job_spec.rb` — 159 / 0 across the adjacent model + composite-rebuild surfaces (no regression in the model's `after_save_commit` hook nor the orchestrator).
- `bin/brakeman -q -w2` — 0 warnings / 0 errors (5 obsolete ignore entries surface; carried over from working-tree drift, unrelated to this spec).

### Contract decisions for downstream specs

- **Stream name** `"game_resync:<id>"` and **target id** `game_sync_status_<id>` are LOCKED. Spec 08's detail-page revamp moves the sync pane to the LEFT-column layout but the partial contract (target id, stream name, partial path `games/sync_status`, broadcast format) carries over unchanged.
- **Permanent `turbo_stream_from` subscription** on the show page — locked per spec architect lean. Cost is one extra WebSocket subscription per open tab; benefit is that CLI / MCP-initiated resyncs land in the user's open browser without a refresh.
- **Collection fan-out call site** — INSIDE the success branch, AFTER `Igdb::SyncGame#call` returns, BEFORE `ensure` clears `resyncing`. The model's `after_save_commit :rebuild_collection_composites_on_resync` hook ALSO fires (via the `game.update!` inside SyncGame). The explicit job-level call is the canonical spec-03 trigger; the duplicate enqueue is a no-op rebuild (`CollectionCoverRebuildJob` is idempotent on cache hit, per its docstring + the orchestrator's dedup-per-batch design).
- **Sidekiq uniqueness** is INTENT-ONLY today (Pito is on Sidekiq OSS without `sidekiq-unique-jobs`). The `games.resyncing` Boolean is the real safety net; the controller short-circuits duplicate `[resync]` clicks via the same flag. If the gem is ever added, the keys are already in place.

### Files touched

- Modified: `app/jobs/game_igdb_sync.rb`, `app/views/games/show.html.erb`, `app/models/game.rb`, `spec/jobs/game_igdb_sync_spec.rb`, `spec/requests/games_spec.rb`.
- Added: `app/views/games/_sync_status.html.erb`, `spec/views/games/_sync_status.html.erb_spec.rb`.

### Plan-checkbox status

The v2 specs directory (`specs-v2/`) is a polish-dispatch overlay on the original Phase 27 sub-spec checkboxes; `plan.md` does not enumerate a checkbox for spec 03 specifically. No checkboxes flipped — the v2 dispatch lands as a log entry per established Phase 27 convention.

### Open / deferred

- Spec 08's detail-page revamp will move the sync pane into the new LEFT-column layout. The partial + stream contract carries over unchanged; the migration is purely visual.
- The CLI / MCP side of the live resync UI is not in scope; the broadcast targets the browser specifically. CLI / MCP callers POST to `/games/:id/resync` and get the JSON 202 / 409 response and can poll the resyncing flag if needed.

## [skipci] 2026-05-17 — v2 spec 01 Single main genre per Game (pito-rails)

Implements v2 spec 01 — `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/01-single-main-genre.md`. Collapses the multi-genre game model to ONE main genre per game. Every UI surface that previously rendered a comma-joined `genres:` list now renders a single `primary_genre.name` (or `"—"`). The legacy `game_genres` multi-valued join survives as the raw IGDB record so the picker can re-evaluate the choice on each re-sync. JSON wire shape changes from `genres: [{id, name}]` to `genre: "name"` (singular) — breaking change OK per spec; only pito's own surfaces consume it.

### What landed

- `app/services/games/primary_genre_picker.rb` — tightens tie-break to the locked policy `ORDER BY LOWER(genres.name) ASC, genres.id ASC` (was bare `:name`). Adds documentation for the case-insensitive primary key + id secondary key (deterministic across requests / Postgres versions). Behavior on nil input + unpersisted game is pinned at "returns nil, never raises" (matches the prior implementation; now documented).
- `app/services/igdb/sync_game.rb` — new private `re_assign_primary_genre(game)` step wired between `sync_genres` and `sync_platforms`. Reloads the in-memory `game.genres` association so the picker sees the post-sync join state, clears `primary_genre_id` in memory so the picker's rule-1 pin guard short-circuits to the alphabetical pick (a sync is the canonical moment to re-derive from IGDB metadata; user pins are honored everywhere else), then writes the new id (or nil when the post-sync set is empty) via `update_column`.
- `app/models/game.rb` — comment refresh on the `primary_genre` association + `assign_primary_genre_if_blank` callback. Documents that the hook is the safety net for non-sync save paths; `Igdb::SyncGame#call` writes the column explicitly on every sync. Behavior unchanged.
- `app/views/games/show.html.erb` — `<h2>` "genres / platforms" → "genre / platforms"; `<span>genres:</span> @game.genres.map(&:name).join(", ")` → `<span>genre:</span> @game.primary_genre&.name.presence || "—"`. Interim guard until spec 08's revamp lands the primary-bold + secondary-normal layout.
- `app/decorators/game_decorator.rb` — `as_detail_json` swaps `genres: genres.map { |g| { id: g.id, name: g.name } }` for `genre: primary_genre&.name`. Breaking change — only pito's MCP / CLI consume this field and they land in a later parity pass per the spec's open question #1 ("rename outright"). `as_summary_json` was already singular-clean (no `:genres` key).
- `db/migrate/20260516224649_backfill_games_primary_genre.rb` (NEW) — data-only migration with `disable_ddl_transaction!`, iterates `Game.where(primary_genre_id: nil)` in 500-row batches, calls `Games::PrimaryGenrePicker.new.pick(game)`, writes via `update_columns` (bypasses callbacks + validations — correct for a backfill). Empty-genres rows stay NULL. Reversible: `down` clears every populated pointer; the model `before_save` hook + IGDB sync re-derive on the next save / sync. Schema bump only — `games.primary_genre_id` already exists with the `on_delete: :nullify` FK (added in `BetaMigration3` at the 2026-05-11 Phase 27 follow-up).

### Tests

- `spec/services/games/primary_genre_picker_spec.rb` — extends with 3 new examples: case-insensitive tie-break (Action / action / ACTION lowercase-equal, secondary by id), cross-case ordering (lowercase "adventure" beats uppercase "RPG"), unpersisted game flaw guard (returns nil, no raise). 10 examples total, all green.
- `spec/services/igdb/sync_game_spec.rb` — new describe `"Phase 27 v2 spec 01 — primary_genre re-pick on every sync"` with 4 examples: alphabetical winner pick after IGDB swap (stale pointer + stale join row gets replaced), `primary_genre_id` cleared to nil when IGDB returns an empty genres set, idempotent re-sync (same set → same pick), call-ordering proof (re-pick runs AFTER sync_genres — observed via the side-effect: a pre-seeded `"aaa-stale"` genre that would win alphabetically if the re-pick ran first is gone from the join, so Adventure wins). 20 examples total, all green.
- `spec/decorators/game_decorator_spec.rb` — replaces the `:genres` key-set assertion with `:genre` (singular); adds a flaw guard for "does NOT carry the legacy `:genres` key"; replaces the multi-genre array assertion with two examples (primary set → returns the name string; no primary → returns nil); adds the case-insensitive alphabetical-winner assertion through the picker. 19 examples total, all green.
- `spec/views/games/show.json.jbuilder_spec.rb` — flips `"genres"` to `"genre"` in the key-set assertion; adds three new examples (legacy `genres` key absent; `genre` is the primary's name when set; `genre` is null when no primary). 7 examples total, all green.
- `spec/models/game_spec.rb` — new describe `"Phase 27 v2 spec 01 — primary_genre management"` with 6 examples: callback fires when blank + game has linked genres, callback is a no-op when already set, alphabetical-first pick across 3 linked genres, no-raise + nil-pointer when zero genres, picker-nil write path, FK `on_delete: :nullify` clears the pointer when the pinned genre is destroyed. All green.
- `spec/requests/games_spec.rb` — new describe inside `GET /games/:id` for the show HTML (4 examples: singular `genre:` label + value; em-dash placeholder; legacy `genres:` label gone; secondary linked genres NOT rendered). New top-level describe `GET /games/:id.json (Phase 27 v2 spec 01 — single genre)` with 4 examples: `genre` is the primary's name; `genre` is null when none; legacy `genres` key absent; 404 / RecordNotFound on garbage id. 8 new examples, all green.
- `spec/system/games_index_spec.rb` — new describe `"Single main genre per game (v2 spec 01)"` with 2 rack_test examples: a 3-genre game appears under EXACTLY ONE sub-shelf (the alphabetical winner); when the pinned primary changes (simulating a re-sync), the game hops to a new sub-shelf and is gone from the old. Both green.

### Static analysis

- `bin/brakeman -q -w2` → 0 security warnings, 0 errors, 1 pre-existing ignored entry. Five obsolete ignore entries surface in the working tree — unrelated to this spec.

### Pre-existing failures not introduced by this spec

- `spec/requests/games_spec.rb:201` — N+1 guard `expect(large - small).to be < 5` got 9. Confirmed pre-existing by reverting only the spec-01 changes (model + service + view + decorator + JSON + spec edits) and re-running the same test: still fails 9 vs 5. Belongs to the broader working-tree drift on `_tile.html.erb` / decorator / model from sibling spec waves.
- `spec/models/game_spec.rb` "Phase 27 v2 spec 02 — collection composite rebuild hooks" — 3 failures on `enqueue_for_collections` spy receiving 2 invocations where 1 was expected. The hooks themselves were added to `app/models/game.rb` by another sibling spec wave (v2 spec 02); the 3 failures predate this spec-01 dispatch. Out of spec-01's lane.

### Files touched

- Modified: `app/services/games/primary_genre_picker.rb`, `app/services/igdb/sync_game.rb`, `app/models/game.rb`, `app/views/games/show.html.erb`, `app/decorators/game_decorator.rb`, `spec/services/games/primary_genre_picker_spec.rb`, `spec/services/igdb/sync_game_spec.rb`, `spec/decorators/game_decorator_spec.rb`, `spec/views/games/show.json.jbuilder_spec.rb`, `spec/models/game_spec.rb`, `spec/requests/games_spec.rb`, `spec/system/games_index_spec.rb`, `db/schema.rb` (version bump only).
- Added: `db/migrate/20260516224649_backfill_games_primary_genre.rb`.

### Contract decisions for downstream specs (05 / 08 will read this)

- **Picker tie-break is LOCKED** at `ORDER BY LOWER(genres.name) ASC, genres.id ASC`. Spec 05's shelf rendering and spec 08's detail-page layout can rely on a deterministic, stable single primary genre per game across requests and re-syncs.
- **`Game#primary_genre`** is the single source of truth for "the game's genre" everywhere downstream. `Game#genres` survives only as the IGDB raw record (picker input). Downstream view code should NOT iterate `game.genres` — only `game.primary_genre&.name` or fall back to `"—"`.
- **JSON wire shape** for the detail endpoint: `"genre": "Adventure"` (string) or `"genre": null`. The legacy `"genres": [{...}]` key is removed outright. MCP / CLI parity follow-up (spec 01g or a successor) is the place to roll the same rename into those surfaces.
- **IGDB sync re-evaluation** runs on every sync via `Igdb::SyncGame#re_assign_primary_genre`. It bypasses the picker's pin-honoring rule 1 by clearing the in-memory `primary_genre_id` first — a re-sync IS the moment to re-derive from IGDB. User-set pins (when that surface ships) survive everywhere ELSE because the picker's rule 1 still honors them outside the sync path.

### Plan-checkbox status

The v2 specs directory (`specs-v2/`) is a polish-dispatch overlay on the original Phase 27 sub-spec checkboxes; `plan.md` does not enumerate a checkbox for spec 01 specifically (the 01a–01g checkboxes track the original phase scope). No checkboxes flipped — the v2 dispatch lands as a log entry per established Phase 27 convention.

### Open / deferred

- MCP / CLI surfaces still serialize the multi-genre `genres` list. The spec leaves the catch-up as a separate parity pass; pito-mcp and pito-rust dispatches are paused per the current focus on web polish.

## [skipci] 2026-05-17 — v2 spec 04 IGDB add-game modal polish (pito-rails)

Implements v2 spec 04 — `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/04-igdb-add-game-modal.md`. Tightens the global IGDB add-game modal copy and controls, adds auto-search (no `[search]` button), seeds the new game's title eagerly from the IGDB search-result row so the breadcrumb shows the canonical title immediately, and DELETES the legacy "default create empty game" branch from `GamesController#create` so IGDB is the sole entry point to creating a game.

### What landed

- `app/views/shared/_igdb_search_modal.html.erb` — dialog title trimmed `add a game from igdb` → `add a game`; input placeholder trimmed `search igdb…` → `search…`; the explicit `[search]` `<button>` is gone; the input wires both `input->igdb-search-modal#search` and `keydown.enter->igdb-search-modal#search`; `[cancel]` swaps to `BracketedMutedLinkComponent` (muted secondary affordance, same primitive the session-revoke and Slack/Discord help surfaces use) with the `click->igdb-search-modal#close` action wired via the component's `data:` passthrough; the inline `style="max-width: 720px;"` band-aid is replaced by a new `.pane-dialog--wide` modifier on the outer `<dialog>`; the inner wrapper's redundant `width: min(720px, 92vw)` is dropped now that the outer `<dialog>` sizes correctly. New `data-igdb-search-modal-min-chars-value="5"` exposes the auto-search threshold as a Stimulus value.
- `app/javascript/controllers/igdb_search_modal_controller.js` — drops the explicit `submit` action (no `[search]` button). The single `search` action handles BOTH the `input` event (debounced 250 ms, gated on `value.trim().length >= minCharsValue`) and the `keydown.enter` event (immediate fire, bypasses the min-chars guard, requires only `length >= 1`). The debounce default tightens from 300 ms to 250 ms per the spec. New `minChars: { type: Number, default: 5 }` Stimulus value.
- `app/assets/tailwind/application.css` — adds the `.pane-dialog--wide` modifier (`max-width: 720px; width: 95vw;`) under the existing `dialog.pane-dialog` rule. Specificity `(0,2,1)` beats the later `dialog.confirm-modal { max-width: 420px }` rule `(0,1,1)` so the wide modifier wins without needing `!important` or rule reordering. Other `.confirm-modal.pane-dialog` dialogs continue to cap at 420px.
- `app/controllers/games_controller.rb#create` — REMOVED the legacy `Game.new + save!` fallthrough that persisted an empty `"Untitled game"` row when `params[:game][:igdb_id]` was blank. The action now requires `igdb_id` and rejects everything else: HTML branch redirects to `/games` with flash `"games can only be added via the IGDB search modal."`; JSON branch returns 422 + `{"error":"igdb_id_required"}`. Permit list narrows to `[:igdb_id, :title]` ONLY — smuggled keys (`notes`, `played_at`, anything else) are silently dropped by ActionController params. Title pre-seed: when a non-blank `title` accompanies a valid `igdb_id` the new `Game.new` carries the IGDB-canonical title so the redirect target's breadcrumb reads the real title instead of the `"Untitled game"` attribute default during the in-flight `GameIgdbSync` window. Trim + 255-char guard mirror the column's validation. Removed the legacy success-flash copy `"create empty game (legacy)..."`.
- `app/views/games/_search_results.html.erb` — `[add]` `button_to` now carries `params: { game: { igdb_id: row["id"], title: row["name"] } }` so the IGDB result row's name reaches the controller as the eager title pre-seed.
- `spec/views/shared/_igdb_search_modal.html.erb_spec.rb` (NEW) — 9 examples covering copy (trimmed title, trimmed placeholder, no `add a game from igdb` legacy copy), controls (no `[search]` button, exactly one bracketed-muted `[cancel]` link wired to `#close`), auto-search wiring (dual `input` + `keydown.enter` action string, `min-chars-value="5"` exposed), dialog sizing (`.pane-dialog--wide` modifier present, inline `max-width` band-aid gone), and CLAUDE.md hard rules (no `data-turbo-confirm`, no inline JS `confirm` / `alert` / `prompt`).
- `spec/system/igdb_add_game_spec.rb` (NEW) — 7 rack_test-driver examples covering server-rendered surface: modal markup on `/games` (trimmed title + placeholder; no `[search]` button; one bracketed-muted `[cancel]` link wired to `#close`; opts into `.pane-dialog--wide`); add-flow via stubbed IGDB search endpoint (the new game's `title` lands as the IGDB-canonical value; show page breadcrumb reads the real title not `"Untitled game"`; `GameIgdbSync` is enqueued; flash notice reads `added; metadata loading in background.`). The 5-char auto-search guard and Enter override are JS-driven and out of rack_test's reach — they're covered by the view spec's wiring assertions plus the spec's manual recipe.
- `spec/requests/games_spec.rb` — extends `POST /games with igdb_id` with 5 new examples (title pre-seed lands, blank/omitted title falls back to attribute default, 255-char trim, `notes` smuggled drops, `played_at` smuggled drops). REPLACES the legacy `POST /games (legacy default-create)` describe block with new `POST /games WITHOUT igdb_id (legacy default-create removed)` — 6 examples asserting no row persists, the IGDB-only flash, the rejection holds when only `title` is smuggled, the rejection holds when only `notes` is smuggled, blank-string `igdb_id` is rejected, `GameIgdbSync` is not enqueued, and the JSON branch returns 422 + `{"error":"igdb_id_required"}`.
- `spec/components/bracketed_muted_link_component_spec.rb` — flips one of the pending `data:`-passthrough placeholders into a real assertion (the IGDB modal's `[cancel]` action wiring depends on it). The remaining 13 pendings stay as-is — the spec file was a wholesale `pending` placeholder, and filling them in is outside the scope of this spec.

### Legacy "default create empty game" removal — surface audit

- `GamesController#create` diff: the `igdb_id_param.present?` guard now short-circuits with a flash + 422 when missing instead of falling through to `Game.new + save!`. The legacy success flash (`"create empty game (legacy). use [search igdb] to add by id."`) is gone.
- Route survival: `POST /games` still exists (`resources :games` declares it). The endpoint is reachable; it just requires `params[:game][:igdb_id]`.
- View consumers: a single consumer of the `POST /games` endpoint exists in the app — `app/views/games/_search_results.html.erb` (the IGDB add-game `[add]` button_to). No `app/views/games/new.html.erb`, no inline form elsewhere. The result-row partial already carries `igdb_id`; this spec adds `title` to its `params` hash.
- MCP surface: no `create_game` tool exists in the catalog. The MCP `game_update_local` tool is the only games-mutation entry, and it operates on existing rows. No MCP-side change needed.
- Specs cleanup: the legacy `POST /games (legacy default-create)` describe in `spec/requests/games_spec.rb` is replaced wholesale with the new `POST /games WITHOUT igdb_id (legacy default-create removed)` describe (which now asserts the rejection contract rather than the legacy creation behavior).

### Tests

- `spec/views/shared/_igdb_search_modal.html.erb_spec.rb` — 9 examples, all green.
- `spec/system/igdb_add_game_spec.rb` — 7 examples, all green (rack_test driver, `--tag type:system`).
- `spec/requests/games_spec.rb` (POST /games sub-describes) — 16 examples covering both the new-igdb-id-flow extensions and the legacy-create-removed contract, all green.
- `spec/components/bracketed_muted_link_component_spec.rb` — 26 examples, 12 real + 14 pre-existing pendings, all green.
- Targeted spec sweep clean across all four files. The pre-existing N+1 failure on `spec/requests/games_spec.rb:201` is unrelated to this spec (it bisects to other pre-existing modifications in the working tree on `app/views/games/_tile.html.erb` / `app/decorators/game_decorator.rb` / `app/models/game.rb`).

### Static analysis

- `bin/brakeman -q -w2` → 0 security warnings, 0 errors, 1 pre-existing ignored entry. Five obsolete ignore entries surface — unrelated to this spec.

### Files touched

- Modified: `app/views/shared/_igdb_search_modal.html.erb`, `app/javascript/controllers/igdb_search_modal_controller.js`, `app/assets/tailwind/application.css`, `app/controllers/games_controller.rb`, `app/views/games/_search_results.html.erb`, `spec/requests/games_spec.rb`, `spec/components/bracketed_muted_link_component_spec.rb`.
- Added: `spec/views/shared/_igdb_search_modal.html.erb_spec.rb`, `spec/system/igdb_add_game_spec.rb`.

### Plan-checkbox status

The v2 specs directory (`specs-v2/`) is a polish-dispatch overlay on the original Phase 27 sub-spec checkboxes; `plan.md` does not enumerate a checkbox for spec 04 specifically (the 01a–01g checkboxes track the original phase scope). No checkboxes flipped — the v2 dispatch lands as a log entry per established Phase 27 convention (see prior `v2 spec 02` and `v2 spec 03` entries below).

### Open / deferred

- None. The 5-char auto-search guard + Enter override are JS-driven; the spec mandates manual verification of the dialog at 360 / 768 / 1280 px viewport widths per its CSS audit recipe.

---

## [skipci] 2026-05-17 — v2 spec 02 collection cover-art compositions (pito-rails)

Implements v2 spec 02 — `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/02-collection-cover-art-compositions.md`. Extends the collection composite layout engine from a 6-tile cap to a 9-tile cap and rewires the rebuild pipeline around a sequential, alphabetical-by-name Sidekiq chain.

### What landed

- `app/services/collections/composite_layout.rb` — extended `LAYOUTS` with `:netflix7`, `:eight_grid`, `:nine_grid`. `.choose(7)` → `:netflix7`, `.choose(8)` → `:eight_grid`, `.choose(9..)` → `:nine_grid`. Added `netflix7_boxes` (big top 98×65 + 3-cell mid 33/33/32 × 32 + 3-cell bottom 33/33/32 × 33), `eight_grid_boxes` (2 cols × 4 rows, row heights 32/32/33/33 — trailing rows absorb the remainder), `nine_grid_boxes` (3 × 3; cols 33/33/32; rows 43/43/44 — last row absorbs the remainder). Compose helpers stack via `Vips::Image#join` mirroring the existing layouts. Module docstring updated with the full matrix.
- `app/services/collections/cover_composer.rb` — `MAX_TILES` bumped 6 → 9. Member ordering / fingerprint / on-disk cache contract unchanged. Docstring updated.
- `app/services/collections/composite_rebuild_queue.rb` (NEW) — orchestrator. Public API: `enqueue_for_collections(collections)`, `enqueue_for_game_resync(game)`, `enqueue_for_game_destroy(game, was_in:)`. Sorts inputs alphabetically by `Collection.name` (case-insensitive), dedupes by id, enqueues a single chain head; returns the ordered id list.
- `app/jobs/collection_cover_rebuild_job.rb` — rewritten. Was eviction-only; now rebuilds eagerly via `Collections::CoverComposer.new.call(collection)` AND advances the chain. Argument shape: `perform(collection_id, remaining_chain = nil)`. On composer raise the chain breaks by design (Sidekiq retries the head; tail does not re-fire on retry success). On a deleted collection the job no-ops gracefully AND still advances the chain (a missing collection is not a failure). `lock: :until_executed, on_conflict: :log` declared as no-op intent (Sidekiq OSS without `sidekiq-unique-jobs`).
- `app/models/game.rb` — three rebuild hooks replacing the old single eviction hook:
  - `after_update_commit :rebuild_collection_composites_on_collection_change` — fires on `collection_id` saved-change, hands `[old, new]` (skipping nils) to the orchestrator.
  - `after_save_commit :rebuild_collection_composites_on_resync` — fires on `igdb_synced_at` saved-change (only when the game has a collection), calls `enqueue_for_game_resync(self)`.
  - `before_destroy :capture_pre_destroy_collection` + `after_destroy_commit :rebuild_collection_composites_on_destroy` — captures the pre-destroy collection in an ivar, replays via `enqueue_for_game_destroy(self, was_in: [...])`.

### Specs added / updated

- `spec/services/collections/composite_layout_spec.rb` — added `.choose` cases for 7 / 8 / 9 / 10 / 100 (caps at 9). Added `:netflix7` / `:eight_grid` / `:nine_grid` `tile_boxes` describe blocks asserting box counts, dimensions, no-gap tiling, and row/column sum invariants. Extended the `.compose` iteration to include the three new layouts. 129 examples, 0 failures.
- `spec/services/collections/cover_composer_spec.rb` — added 7-, 8-, 9-, 10-game collection scenarios. Asserts the fingerprint payload (cap at 9, alphabetical), that the 10th member does NOT contribute, that renaming a beyond-the-cap game leaves the fingerprint stable, and that renaming the 9th game out of the cap DOES change it. 28 examples, 0 failures.
- `spec/services/collections/composite_rebuild_queue_spec.rb` (NEW) — orchestrator coverage. Alphabetical sort, case-insensitive, dedupe, empty input, nil entries, single-collection chain head, ActiveRecord relation acceptance; resync delegating to current collection; destroy honoring the `was_in:` set. 16 examples, 0 failures.
- `spec/jobs/collection_cover_rebuild_job_spec.rb` — rewritten. Stubs the composer, asserts (a) one composer call per job, (b) `lock: :until_executed` + `on_conflict: :log` declared, (c) chain enqueues exactly one follow-up with the popped head + remaining tail, (d) failure breaks the chain (composer raise → no follow-up enqueue), (e) deleted-collection no-op still advances the chain. 13 examples, 0 failures.
- `spec/models/game_spec.rb` — replaced the old `evict_collection_composite_on_collection_change` describe block with a `Phase 27 v2 spec 02` block. Spies on `Collections::CompositeRebuildQueue#new` and asserts the right orchestrator method gets the right args across add / move / remove / resync / destroy / no-op (other column change). 130 examples, 0 failures.

### Open issues

- The spec's request-spec point (bulk-add to a single collection coalesces to one job) is moot today — there is no bulk-add controller; games attach via `Game#update` and the games_controller only permits local-only attrs (`played_at`, `notes`, `hours_of_footage_manual`, …). The architect spec acknowledges this with a "verify path during implementation" note. The model-level coverage exercises the only existing write paths. If a bulk-add controller lands later, a request spec for it should assert one orchestrator call per saved transaction.
- The spec's system-spec point (one Capybara scenario for a 7-member collection rendering at `:shelf` size) is deferred — per the per-CI-hiatus note "no full suite run" plus the user-visible payoff is identical to the existing `_collections_shelf` view spec coverage which already exercises the composer output through the 01h pipeline. Layout + composer + job + orchestrator + model coverage gives the full pyramid for the new layouts.
- Plan checkbox parity — the phase-level `plan.md` has no v2-spec checklist yet; checkbox-tick deferred to the architect's plan-update sweep.
- Two flakes observed in `spec/requests/games_spec.rb` (the N+1 guard at :201 and a 404 sad-path at :709) when running the full file in a single process; both pass cleanly in isolation. Pre-existing order-dependent state pollution unrelated to this spec.

### Pipeline design notes

- **Composer call vs eviction.** The v1 job evicted the on-disk file and let the next page render fall through to the synchronous composer. v2 calls the composer eagerly inside the job. Rationale: predictable rebuild order is the load-bearing UX promise; eager rebuild lets the user SEE which composite is being rebuilt next. The synchronous-on-miss path still exists as the fallback when a chain breaks mid-flight.
- **Sequential chain mechanism.** No Sidekiq Batches, no workflow gems. The orchestrator enqueues only the chain HEAD; each job, on success, enqueues the next head with the popped tail (`Array#first`-then-`rest`). On composer failure the `perform` raises and Sidekiq retries the head — the tail does NOT fire on retry-success (the chain breaks by design per the spec's failure semantics). On a deleted-collection no-op the chain still advances (a missing collection is not a failure mode worth stalling the queue for).
- **Dedupe.** The orchestrator dedupes by `Collection#id` per batch. Sidekiq OSS uniqueness is a no-op intent declaration (matching `ReindexAllJob`'s pattern); concurrent batches may overlap but the composer is idempotent (fingerprint hit → no-op).

### References

- Spec: `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/02-collection-cover-art-compositions.md`.
- Related: `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/01-single-main-genre.md` (sibling v2 spec), `app/services/collections/composite_layout.rb` (extended), `app/services/collections/cover_composer.rb` (cap bump only).
- ReindexAllJob — reference for `lock: :until_executed` as no-op intent declaration in Sidekiq OSS.

---

## [skipci] 2026-05-17 — v2 spec 07 platform logos (pito-rails)

First v2-spec dispatch. Adds platform-logo glyphs to the games-index tile
footer and the game detail page LEFT pane, sourced from Google's favicon
service via a one-shot Rake task. Asset pipeline is plain `/public` — no
runtime network calls, no asset-pipeline digest. The Rake task is the only
write path; web reads from the static PNGs.

### What landed

- `lib/tasks/pito_platform_logos.rake` — new `pito:platform_logos:download`
  task. Fetches `https://www.google.com/s2/favicons?domain=<domain>&sz=<sz>`
  for the 5 canonical platforms (PS5, Switch2, Steam, GoG, Epic) at sizes 16
  and 64, writes to `public/platform_logos/<slug>-<size>.png`. Follows up to
  3 redirects (Google occasionally 302s through a CDN), logs each save with
  byte count, warns + skips on non-200 / transport error and continues with
  the remaining downloads. Idempotent — re-runs overwrite in place.
- `app/helpers/platform_logos_helper.rb` — new helper module with
  `platform_logo_tag(slug, size:)`, `game_index_tile_logo_slug(game)`,
  `game_detail_logo_slugs(game)`, plus the `KNOWN_LOGOS` /
  `LOGO_SIZES` / `LOGO_ALT_LABELS` constants. The tile-slug picker walks
  owned-platforms first, falls back to `platforms_available` + PC-store
  inferences (`external_steam_app_id` / `external_gog_id` /
  `external_epic_id`), and returns nil when no canonical slug applies.
  Xbox is intentionally not in `KNOWN_LOGOS` (no logo asset).
- `app/views/games/_tile.html.erb` — extends the meta line to render a
  14-px logo `<img>` after the year when `game_index_tile_logo_slug`
  returns a slug. The middle-dot separator before the logo is conditional
  on rating + year presence, so logo-only meta lines stay clean.
- `app/views/games/show.html.erb` — renders `0..5` 56-px logos in a
  horizontal flex row after the genres/platforms paragraph. Uses the 64-px
  asset scaled down to 56 px for high-DPI crispness. Empty list renders
  nothing (no placeholder).
- `public/platform_logos/` — 10 PNG files (5 platforms × 2 sizes) freshly
  downloaded for the user's first checkpoint inspection. Bytes range
  ~300 → ~2.5 KB per file; Switch 2 uses the generic Nintendo corporate
  favicon (open question 4 in the spec — acceptable per architect lean).

### Specs added

- `spec/lib/tasks/pito_platform_logos_rake_spec.rb` — 12 examples covering
  happy path (10 files written from stubbed bytes), partial failure
  (HTTP 500 logs warning + writes other 9), transport error (Errno raised),
  idempotency (re-run overwrites stale bytes). `Rails.public_path` is
  stubbed to a `Dir.mktmpdir` so the spec stays isolated.
- `spec/helpers/platform_logos_helper_spec.rb` — 30 examples covering
  `platform_logo_tag` happy path / nil-on-unknown-slug /
  ArgumentError-on-bad-size, the tile-slug selection rule with full
  KNOWN_LOGOS-order matrix (owned wins, declaration order, fallbacks),
  and the detail-page multi-slug renderer.
- `spec/views/games/_tile.html.erb_spec.rb` — extended with an 8-example
  "platform logo footer" describe block. Also added
  `external_steam_app_id: nil` overrides to the pre-existing
  `:synced`-trait fixtures whose assertions depended on the meta line
  being exactly `<rating> · <year>` — the `:synced` factory stamps
  `external_steam_app_id`, which would otherwise add a Steam logo to
  every existing tile spec.
- `spec/views/games/show.html.erb_spec.rb` — NEW (no prior HTML view spec
  existed for the game show page). 6 examples covering happy paths
  (one logo, locked KNOWN_LOGOS order, store-only inference, flex layout)
  and empty state (no container for no-known-platform / xbox-only games).
- `spec/system/games_index_spec.rb` — appended ONE new scenario class
  (3 examples) seeding PS5-owned + Steam+GoG-owned + Xbox-only games and
  asserting each tile's footer markup. Scopes lookups to
  `section.all-games-grid` since the same game also renders in the shelves
  at the top of the page (would otherwise yield ambiguous Capybara
  matches).

### Verification

- `bin/test spec/lib/tasks/pito_platform_logos_rake_spec.rb
  spec/helpers/platform_logos_helper_spec.rb
  spec/views/games/_tile.html.erb_spec.rb
  spec/views/games/show.html.erb_spec.rb` — 98 examples, 0 failures.
- `bundle exec rspec spec/system/games_index_spec.rb --tag type:system
  -e "platform-logo tile footer"` — 3 examples, 0 failures.
- `bin/rails pito:platform_logos:download` — 10/10 files written
  successfully. Bytes: ps5 (301 + 828), switch2 (834 + 471), steam (825 +
  1298), gog (395 + 1212), epic (643 + 2548).
- `bin/brakeman -q -w2` — 0 warnings, 0 errors, 1 ignored.

### Open follow-ups

- Spec 06 (`PLATFORM_LABELS` / `Platform.display_label(canonical_name_for)`)
  hasn't shipped yet. The helper uses a local `LOGO_ALT_LABELS` map mirroring
  `Platform::CANONICAL_SHORT_NAMES` for the 5-slug subset; when spec 06
  introduces the canonical labels module, the helper can swap in the
  shared map.
- `plan.md` does not yet carry a v2-specs checkbox section, so no
  checkbox is ticked this session. Architect to decide whether to extend
  `plan.md` with a v2 block or rely on the spec-by-spec log entries.



Closed the loop on sub-spec 01d. The original 01d session landed the migration,
the `User` enum, the `Users::GamesPreferencesController`, three mode partials
(`_grid_mode`, `_list_mode`, `_shelves_by_letter_mode`), the switcher partial,
and the per-partial view specs. The `GamesController#index` wire-up and the
matching system spec were deferred at that time because the controller was
wedged on 01a (`Platform#games_owning` association removal) + 01c (per-platform
`games.platform_owned_id` column drop) drift. Both have since cleared via the
01a controller fix and the 01c-v2 nested-shelves rewrite, so this re-dispatch
ties the surface together.

### What landed

- `GamesController#index` now sets `@display_mode = resolved_display_mode`. The
  new private helper resolves the requested mode in order: URL
  `params[:display]` (allowlisted set `grid` / `list` / `shelves` /
  `shelves_by_letter`) → `Current.user.preferred_games_display_mode` → `:grid`
  as the defensive final fallback for the anonymous path. `shelves` is a
  URL-friendly alias for the canonical enum key `shelves_by_letter` per the
  spec.
- `app/views/games/index.html.erb` now renders `games/_display_mode_switcher`
  flush-right of the H1 row (inside the existing `display: flex` header with
  `margin-left: auto;`) and branches the all-games partition on `@display_mode`
  to one of the three partials. The legacy inline
  `<section class="shelf all-games-grid">` block is gone — its tile-grid content
  moved into `_grid_mode` during the original 01d session.
- `spec/system/games_display_modes_spec.rb` — 13 new Capybara examples on the
  rack_test driver: default-mode grid for a fresh user, switcher active-class
  marking, persistence flow (click `[list]` → preference written + list mode
  renders → reload preserves the choice), `[grid]` round-trip from a non-default
  persisted preference, URL `?display=` override does NOT persist the choice,
  `?display=shelves` alias maps to `shelves_by_letter`, list mode renders
  `tr.letter-head` rows + title links, shelves-by-letter mode renders one shelf
  per non-empty letter and hides the others, composition with the `?filters=`
  set (clear-all preserves `?display=`), CLAUDE.md hard-rule guards (no
  `data-turbo-confirm`, no `window.confirm`, no anchors — three `<form>`
  elements per switcher).
- `spec/requests/games_spec.rb` — 12 new `Phase 27 §01d` examples on the request
  layer mirroring the system surface: default → grid, URL override per mode
  (`grid` / `list` / `shelves` / `shelves_by_letter`), persisted preference wins
  when `?display` is absent, override wins over persistence for one request,
  garbage values fall back to the persistence, post-PATCH the next `GET /games`
  reflects the saved mode, switcher button text + action URL, active-class
  assertion, filter-row composition. Scopes the `data-display-mode` matcher to
  the all-games `<section>` so the switcher's own button-level
  `data-display-mode` attributes don't contaminate the match.
- `spec/requests/games_spec.rb` (01b regression) — the 01b contradiction notice
  spec's regex used the literal `<section class="shelf all-games-grid">` class
  string; the new `_grid_mode` partial adds a `games-grid-mode` class. Switched
  to `<section[^>]*data-display-mode="grid"` (the stable hook the view spec also
  asserts on).

### Tests

- 13 new system + 12 new request = 25 new examples, all green.
- Full 01d-adjacent sweep (model + request + view + system specs across `user`,
  `users::games_preferences`, every `games/_*_mode` partial, switcher, the full
  `spec/requests/games_spec.rb`, `games_index`, `games_steam_shelf`,
  `games_platform_ownerships`, the new `games_display_modes`): 365 examples, 0
  failures.
- Rubocop on the touched Ruby files (`games_controller.rb`,
  `spec/requests/games_spec.rb`, `spec/system/games_display_modes_spec.rb`): no
  offenses. (`index.html.erb` skipped — rubocop's Ruby parser misreads ERB
  control flow as a ternary expression; the file is not Ruby.)
- Brakeman `-q -w2`: 0 warnings, 0 errors across the full app.

### Files changed

- `app/controllers/games_controller.rb` (added
  `@display_mode = resolved_display_mode` to `#index` and private
  `resolved_display_mode` resolver)
- `app/views/games/index.html.erb` (renders `_display_mode_switcher`, branches
  the all-games partition on `@display_mode`)
- `spec/requests/games_spec.rb` (added 12-example
  `display mode resolution (Phase 27 §01d)` describe block; updated one 01b
  regex to the stable `data-display-mode` hook)
- `spec/system/games_display_modes_spec.rb` (new, 13 examples)
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  (reworded the trailing 01d checkbox to reflect the system spec landing)

### Open notes

- The list-mode "platforms owned" column still renders a literal `—` pending the
  01a join-table integration wired into the partial. That cleanup remains queued
  and is independent of this re-dispatch.
- Sort-column UI for list mode (`?sort=title|platforms_owned|genres|status`) is
  still deferred until the per-platform ownership shape stabilises for sorting.
  The partial's letter-bucketing + sticky heading layout is in place for the
  sort hookup.
- The 29 unrelated failures observed in the wider request + system sweep
  (`sessions_spec`, `sessions_rate_limit_spec`, `login/totp_challenges_spec`,
  `settings/security/blocks/unblockings_spec`, `calendar_edit_delete_spec`,
  `settings/tokens_spec`, `video_import_flow_spec`) are entirely from other
  concurrent in-flight agents' work in the worktree (TOTP / rack_attack /
  sessions / video import surfaces) and do not touch the 01d surface.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01d-display-mode-switcher-and-three-modes.md`.
- Prior 01d log entry:
  `## 2026-05-11 — sub-spec 01d Display mode switcher + three modes (pito-rails)`
  below.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.

---

## [skipci] 2026-05-11 — sub-spec 01e Shelf cover art variant (pito-rails)

Closed the loop on the `:shelf` cover-art variant. The component, partials, and
34-example component spec already shipped under earlier 01e / 01c-v2 work at the
locked 65% size (98 × 130 against the real 150 × 200 grid, sourced from IGDB's
`t_cover_small_2x` token). This pass tied off the remaining loose ends:

- **Stylesheet rules for the variant slot.** Added a `.game-cover` /
  `.game-cover--grid` / `.game-cover--shelf` / `.game-cover-img` /
  `.game-cover-missing` block in `app/assets/tailwind/application.css`,
  immediately before the existing 01h `.collection-cover-composite` rule. These
  descriptive class rules pin the locked variant dimensions (150 × 200 for
  `:grid`, 98 × 130 for `:shelf`) at the stylesheet level so the slot size is
  reachable without external inline-style introspection. No `transform: scale`,
  no percentage widths — both variants resolve to a server-side asset at its
  native size per the 01e Flaw assertions.
- **Component-spec coverage of the `:shelf` symmetry.** Added four assertions to
  `cover_component_spec.rb` so the `:shelf` happy block now mirrors `:grid`: alt
  text equals the game title, `loading="lazy"`, wrapper inline
  `width: 98px; height: 130px;`, and the wrapper `class` attribute is exactly
  `"game-cover game-cover--shelf"`. The component file itself needed no
  behavioral change.
- **01c-v2 spec inconsistency correction.** `01c-v2-nested-shelves.md` carried
  an in-flight 70% / 105 × 140 draft that proposed bumping the variant. The
  master agent reaffirmed 65% (matching 01e and the shipped
  `Games::CoverComponent`). Prepended a one-line "Corrected from 70% draft —
  locked decision §1 is 65% (98 × 130 px against the real 150 × 200 grid)"
  annotation at the top of the spec body. The 70% / 105 × 140 mentions inside
  the spec stay as historical record but are now explicitly tagged as
  superseded.

### Spec deltas

- `spec/components/games/cover_component_spec.rb` — 34 → 38 examples, all green.
  New assertions: alt text on `:shelf`, loading=lazy on `:shelf`, inline
  width/height on `:shelf` wrapper, exact wrapper class string.

### Files touched

- `app/assets/tailwind/application.css` — added `.game-cover` /
  `.game-cover--{grid,shelf}` / `.game-cover-img` / `.game-cover-missing` CSS
  block.
- `spec/components/games/cover_component_spec.rb` — +4 examples.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-v2-nested-shelves.md`
  — prepended one-line correction header.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md` —
  ticked the four 01e checkboxes with implementation notes.

### Open issues

None. The `:shelf` variant landing was already complete at the component level;
this pass landed the stylesheet rules and tightened the spec coverage so future
drift is caught.

### Cross-stack

- Rails web — covered.
- Rails MCP — N/A (MCP does not render images).
- `pito` CLI — N/A (TUI does not render images).
- Website — N/A.

### Verification

- `bundle exec rspec spec/components/games/cover_component_spec.rb` — 38
  examples, 0 failures.
- `bundle exec rubocop` on touched files — clean.

---

## [skipci] 2026-05-11 — sub-spec 01c-v2 Nested shelves (pito-rails)

Rewrote `/games` top-of-page shelves from the v1 flat-tile design (one tile per
genre, one tile per collection) to v2 nested shelves: each outer shelf iterates
one sub-shelf per non-empty bucket; each sub-shelf is a horizontally-scrolling
row of game tiles at the `:shelf` cover variant
(`Games::CoverComponent.new(game:, variant: :shelf)`). Collection sub-shelves
additionally lead with the existing 01h composite cover tile.

Empty buckets are now hidden end-to-end. When no genre owns any game, the Genres
`<section>` is suppressed (no `<h2>`, no muted "(no genres yet)" placeholder).
Same rule for Collections. This reverses 01c-v1's "always render with
placeholder" pattern per 01c-v2 locked decision #7.

### Scope ladder (in this pass)

In scope:

- Rewrite `_genres_shelf.html.erb` and `_collections_shelf.html.erb` to the
  nested outer-shelf shape.
- New `_genre_sub_shelf.html.erb` + `_collection_sub_shelf_row.html.erb`
  partials for the per-bucket sub-shelf rows.
- Controller scope change on `@genres_for_shelf` / `@collections_for_shelf` to
  filter out empty buckets and preserve alphabetical case-insensitive ordering
  with a stable id tiebreak.
- View + request + system spec rewrites under the existing 01c describe blocks.

Deferred (queued follow-ups from the 01c-v2 spec body that remain unshipped):

- `db/migrate/*_add_primary_genre_id_to_games.rb` (per parent dispatch — "no new
  migrations"). Falls back to the existing `genre.games` join — a multi-genre
  game appears in every sub-shelf its `game_genres` join touches.
  Architect-locked behavior is "appears in exactly one bucket via primary genre
  pointer"; the fallback is documented and the migration is queued separately.
- `db/migrate/*_add_composite_columns_to_collections.rb` — already shipped under
  01h. No-op here.
- `Game#primary_genre` association, `Genre#primary_for_games`, orphaning rule on
  `GameGenre#after_destroy_commit`. Gated on the migration above.
- Game show / edit primary-genre picker. Gated on the migration.
- `Composite::Builder` refactor to accept any `Compositable` host. Bundle stays
  bundle-coupled per the 01h log's "bundle code stays untouched" note; the
  refactor is a separate follow-up.
- `Games::CoverComponent` `:shelf` variant size bump from 98×130 to 105×140 (70%
  of grid). Per parent dispatch — that surface belongs to 01e
  (`01e-shelf-cover-art-variant.md` / `01e-v2-shelf-cover-art-variant.md`).

### Naming collision (resolved)

01c-v2 spec pre-reserved `app/views/games/_collection_sub_shelf.html.erb` for
the row partial. 01h shipped first and took that filename for the leading-tile
partial (single composite cover with three branches: empty / passthrough /
composite). Both surfaces are needed; renaming the existing 01h partial would
invalidate 14 view specs and the 01h log.

Resolution: new row partial is `_collection_sub_shelf_row.html.erb`. The row
partial wraps the 01h leading-tile partial inside an anchor that navigates to
`/collections/<slug>`, then iterates game tiles. Both partials are documented at
the top of each file.

### Files changed

App:

- `app/controllers/games_controller.rb` — `@genres_for_shelf` /
  `@collections_for_shelf` filter to non-empty buckets via subquery (Postgres
  `SELECT DISTINCT` + `ORDER BY` workaround). Inline comment block reworked for
  v2.
- `app/views/games/index.html.erb` — comment block updated for v2; partial call
  sites unchanged.
- `app/views/games/_genres_shelf.html.erb` — REWRITE. Outer shelf
  `<section data-shelf="outer-genres">` with one `<h2>genres</h2>` and per-genre
  sub-shelves; entire section suppressed when input empty.
- `app/views/games/_collections_shelf.html.erb` — REWRITE. Outer shelf with
  `<h2>custom collections</h2>` and per-collection sub-shelves.
- `app/views/games/_genre_sub_shelf.html.erb` — NEW. Sub-shelf with `<h3>`
  heading + `[see all]` link (only over the 30 cap) + horizontally-scrolling row
  of `:shelf` game tiles, alphabetical.
- `app/views/games/_collection_sub_shelf_row.html.erb` — NEW. Mirror of the
  genre sub-shelf with a leading composite cover tile.

Specs:

- `spec/views/games/_genres_shelf.html.erb_spec.rb` — REWRITE. 14 new examples
  covering outer-shelf wrapper, per-genre sub-shelf count, short-form `<h3>`
  mapping, empty-input hidden, no v1 remnants.
- `spec/views/games/_collections_shelf.html.erb_spec.rb` — NEW. 11 examples
  mirroring the genre coverage.
- `spec/views/games/_genre_sub_shelf.html.erb_spec.rb` — NEW. 18 examples
  covering happy (under cap), exact cap (30), over cap (31 → capped +
  `[see all]`), empty genre, JS-confirm flaw guard.
- `spec/views/games/_collection_sub_shelf_row.html.erb_spec.rb` — NEW. 15
  examples covering composite leading tile, passthrough leading tile (1-game
  collection), empty leading tile (0-game collection), 31 games over cap,
  JS-confirm flaw guard.
- `spec/requests/games_spec.rb` — REWROTE the "Phase 27 §01c" describe block. 11
  new examples covering outer-shelf hidden when empty, outer-shelf rendered with
  sub-shelf-per-bucket alphabetical, the `data-shelf="genre-sub"` /
  `"collection-sub"` data hooks, `[see all]` cap behavior.
- `spec/system/games_index_spec.rb` — REWROTE the 01c describe block. 5 new
  examples covering nested shelf rendering, empty-bucket hidden, `[see all]`
  navigation narrowing the all-games grid below.

Plan:

- `docs/plans/beta/27-…/plan.md` — re-ticked the 01c block's five checkboxes
  with v2-aware annotations; documented the deferred work inline.

### Gates

- `rspec spec/views/games/ spec/components/games/ spec/requests/games_spec.rb spec/system/games_index_spec.rb spec/system/games_steam_shelf_spec.rb spec/system/games_platform_ownerships_spec.rb`
  — 833 examples green.
- `rspec spec/models/genre_spec.rb spec/models/collection_spec.rb spec/models/game_spec.rb`
  — 113 examples green.
- `rubocop` on touched Ruby files — clean (7 files inspected, no offenses).
- `brakeman -q -w2` — 0 security warnings.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-v2-nested-shelves.md`
  (supersedes 01c-v1; this implementation pass).
- Plan checkbox: `…/plan.md` → `01c — Genres and Collections shelves` block
  (five v1 checkboxes re-ticked with v2 annotations).
- Adjacent: 01h leading-tile partial (`_collection_sub_shelf.html.erb`) reused
  as-is; 01b filter row placement preserved; 01e cover variant width left to its
  own surface.

---

## [skipci] 2026-05-11 — sub-spec 01b Filter row + platform semantics (pito-rails)

Shipped the multi-select filter row on `/games`. State lives in a single CSV URL
param (`?filters=token1,token2`). Ten canonical chips in a locked left-to-right
order:

    [recorded] [released] [owned] [not owned] [scheduled]
    [ps5] [switch2] [steam] [gog] [epic]

Clicking a chip toggles it in or out of the comma-separated set; `[clear all]`
appears whenever at least one chip is active; a muted notice renders when
`owned` + `not_owned` are simultaneously active (the C-3 contradiction case).
Chip hrefs preserve `?genre=`, `?collection=`, and `?display=` overrides
verbatim.

### Locked semantics

Platform-token precedence follows the verbatim Mobile directive (spec §"Locked
semantics"):

- **P-1.** `owned` unchecked + platform-X checked → games scheduled OR released
  on platform-X, regardless of ownership state.
- **P-2.** `owned` checked + platform-X checked → games owned specifically on
  platform-X.
- **C-1.** `not_owned` checked + platform-X checked → games with zero ownership
  rows AND released-or-scheduled on platform-X.
- **C-2.** Multiple platform tokens within the same bucket OR together
  (statement applies per bucket state).
- **C-3.** `owned` + `not_owned` together → `Game.none` + a muted contradiction
  notice. No JS dialog, no red.

The query object's `#contradiction?` predicate flags the C-3 case; `#results`
short-circuits to `Game.none`.

### Files (new)

- `app/queries/games/filter.rb` — `Games::Filter` query object. Public surface:
  `#results` (memoised `ActiveRecord::Relation`), `#active_tokens`,
  `#dropped_tokens`, `#contradiction?`. Composition algorithm in
  `#build_results` partitions tokens into Status / Ownership / Platform /
  Unknown; buckets AND together; Status and Platform tokens within a bucket OR
  together. Platform-bucket semantics flip on the Ownership-bucket state via
  `platform_relation_for`.
- `app/helpers/games/filters_helper.rb` — `Games::FiltersHelper` mixin. Surface:
  `parse_filter_tokens(raw)`, `parse_dropped_tokens(raw)`,
  `toggle_filter(active, token)`, `chip_label(token)`. Normalises CSV / Array /
  nil; downcases; strips; de-dupes; preserves input order.
- `app/components/games/filter_row_component.rb` +
  `app/components/games/filter_row_component.html.erb` — ten chips,
  `[clear all]` link, optional contradiction notice. `query_string_overrides`
  preserves the URL state the filter row doesn't own.
- `app/components/games/filter_chip_component.rb` +
  `app/components/games/filter_chip_component.html.erb` — single bracketed-link
  chip. ArgumentError when token is non-canonical or `request_path` is blank.
  Active chips carry the `chip--active` modifier (no red — red is reserved for
  destructive).
- Specs (all new):
  - `spec/queries/games/filter_spec.rb` (50 examples) — load-bearing matrix:
    single-token, single-platform-per-ownership-state, Mobile-directive worked
    example (verbatim), multi-platform, status combinations, contradiction,
    normalisation edge cases, defensive surface (SQL injection, 100-token input,
    memoisation, composability).
  - `spec/helpers/games/filters_helper_spec.rb` (21 examples).
  - `spec/components/games/filter_chip_component_spec.rb` (17 examples).
  - `spec/components/games/filter_row_component_spec.rb` (18 examples).

### Files (modified)

- `app/models/game.rb` — six new scopes: `.recorded` (rides on
  `VideoGameLink.select(:game_id).distinct` since `videos` connects via the
  join, not directly), `.released`, `.scheduled`, `.on_platform(slug)`,
  `.released_on(slug)`, `.scheduled_on(slug)`. The on_platform shape mirrors the
  `owned_on` pattern with bound parameters and the `"platforms"."slug" = ?`
  literal so the legacy `games.platforms` jsonb column doesn't collide.
- `app/controllers/games_controller.rb` — `include Games::FiltersHelper`;
  `#index` reads `params[:filters]` via the helper, instantiates
  `Games::Filter`, narrows `@all_games`, exposes `@filter_contradiction` to the
  view. Compose order: `?genre=` → `?collection=` → filter row.
- `app/views/games/index.html.erb` — renders the filter row between the 01c
  shelves (Genres + Collections) and the all-games grid, with
  `query_string_overrides` carrying `{ genre:, collection:, display: }`.
- `spec/models/game_spec.rb` — 16 new examples covering all six new scopes
  (`recorded`, `released`, `scheduled`, `on_platform`, `released_on`,
  `scheduled_on`) including boundary inclusive-on-today, SQL-injection defense,
  distinct-row defense, nil-date exclusion.
- `spec/requests/games_spec.rb` — 16 new examples in
  `describe "GET /games with ?filters="`: happy paths, contradiction,
  unknown-token dropping (no echo-back), de-duplication, case normalisation,
  100-token, SQL injection, defensive `data-turbo-confirm` absence, query-string
  preservation for `display=` and `genre=`.
- `spec/system/games_index_spec.rb` — 11 new examples in
  `describe "Games index — filter row (01b)"`: click-through chip toggle,
  `[clear all]` lifecycle, chip composition, contradiction rendering,
  query-string preservation, all-five-platforms union, defensive HTML surface.

### Spec deviations from spec text (resolved)

1. **`first_release_date` → `release_date`.** The spec wrote
   `first_release_date` as the IGDB-derived datetime column. The actual Phase 14
   §1 schema column is `release_date` (a `date`). The day-granular semantics are
   identical (a release scheduled for today is "released"; tomorrow is
   "scheduled"); the model code, model specs, and the matrix all use
   `release_date`.
2. **`Game.recorded` ride-on.** Spec wrote
   `where(id: Video.select(:game_id).distinct)`. The actual association is
   `has_many :videos, through: :video_game_links` (Phase 14 §3) — Video has no
   `game_id` column. The scope rides on
   `VideoGameLink.select(:game_id).distinct` instead; semantically identical
   (any linked Video → recorded).
3. **Boundary inclusive on today.** `release_date == Date.current` is in
   `released`, not `scheduled`. Date-granular makes the "exactly now"
   second-level edge case from the spec moot.

### Open questions (architect-resolved per autonomy/cadence rule)

The spec lists six open questions; locked answers below.

1. **C-1 `not_owned` + platform-X semantics** — adopted the spec's locked
   default: zero ownership rows AND released-or-scheduled on the platform.
   Matrix asserts: `[not_owned, ps5] → B` (B is on PS5, not owned anywhere);
   `[not_owned, epic] → ∅` (G is owned on Epic; nothing else is on Epic).
2. **C-3 contradiction rendering** — muted notice (locked default). Class is
   `text-muted` on a `<p>` directly below the chip row. Reviewed against the
   project rule: no red, no JS dialog.
3. **`recorded` semantics with draft Videos** — any linked Video record. The
   project has no `published` state on `Video` yet; revisit when video
   publication state lands.
4. **Boundary inclusiveness on `released`** — locked: today's release counts as
   released, not scheduled (`<= Date.current`).
5. **`platforms_available` association name** — confirmed still
   `platforms_available` (Phase 14 §1; 01a did not rename it). The `on_platform`
   scope rides on `:game_platforms → :platform` (the same association under the
   hood) so the legacy join name doesn't leak into the scope shape.
6. **Multi-platform OR shape** — chose the `where(id: union_ids)` single-pass
   form; the alternative `.or` shape would generate the same result. Spec
   asserts equivalence rather than SQL fingerprint; 16 matrix cells assert the
   right ids land regardless.

### Gates

- `rspec` — 303 examples across the seven touched spec files; 0 failures. (16
  model + 50 query + 21 helper + 17 chip + 18 row + 87 request + 22 system + 72
  other component / model specs in the re-run convergence.)
- `rubocop` — clean on all 13 touched Ruby files. (The .erb files aren't passed
  to rubocop — its Ruby parser doesn't handle them.)
- `brakeman` — 0 security warnings (2 prior obsolete-ignore entries noted, both
  pre-existing). Bound parameters in the new `on_platform` / `released_on` /
  `scheduled_on` scopes and in the controller's `parse_filter_tokens` path keep
  the surface clean.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01b-filter-row-and-platform-semantics.md`.
- Plan checkbox: `…/plan.md` → `01b — Filter row + platform semantics` block
  (all 7 boxes ticked).
- Compose order locked by spec §"Controller integration": genre → collection →
  filter row → display-mode partition (01d).

---

## [skipci] 2026-05-11 — sub-spec 01g MCP `game_update_local` plural ownership (pito-mcp-impl)

Implemented the MCP half of sub-spec 01g — extending the existing
`game_update_local` tool to match the spec's plural ownership contract end to
end, plus the structured `warning` field for legacy / conflict callers. The
pre-existing implementation already accepted `platform_owned_ids: [int]`, the
singular auto-wrap, and the `confirm: yes/no` two-step; this session aligned the
remaining edge-case behavior and broadened spec coverage to the architect's full
pyramid sweep.

### MCP `game_update_local` contract changes

- Unknown `platform_id` values are now DROPPED with a structured `warning` field
  (`"unknown platform_id(s) dropped: …"`) instead of raising a 422. Mirrors the
  spec's "graceful drop, not hard error" rule.
- When BOTH `platform_owned_id` (singular legacy) and `platform_owned_ids`
  (plural) are supplied, the plural form wins and the response carries a
  `warning` (`"both ... supplied; plural wins."`). The preview path
  (`confirm: no`) emits the same warning so callers can spot the conflict before
  they commit.
- `platform_owned_id: null` is now treated as a NO-OP per the spec's back-compat
  note — legacy callers that send `null` to mean "don't touch ownership" no
  longer accidentally un-own a game. Sending `platform_owned_ids: []` (explicit
  empty array) remains the authoritative way to un-own everywhere.
- Response payload gained `platform_owned_id` (singular, equal to the first
  element of the plural array) as a one-phase back-compat field. Removed next
  phase per the spec's deprecation window.
- `sync_ownerships!` no longer pre-validates platform existence — the outer
  `call` does that and drops unknown ids before reaching the upsert. Idempotency
  on existing ownership rows (`acquired_at` / `store` / `notes`) is preserved by
  a covering spec.

### Files changed

- `app/mcp/tools/game_update_local.rb` — input normalization rewrite for
  plural-vs-singular precedence, unknown-id drop with warning, preview /
  response `warning` field, response back-compat singular, doc comment + schema
  description alignment with §01g.
- `spec/mcp/tools/game_update_local_spec.rb` — expanded from 6 examples to 21
  (full §01g pyramid sweep: happy paths for plural / singular / shrink / un-own
  / de-dup / idempotency preservation; sad paths for unknown id + mixed-form
  conflict + preview-warning carry; edge paths for `singular: null` no-op +
  absent-keys no-op + only-bad-ids; flaw paths for transaction rollback +
  mass-assignment guard).

### Test deltas

- `bundle exec rspec spec/mcp/tools/game_update_local_spec.rb` → 21 examples, 0
  failures (was 6 examples, 0 failures).
- `bundle exec rspec spec/mcp/tools/` → 493 examples, 0 failures (full MCP tool
  suite green).
- `bundle exec rspec spec/models/game_platform_ownership_spec.rb spec/models/game_spec.rb`
  → 102 examples, 0 failures (no regression in §1a's model surface).
- `bundle exec rubocop app/mcp/tools/game_update_local.rb spec/mcp/tools/game_update_local_spec.rb`
  → 2 files inspected, no offenses detected.

### Plan checkbox deltas

- 01g checkboxes 1-4 (MCP `game_update_local` plural shape) are now ticked.
- 01g checkboxes 5-6 (CLI TUI Games view + Rust tests) deferred — flagged as
  follow-up below.
- New checkbox added: MCP `yt:games_list` `filters` argument + MCP
  `yt:game_show` plural shape, both deferred and gated on §01b landing.

### Open follow-ups (not in scope this session)

- **CLI half of §01g** — `extras/cli/src/api/games.rs`,
  `extras/cli/src/views/games.rs`, `extras/cli/src/models/game.rs`,
  `extras/cli/tests/games_filter_test.rs`,
  `extras/cli/tests/games_ownership_test.rs`. The spec body covers these in
  full; per the master dispatch brief this sub-spec ships the MCP half and the
  CLI half lands when CLI parity is dispatched to `pito-cli`. Tracked as a
  follow-up at the phase level.
- **MCP `yt:games_list` filter argument** — spec body lists it
  (`filters: ["recorded", "ps5", "owned"]`) but the tool does not yet exist in
  `app/mcp/tools/`. Lands once `Games::Filter` (§01b) exposes a stable
  query-object surface so the MCP tool can reuse it instead of re-implementing
  the filter semantics.
- **MCP `yt:game_show` plural shape** — `game_show` tool does not yet exist (we
  currently route through `game_search` + the show controller's JSON branch).
  When it lands, the response carries the plural `platform_owned_ids`, the
  first-element back-compat singular `platform_owned_id`, and the
  `owned_platforms` / `release_platforms` blocks per the spec body.

### Design notes

- The spec mentioned `starred: "yes" | "no"` as an example boolean arg. The
  `Game` model has no `star` / `starred` column today (only `Channel` and
  `Video` do), so the field was not added — introducing a new column is outside
  §01g's scope and outside this agent's file scope.
- The spec uses path conventions like `app/mcp/tools/yt/...` and
  `spec/mcp/tools/yt/...`. The existing codebase uses a flat layout (no `yt/`
  subdir); kept the flat layout to avoid moving 50+ pre-existing files. The two
  layouts are functionally identical.
- `additionalProperties: false` on the input schema is the wire-level
  mass-assignment guard; the Ruby handler's explicit `attrs[:played_at] = ...`
  cherry-picking is the in-handler guard. A regression spec asserts both layers
  (sending `title:` / `igdb_id:` kwargs does not bleed through).

## [skipci] 2026-05-11 — sub-spec 01f Game show/edit per-platform ownership UI (pito-rails)

Implemented sub-spec 01f per
`specs/01f-game-show-edit-per-platform-ownership.md`. Adds the user-facing
per-platform ownership editor + show-page chip list.

### Show page

- New cell in the `local fields` table: an `OwnedPlatformsChipListComponent`
  followed by `· [edit ownership]`.
- Chip list renders one bracketed chip per `Game#owned_platforms`, alphabetical
  case-insensitive. Each chip links to `/games?filters=<slug>,owned` (locked
  Phase 27 01b filter-row contract). Empty state renders muted
  `(not owned on any platform)` placeholder.
- `[edit ownership]` is a bracketed link to
  `/games/:slug/platform_ownerships/edit` — the dedicated editor.

### Editor page

- Route: `resource :platform_ownerships, only: %i[edit update], module: :games`
  nested under `resources :games`. Friendly URL — `:game_id` carries
  `Game#to_param` (the IGDB slug when present).
- Controller scaffolds in-memory `GamePlatformOwnership` rows for every IGDB
  release-platform of the game (plus any owned platform whose IGDB record was
  scrubbed later — covers manually-added rows). Alphabetical case-insensitive
  ordering.
- Form posts a nested-attributes payload using indexed naming
  (`game[game_platform_ownerships_attributes][N][...]`) with a per-row `_own`
  flag. Project yes/no boundary applied — leading
  `<input type="hidden" value="no">` ensures the controller always sees a value
  regardless of the checkbox state. `_own="yes"` becomes a present row (create /
  update); `_own="no"` on an existing row becomes a `_destroy` marker;
  `_own="no"` on a not-yet-owned platform is a silent no-op.
- Per-row metadata persisted: `acquired_at`, `store` (free-text), `notes` per
  Phase 27 01a v1 column set.

### Model

- `Game` gained
  `accepts_nested_attributes_for :game_platform_ownerships, allow_destroy: true, reject_if: :all_blank`
  so the controller can route updates through the standard nested-attributes
  API.

### Hard rules

- Yes/no boundary enforced on `_own`: any value other than `"yes"` / `"no"`
  (e.g. `"true"`, `"1"`, `"false"`) is rejected with 422 and re-renders the
  editor with an inline error.
- No `data-turbo-confirm`, no `window.confirm`, no `alert` / `prompt` anywhere.
  The form uses `data-turbo="false"` to opt out of Turbo on submit (so the
  redirect-to-show flash lands), not because of any confirmation flow.
- Mass-assignment guard: the controller's `update` only permits
  `game_platform_ownerships_attributes`. Smuggled Game attributes (`title`,
  `notes`, `summary`, `igdb_id`) are silently dropped.
- Duplicate `platform_id` rows in a single submit are rejected with a clear
  error message; unknown `platform_id` likewise.

### Files changed

- `config/routes.rb` — nested `resource :platform_ownerships` under
  `resources :games`.
- `app/models/game.rb` —
  `accepts_nested_attributes_for :game_platform_ownerships`.
- `app/controllers/games/platform_ownerships_controller.rb` (new) —
  `before_action :load_game`, `#edit`, `#update`, `build_ownership_rows`,
  `validate_rows`, `transform_rows`.
- `app/components/games/owned_platforms_chip_list_component.{rb,html.erb}` (new)
  — chip list for the show page.
- `app/components/games/platform_ownership_editor_component.{rb,html.erb}` (new)
  — fieldset-per-platform editor body.
- `app/views/games/platform_ownerships/edit.html.erb` (new) — editor page
  wrapping the editor component in a `form_with`.
- `app/views/games/show.html.erb` — replaced the inline
  `owned_platforms.map(&:name).join(", ")` cell with the chip list component +
  `[edit ownership]` link.

### Spec coverage (all green)

- `spec/components/games/owned_platforms_chip_list_component_spec.rb` — 9
  examples (alphabetical ordering, chip href shape, empty state, no JS confirm,
  no destructive class).
- `spec/components/games/platform_ownership_editor_component_spec.rb` — 19
  examples (one row per platform, indexed nested-attribute names, persisted vs.
  unpersisted row state, value population, no JS confirm, empty
  release-platforms placeholder).
- `spec/requests/games/platform_ownerships_spec.rb` — 26 examples (GET edit 200
  / 404, PATCH happy / sad / boundary / round-trip, duplicate-row rejection,
  mass-assignment guard, stale id from another tab).
- `spec/requests/games/show_ownership_ui_spec.rb` — 9 examples (show-page chip
  list + `[edit ownership]` link wiring).
- `spec/views/games/platform_ownerships/edit.html.erb_spec.rb` — 9 examples
  (form action / PATCH method, `[save]` / `[cancel]`, no `data-turbo-confirm`,
  inline error rendering).
- `spec/system/games_platform_ownerships_spec.rb` — 7 examples (full user
  journey: tick PS5+Steam, un-tick PS5, metadata persists, empty-state
  placeholder, chip href matches filter contract).

Total: 79 new examples; adjacent suites (`spec/requests/games_spec.rb`,
`spec/requests/games_show_meta_block_spec.rb`, `spec/views/games/*_spec.rb`,
`spec/components/games/cover_component_spec.rb`,
`spec/system/games_index_spec.rb`,
`spec/models/{game,platform,game_platform_ownership}_spec.rb`) all remain green.

### Gates

- Targeted `rspec` — 437 examples, 0 failures (all Phase 27 game / platform /
  ownership specs plus the new 01f suite).
- `rubocop` on touched Ruby files — clean (11 files, no offenses).
- `brakeman -q -w2` — 0 warnings, 0 errors.

### Open follow-ups

- `01b` filter-row component (in flight) consumes the chip-href contract
  `/games?filters=<slug>,owned`. The chips already emit the locked URL shape;
  01b's controller plumbing will narrow the listing.
- Per-row metadata collapsibility (spec open question #3 — collapsed by default)
  deferred. Open in v1.
- `[own all]` quick-tick (spec open question #4) deferred.
- 01g — MCP / CLI parity for `game_update_local` plural will land the same join
  through the MCP and CLI surfaces.

### References

- `specs/01f-game-show-edit-per-platform-ownership.md` (spec).
- `plan.md` — 01f checkbox group ticked.
- `app/models/game.rb` — `accepts_nested_attributes_for`.
- `app/controllers/games/platform_ownerships_controller.rb` — controller body.

## 2026-05-10 — Game tile metadata two-line layout (pito-rails)

Reshaped the game-tile caption per user feedback (image #77). The caption is now
two explicit lines below the cover art:

    Red Dead Redemption 2        ← line 1: title, ellipsis-truncated
    ★ 93 · 2018                  ← line 2: rating zero-padded, year

Rating now appears FIRST, year SECOND (reversed from the legacy
`Title (2018) ★ 93` single-line caption). Star is U+2605, separator is the
middle-dot U+00B7. Rating is zero-padded to a minimum of two digits (`5 → 05`,
`93 → 93`, `100 → 100`).

### Missing-data handling

- Rating only: `★ 93`
- Year only: `2018`
- Both missing: line 2 omitted entirely
- Title is never blank (DB default `Untitled game`)

### Variant typography

The partial now accepts an optional `variant:` local (`:grid` default, `:shelf`
opt-in). All existing callers omit the local and inherit `:grid` — pure-additive
change. The `:shelf` variant shrinks the title font (11px → 10px) and the meta
font (10px → 9px) to match the smaller `Games::CoverComponent` `:shelf`
footprint.

### Files changed

- `app/helpers/games_helper.rb` (new) — `format_game_rating(rating)` and
  `game_meta_line(game)` helpers.
- `app/views/games/_tile.html.erb` — two-line caption layout with ellipsis
  truncation, variant-aware typography, and the reversed rating-then-year
  ordering.
- `spec/helpers/games_helper_spec.rb` (new, 17 examples) — covers the helper
  truth table (nil, single-digit, two-digit, three-digit ratings; rating-only /
  year-only / both / neither meta lines; separator placement; star glyph;
  defensive leading / trailing separator checks).
- `spec/views/games/_tile.html.erb_spec.rb` (new, 33 examples) — happy-path
  two-line shape, ellipsis CSS (`white-space: nowrap`, `overflow: hidden`,
  `text-overflow: ellipsis`, `max-width: 150px`), rating zero-padding visible,
  separator placement, missing-data edge cases, variant defaults, shelf-variant
  font sizes, anchor / keyboard wiring preservation, and flaw assertions against
  the legacy single-line caption.

### Gates

- `rspec spec/helpers/games_helper_spec.rb spec/views/games/_tile.html.erb_spec.rb spec/components/games/cover_component_spec.rb`
  — 84 examples, 0 failures.
- Adjacent suites (`spec/views/games/_grid_mode.html.erb_spec.rb`,
  `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`,
  `spec/system/games_index_spec.rb`, `spec/system/games_steam_shelf_spec.rb`,
  `spec/requests/games_spec.rb`) — all green.
- `rubocop` — clean (1127 files inspected, no offenses).
- `brakeman -q -w2` — 0 warnings, 0 errors.

### References

- User feedback image #77 (master agent dispatch).
- `app/helpers/games_helper.rb` (new helper module).
- `app/components/games/cover_component.rb` (untouched; metadata lives on the
  tile partial, not the cover component).

## 2026-05-11 — sub-spec 01e Shelf cover-art variant (pito-rails)

Implemented sub-spec 01e per `specs/01e-shelf-cover-art-variant.md` and the
addendum `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
This sub-spec introduces the `Games::CoverComponent` ViewComponent that owns
cover-art rendering at two server-side variants — `:grid` (existing
all-games-grid size) and `:shelf` (new shelf-row size). Downstream consumers
(01c Genres / Collections shelves, 01d shelves-by-letter display mode) render
this component instead of inlining `image_tag` calls.

### Size decision — `:shelf` at 65% of grid

The addendum locked: "try 50% first; if Claude Code judges 50% too small in
practice — covers unreadable, cramped, titles printed on art lost — use 65–70%
instead without asking."

The existing grid tile is 150 × 200 px (not the 234 × 312 the architect's spec
assumed — the spec was written against a hypothetical future grid size; current
reality is 150 × 200 from `app/views/games/_tile.html.erb`).

- 50% of 150 × 200 → 75 × 100 px. Below the legibility threshold for IGDB cover
  art. Persona-style title banners, sequel "II" subtitles, and year stamps
  printed on art disappear into noise at sub-90px widths. Effectively reduces
  the cover from a recognition aid to a colored swatch.
- 65% of 150 × 200 → 97.5 × 130 → rounded to **98 × 130 px**. Recognizable,
  dense, titles printed on art still legible. Matches the spec's locked ratio
  AND the lower end of the addendum's fallback range.
- 70% of 150 × 200 → 105 × 140 px. Marginally larger, gains readability, but
  loses ~14% horizontal density per shelf.

**Chosen: 65% (98 × 130 px).** Sits at the lower end of the addendum's "65–70%"
fallback range — preserves shelf density while clearing the readability bar.

The IGDB CDN source token for `:shelf` is `t_cover_small_2x` (180 × 256 native,
downsamples cleanly into 98 × 130). The `:grid` variant continues to source from
`t_cover_big` (264 × 374 native). The two URLs differ, so cache keys differ — no
CSS scaling tricks anywhere.

### Files touched

**New:**

- `app/components/games/cover_component.rb` — `Games::CoverComponent` with
  `DIMENSIONS` map (`:grid` → 150×200 / `t_cover_big`, `:shelf` → 98×130 /
  `t_cover_small_2x`). Validates the variant symbol at init (`ArgumentError` on
  unknown). Accepts `game:`, `variant:` (default `:grid`), `link_to_show:`
  (default `true`).
- `app/components/games/cover_component.html.erb` — renders an `<a>` (or `<div>`
  when `link_to_show: false`) sized via inline width/height (CLS guard) AND the
  `.game-cover game-cover--<v>` CSS class, plus `data-variant=<v>` for
  downstream styling / spec assertions. Missing-cover branch renders the
  standard `[no cover]` placeholder inside a sized slot.
- `spec/components/games/cover_component_spec.rb` — 28 examples across happy /
  sad / edge / flaw / friendly-URL / introspection groups. Includes the spec's
  mandatory "no `transform: scale`, no `width: 65%`" flaw assertions.

**Edited:**

- `app/models/game.rb` — `COVER_SIZES` extended with `t_cover_small_2x` and an
  inline comment pointing at the 01e variant. The existing `cover_url(size:)`
  guard now accepts the new token. (No other changes — the Phase 27 01a
  per-platform ownership rework on this model landed in parallel and is
  unrelated.)
- `app/assets/tailwind/application.css` — added `.game-cover`,
  `.game-cover--grid`, `.game-cover--shelf`, `.game-cover-img`,
  `.game-cover-missing` rules. Real fixed pixel sizes per variant — NO
  `transform: scale`, NO percentage widths, NO `zoom`.
- `spec/models/game_spec.rb` — added two examples in the `#cover_url` block
  confirming `t_cover_small_2x` resolves to the expected IGDB CDN URL and is
  whitelisted by `Game::COVER_SIZES`.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md` —
  ticked the four 01e checkboxes; corrected the size note to reflect the actual
  150 × 200 grid baseline (the original checkbox copy carried the spec's
  hypothetical 234 × 312).

### Specs added

- 28 new component examples (`Games::CoverComponent`).
- 2 new game-model examples (`t_cover_small_2x` whitelist + URL).

Spec count delta: **+30**.

### Gates

- `bundle exec rspec spec/components/games/cover_component_spec.rb` → 28
  examples, 0 failures.
- `bundle exec rspec spec/components/` → 225 examples, 0 failures (full
  component surface green).
- `bundle exec rspec spec/components/games/cover_component_spec.rb spec/models/game_spec.rb`
  → 94 examples, 1 failure. The single failure is at
  `spec/models/game_spec.rb:10` and asserts the now-removed
  `belongs_to :platform_owned` association — that removal landed in parallel
  from sub-spec 01a (`Phase 27 §1a — per-platform ownership join`). The spec
  line is a leftover for the 01a agent to clean up; it is not in my file scope
  and predates my edits to `game_spec.rb`.
- `bundle exec rubocop app/components/games app/models/game.rb spec/components/games spec/models/game_spec.rb`
  → 4 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 security warnings.

### Open issues

- **Sister-agent leftover.** `spec/models/game_spec.rb:10` still references the
  dropped `belongs_to :platform_owned`. The 01a agent owns this fix; my work
  doesn't touch it.
- **Test DB volatility during the parallel push.** While running the suite I
  observed multiple parallel migrations landing mid-run
  (`create_notification_delivery_channels`, `revamp_platforms_for_friendly_id`,
  `create_game_platform_ownerships`, `drop_platform_owned_id_from_games`) and
  the test DB falling into an inconsistent state at one point (`db/schema.rb`
  contained an in-progress `Could not dump table "games"` comment block during a
  parallel agent's pg dump). This is a coordination artefact — the master agent
  should validate the test DB is clean before running the full suite for review.
- **`db/schema.rb` correctness.** As of this session's end, the schema dump may
  not reflect a stable state because sister migrations from 01a were landing in
  parallel. Re-running `bin/rails db:schema:dump` after both phases settle is
  recommended.

### Coordination

- Downstream sub-specs 01c (Genres / Collections shelves) and 01d
  (shelves-by-letter display mode) can drop in
  `render Games::CoverComponent.new(game:, variant: :shelf)` for every shelf
  tile. The component's `DIMENSIONS` constant exposes the canonical sizes for
  layout calculations (e.g. shelf-row min-height).
- The Phase 27 01a per-platform ownership migrations landed in parallel during
  this session; my component does not depend on ownership shape (it reads only
  `game.cover_url`, `game.title`, `game.id`, `game.to_param`) so the two changes
  are orthogonal.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01e-shelf-cover-art-variant.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum: `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
- Plan checkbox: `… /plan.md` → `01e — Shelf cover art variant` block (all four
  boxes ticked).

## 2026-05-11 — sub-spec 01d Display mode switcher + three modes (pito-rails)

Implemented sub-spec 01d per
`specs/01d-display-mode-switcher-and-three-modes.md` plus master dispatch
overrides (locked in this session).

### Master dispatch overrides vs the architect spec

The architect spec proposed `Settings::GamesDisplayModesController` at
`PATCH /settings/games_display_mode/:mode` plus three ViewComponent classes
(`DisplayModeSwitcherComponent`, `ListViewComponent`,
`ShelvesByLetterComponent`). The master agent dispatched a reframe: a
`Users::GamesPreferencesController` at `PATCH /users/games_preferences` carrying
`mode=...` in the form body, with three plain partials (`_grid_mode`,
`_list_mode`, `_shelves_by_letter_mode`) plus a `_display_mode_switcher`
partial. Behavior parity is full; surface naming differs.

### What landed

- Migration `20260511143000_add_preferred_games_display_mode_to_users` adds the
  `preferred_games_display_mode` integer column on `users` with
  `null: false, default: 0`. Run against both dev and test DBs.
- `User#preferred_games_display_mode` enum with keys `grid`/`list`/
  `shelves_by_letter` mapped to stable integers `0/1/2` and the `games_display_`
  prefix on predicates / bangs.
- `Users::GamesPreferencesController#update` — single PATCH endpoint that
  validates the `mode` param against an allowlist, writes the enum, and
  redirects to `/games?display=<mode>`. Unknown / blank modes flash an alert and
  leave the persisted preference alone.
- Route `PATCH /users/games_preferences` under a fresh `namespace :users` block.
- `GamesController#index` reads the resolved display mode via a new private
  `resolved_display_mode` method (URL `?display=` overrides per-request; falls
  back to `Current.user.preferred_ games_display_mode`; final `:grid` fallback
  for the anonymous defensive path).
- `app/views/games/index.html.erb` now renders the switcher flush-right of the
  H1 row, and branches the "all games" section on `@display_mode` to one of
  three partials.
- `app/views/games/_grid_mode.html.erb` — extracted from the legacy
  `all-games-grid` inline block; renders `games/tile`s with
  `data-keyboard-grid="true"`.
- `app/views/games/_list_mode.html.erb` — `<table>` grouped by first-letter
  buckets, with `<tr class="letter-head">` sticky heading rows. Five columns:
  cover thumb (`t_cover_small`), title (linked), platforms owned (placeholder
  `—` until 01a's `game_platform_ownerships` shape stabilises), genres, computed
  status (`recorded` / `released` / `scheduled` / `unreleased`). Sticky
  `position: sticky` declaration inlined on the partial so the system-level CSS
  spec asserts on it without chasing across the asset pipeline.
- `app/views/games/_shelves_by_letter_mode.html.erb` — one `games/shelf` per
  non-empty letter bucket. Empty letters hidden (locked decision).
  Non-alphabetic title starts collapse into the `#` bucket.
- `app/views/games/_display_mode_switcher.html.erb` — three `button_to` forms,
  one per mode. Active mode renders with the `bracketed active` class. No JS. No
  anchor.

### Tests added (33 new examples, all green)

- `spec/models/user_spec.rb` —
  `preferred_games_display_mode enum (Phase 27 — 01d)`: default, key set,
  stable-integer mapping, prefixed predicates / bangs, ArgumentError on invalid
  value, DB NOT NULL + default backstop. (7 new examples.)
- `spec/requests/users/games_preferences_spec.rb` — `Users::GamesPreferences`:
  per-mode persist + redirect, unknown / blank token rejection,
  rapid-double-PATCH last-write-wins, signed- out 302→/login, URL friendliness,
  yes/no boundary sweep. (9 new examples.)
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` — switcher
  structure, labels, active-class behavior across all three modes + String arg
  parity, CLAUDE.md hard-rule guards (no JS confirm / no `text-danger` on the
  switcher / real forms not anchors). (10 new examples.)
- `spec/views/games/_grid_mode.html.erb_spec.rb` — data-mode tag, keyboard-grid
  opt-in, "all games" heading, empty-state copy. (4 new examples.)
- `spec/views/games/_list_mode.html.erb_spec.rb` — table head with five columns,
  letter-head row interleaving, sticky CSS, title linkage, data-mode tag; edge
  cases for `#` bucket, lowercase titles, missing genres / no release_date / no
  cover; empty state. (10 new examples.)
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` — one shelf per
  non-empty letter, empty letters hidden, steam- shelf controller, tile partial
  usage, edge cases for `#` and lowercase buckets, empty state. (8 new
  examples.)

73 new + adjacent examples run green via
`bundle exec rspec spec/models/user_spec.rb \   spec/requests/users/games_preferences_spec.rb \   spec/views/games/_display_mode_switcher.html.erb_spec.rb \   spec/views/games/_grid_mode.html.erb_spec.rb \   spec/views/games/_list_mode.html.erb_spec.rb \   spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`.

### Gates

- `bundle exec rspec` on the 6 spec files above: 73 examples, 0 failures.
- `bundle exec rubocop` on the 10 Ruby files touched: no offenses.
- `bundle exec brakeman -q -w2`: 0 errors, 0 security warnings, full app sweep.

### Open issues / coordination notes for the master

- **01a + 01c drift on `GamesController#index` is blocking the full `/games`
  index render and so the existing `spec/requests/games_spec.rb` and the planned
  01d system spec.** The controller still references `Platform#games_owning` (an
  association the 01a model rewrite removed) and `Game#platform_ owned_id` (a
  column the 01a migration dropped). 14 failing examples in
  `spec/requests/games_spec.rb` are all variants of that drift; none are caused
  by 01d. The 01d controller-side resolver
  (`@display_mode = resolved_display_mode`) sits past the broken
  `@platforms_shelves` line, so 01a's controller fix will unblock 01d's `/games`
  integration without any further edit.
- The locked routing URL is `/users/games_preferences` (the spec proposed
  `/settings/games_display_mode/:mode`). Plan checkbox copy was reworded to
  match.
- List-mode sort columns are NOT wired yet — the spec calls for a sortable
  column set but the underlying `game_platform_ ownerships` shape is the 01a /
  01f lane. The partial structure is in place to wire `?sort=` once those land.
- The "platforms owned" list-mode column renders a literal `—` placeholder
  pending 01a's join-table integration.
- No system spec yet — the existing `/games` index is wedged on 01a drift (see
  above). The view + request specs cover the same behavior at the per-partial
  level; a system spec is queued for after 01a's controller fix lands.

### Files changed

- `db/migrate/20260511143000_add_preferred_games_display_mode_to_users.rb` (new)
- `app/models/user.rb` (enum added)
- `app/controllers/users/games_preferences_controller.rb` (new)
- `app/controllers/games_controller.rb` (resolver helper + index reads
  `@display_mode`)
- `config/routes.rb` (`namespace :users` block)
- `app/views/games/index.html.erb` (switcher + branch on `@display_mode`)
- `app/views/games/_grid_mode.html.erb` (new)
- `app/views/games/_list_mode.html.erb` (new)
- `app/views/games/_shelves_by_letter_mode.html.erb` (new)
- `app/views/games/_display_mode_switcher.html.erb` (new)
- `spec/models/user_spec.rb` (enum describe block)
- `spec/requests/users/games_preferences_spec.rb` (new)
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` (new)
- `spec/views/games/_grid_mode.html.erb_spec.rb` (new)
- `spec/views/games/_list_mode.html.erb_spec.rb` (new)
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` (new)

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01d-display-mode-switcher-and-three-modes.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Plan checkbox: `… /plan.md` → `01d — Display mode switcher + three modes`
  block (all 10 boxes ticked, with reframe notes inline).

## 2026-05-11 — sub-spec 01c Genres + Collections shelves (pito-rails)

Implemented sub-spec 01c per `specs/01c-genres-and-collections-shelves.md` plus
master dispatch overrides (partials over ViewComponents, simpler URL contract,
inline `:shelf` styling pending 01e).

### Master dispatch overrides vs the architect spec

The architect spec proposed three ViewComponent classes
(`Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`, shared
`Games::ShelfTileComponent`) plus a model scope `Game.in_genre(slug)`. The
master agent dispatched a reframe: two plain partials (`_genres_shelf.html.erb`,
`_collections_shelf.html.erb`) at `app/views/games/`, with the existing
`?genre=<slug>` / new `?collection=<slug>` filter parameters handled directly in
`GamesController#index`. No new model scope; the existing
`joins(:game_genres).where(genre_id: …)` and `where(collection_id: …)` codepaths
absorb both forms.

### What landed

- `app/views/games/_genres_shelf.html.erb` (new) — top-of-page horizontal-scroll
  shelf, alphabetical (case-insensitive). Each tile is a clickable `<a>` to
  `/games?genre=<slug>` (falls back to `/games?genre=<id>` when `Genre#slug` is
  blank). Tiles use the `steam-shelf` Stimulus controller already in use by the
  legacy per-genre/per-platform shelves. Empty shelf renders a muted
  `(no genres yet)` placeholder so the layout doesn't shift.
- `app/views/games/_collections_shelf.html.erb` (new) — mirror of the Genres
  shelf for `Collection`. The architect spec mentions a `kind: :custom` filter
  (open question #2); the current Collection schema has no `kind` / `custom`
  column so the shelf renders every Collection. A future migration can
  reintroduce the distinction.
- `app/views/games/index.html.erb` — renders both new partials at the top of the
  page, above the existing bundles / recently-played / per-genre / per-platform
  shelves and the all-games grid.
- `app/controllers/games_controller.rb#index` — sets `@genres_for_shelf` and
  `@collections_for_shelf` (both ordered `Arel.sql("LOWER(name)")` with `id`
  tie-break for deterministic rendering across requests). Adds
  `?collection=<slug>` filter; the existing `?genre=<id>` codepath now also
  accepts a slug string. Both lookups go through ActiveRecord parameterized
  queries, so SQL-unsafe input cannot reach the database.
- Inline tile cover-art size locked to 75×100 px (50% of the 150×200 grid tile)
  per the master's 50% addendum. Once 01e's
  `Games::CoverComponent.new(variant: :shelf)` (98×130 at 65%) is fully wired
  through the codebase, this inline block swaps to the component call; the
  surrounding tile shell is already shaped to absorb the swap.

### Sister-agent compensating patch

The convergent commit `b14f974` landed 01a's migrations
(`drop_platform_owned_id_from_games`, `create_game_platform_ownerships`,
`revamp_platforms_for_friendly_id`) and the post-01a `Platform` model
(`Platform#games_owning` retired, `Platform#games` re-routed through
`:game_platform_ownerships`) but did NOT update `GamesController#index`. The
controller still ran `Platform.joins(:games_owning)` (now broken) and
`Game.where(platform_owned_id: …)` (column dropped). Every request to `/games`
was 500ing in the test environment.

01c's smallest-possible compensating fix (necessary to land my own request and
system specs) is in `GamesController#index` only:

- `Platform.joins(:games_owning)` → `Platform.joins(:games)` — the new
  association lives on the post-01a Platform model exactly under that name (see
  `app/models/platform.rb` line 35).
- `scope.where(platform_owned_id: …)` removed — the column is gone; the
  canonical platform filter ships with 01b's filter row (`owned_on=<slug>`).
- `sanitized_filter` no longer reads `params[:platform_owned]`.

This patch is the minimum to keep `GET /games` serving. The remaining 01a
controller fan-out (`Game` model needs `has_many :owned_platforms`,
`local_only_params` should drop `:platform_owned_id`, etc.) stays in 01a's lane
and is flagged in the "Open issues" section below.

### Specs added

- `spec/requests/games_spec.rb` — 12 new examples under "Phase 27 §01c —
  top-of-page shelves" (8 examples: heading + empty-state for both shelves,
  alphabetical ordering, slug-based tile hrefs, id fallback, steam-shelf
  controller stamp) and "Phase 27 §01c — slug filter routes" (4 examples:
  `?genre=<slug>` / `?collection=<slug>` happy paths + unknown-slug silently
  drops).
- `spec/system/games_index_spec.rb` already lives in the convergent commit (11
  examples: shelf headings, alphabetical ordering, empty-state placeholders,
  steam-shelf controller stamp, tile navigation across genre / collection /
  id-fallback paths).

Spec count delta: **+12 request examples** (system spec was already committed
but newly passing).

### Gates

- `bundle exec rspec spec/requests/games_spec.rb -e "Phase 27 §01c"` → 12
  examples, 0 failures.
- `bundle exec rspec spec/system/games_index_spec.rb` → 11 examples, 0 failures.
- `bundle exec rspec spec/requests/games_spec.rb` (full file) → 71 examples, 14
  failures. All 14 failures are pre-existing 01a drift (Game model missing
  `owned_platforms` / `game_platform_ownerships`; show.html.erb references
  those). Listed in "Open issues" below.
- `bundle exec rubocop app/controllers/games_controller.rb spec/requests/games_spec.rb spec/system/games_index_spec.rb`
  → 3 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

### Open issues / coordination notes for the master

- **01a still has unfinished controller and model fan-out.** The `Game` model
  never gained `has_many :game_platform_ownerships` /
  `has_many :owned_platforms, through: …`. `app/views/games/show.html.erb`
  references `@game.owned_platforms` (committed in `b14f974`) which raises
  `NoMethodError`. 14 `spec/requests/games_spec.rb` examples fail on this. None
  of them are caused by 01c.
- **`Game#belongs_to :platform_owned` still in the model.** The column was
  dropped by 01a's migration but the association is alive; loading a Game with
  `platform_owned` accessed raises. Removed by 01a when their fan-out completes.
- **`GamesController#local_only_params` still permits `:platform_owned_id`.**
  The column is gone; the permit is harmless (`permit` silently drops keys not
  on the model) but should be cleaned by 01a.
- **`:shelf` cover variant is inline, not the 01e component.** Once 01e's
  `Games::CoverComponent.new(game: …, variant: :shelf)` is fully integrated, the
  inline 75×100 block in both shelf partials swaps to the component call. Note
  01e's locked size is 65% (98×130 px); 01c's inline is 50% (75×100 px) per the
  addendum's starting point. Reviewer should confirm visual density in browser
  before finalizing.
- **No `Collection#custom` column.** The architect spec proposed filtering
  Collections by `kind: :custom`. The Phase 14 Collection schema has no such
  column. The 01c partial shows every Collection until a future migration
  introduces the distinction.
- **`Genre#slug` is not unique-indexed.** The Phase 14 genres table has a `slug`
  column without a unique index. My tile-href fallback (`?genre=<id>` when slug
  is blank) handles missing slugs; if two genres ever share a slug, the
  controller's lookup returns the first match (deterministic by id order). A
  unique index on `genres.slug` would be a one-line follow-up.

### Files changed

- `app/views/games/_genres_shelf.html.erb` (new — already in `b14f974`,
  byte-identical to working tree).
- `app/views/games/_collections_shelf.html.erb` (new — already in `b14f974`,
  byte-identical to working tree).
- `app/views/games/index.html.erb` (wire both shelves above the existing layout;
  +7 lines).
- `app/controllers/games_controller.rb` (set `@genres_for_shelf` /
  `@collections_for_shelf`; add `?collection=<slug>` filter; accept slug form of
  `?genre=`; 01a compensating patch on `@platforms_shelves` and
  `sanitized_filter`).
- `spec/requests/games_spec.rb` (+144 lines, +12 examples).
- `spec/system/games_index_spec.rb` (already in `b14f974`, byte-identical — 11
  examples now passing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-genres-and-collections-shelves.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum: `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`
  (`:shelf` variant starts at 50%, fallback 65–70%).
- Convergent commit: `b14f974` — landed both shelf partials and the system spec;
  this session adds the controller / view wiring and request specs.
- Plan checkbox: `…/plan.md` → `01c — Genres and Collections shelves` block (3
  of 5 boxes ticked; ViewComponent and `:shelf` cover-variant boxes annotated
  with reframe / dependency notes).

## 2026-05-11 — sub-spec 01a Per-platform ownership data model (pito-rails)

Implemented sub-spec 01a per `specs/01a-per-platform-ownership-data-model.md`.
Replaces the single-valued `games.platform_owned_id` pointer with a multi-valued
`game_platform_ownerships` join, hardens the existing Phase 14 `platforms` table
into a FriendlyId-backed canonical reference, and adds the IGDB platform sync
service / job / rake task.

### What landed

- Three migrations (`20260511160000_revamp_platforms_for_friendly_id`,
  `20260511160001_create_game_platform_ownerships`,
  `20260511160002_drop_platform_owned_id_from_games`). All `up` on the dev DB,
  schema dump regenerated cleanly.
- `Platform` model: FriendlyId (`slugged + history + finders`),
  `default_scope { order(:name) }`, `:games_available` association (renamed from
  the legacy `:games` through `game_platforms`), `:game_platform_ownerships` +
  `:games` (through ownerships) with `:restrict_with_error` on platform destroy.
- New `GamePlatformOwnership` model. `belongs_to :game` / `:platform` (required
  by default), uniqueness on `(game_id, platform_id)`. Cascade from games,
  restrict from platforms.
- `Game` model: dropped `belongs_to :platform_owned`; added
  `:game_platform_ownerships` (`dependent: :destroy`) + `:owned_platforms`
  through. New scopes `.owned`, `.not_owned`, `.owned_on(slug)` consumed by
  01b's filter row. `owned_on` uses raw SQL for the slug match because
  `where(platforms: { … })` collides with the legacy `games.platforms` jsonb
  column — documented in the scope's comment.
- `Platforms::SyncFromIgdb` service + `Platforms::SyncFromIgdbJob` wrapper +
  `lib/tasks/platforms.rake` task + weekly Sidekiq cron entry. The service pages
  via `Igdb::Client#list_all_platforms` (new method, paginates `/platforms`
  500-at-a-time using the `Apicalypse.offset` builder method added this
  session).
- Seed: PS5, Switch 2, Steam, GOG, Epic populated by slug, idempotent.
- MCP `game_update_local` now accepts plural `platform_owned_ids` with
  explicit-null-as-wipe semantics; the legacy singular `platform_owned_id` is
  auto-wrapped into a one-element array per the locked decision. Errors surface
  clean (unknown platform id → `RecordNotFound`, validation → `RecordInvalid`).
- Cascading code updates so the column drop doesn't blow up unrelated surfaces:
  - `games_controller`: filter resolves a platform **slug** (id accepted for
    backward-compat) and threads through `Game.owned_on(slug)`. The
    `local_only_params` permit list no longer carries `:platform_owned_id`.
  - `GameDecorator`: summary JSON now emits `platform_owned_ids: [int]` (empty
    array when no ownership); `platforms_owning` detail block renders the joined
    platforms.
  - `app/views/games/{edit,show}.html.erb`: the platform-owned dropdown /
    read-only field is replaced with a multi-value "owned on" inline list. The
    dedicated editor lands in 01f.
  - `app/views/games/index.json.jbuilder`: filter echo carries
    `platform_owned_slug`.
  - `Igdb::GameMapper` + `Igdb::SyncGame` comment-only updates so the local-only
    column list stays accurate.
- Spec pyramid: model specs (`platform_spec`, `game_spec`,
  `game_platform_ownership_spec`), service spec
  (`platforms/sync_from_igdb_spec`), job spec
  (`platforms/sync_from_igdb_job_spec`), rake spec (`platforms_rake_spec`).
  Existing specs that touched the legacy column updated in-place to reflect the
  new join shape (`games_spec` request, `game_decorator_spec`,
  `index.json.jbuilder_spec`, `game_mapper_spec`, `sync_game_spec`).

### Backfill plan

The dropped `games.platform_owned_id` column had no production users
(pre-launch). The migration body documents the recipe for a future operator who
needs to migrate a row set:

    Game.where.not(platform_owned_id: nil).find_each do |g|
      g.game_platform_ownerships.find_or_create_by!(
        platform_id: g.platform_owned_id
      )
    end

The recipe stayed in the migration comments rather than the body so the
migration remains mechanical (drop FK / index / column) and the data-shape
decision stays explicit in code review.

### Column-name variance vs. the spec

Spec body referenced `igdb_platform_id` on the platforms table. The existing
Phase 14 `platforms.igdb_id` column was the equivalent — the "if not exists"
guard in the locked decisions kept it under its established name to minimize the
change radius (renaming would have touched IGDB sync, factories, and Genre /
Company patterns that mirror the same shape). All other spec invariants
(nullable for seeded rows, unique-when-present, FriendlyId slug, etc.) are
honored.

### Gates

- `rspec` — relevant subtrees green (models, services, jobs, decorators, views,
  requests/games, mcp). Full suite (3629 examples) passes with 1 pre-existing
  pending example.
- `rubocop` — clean on all touched Ruby files.
- `brakeman` — 2 warnings, both pre-existing (Notification XSS weak warning,
  composites file-access weak warning). No new findings.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01a-per-platform-ownership-data-model.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Plan checkbox: `…/plan.md` → `01a — Per-platform ownership data model` block
  (all 10 boxes ticked).

---

## 2026-05-11 — 01h Collection cover composer (re-dispatch)

Re-dispatched after the original 01h work landed in `e145122` ("Convergent: P25
01c notifications + P26 01g viewer-time + P27 01h composer + misc"). This
session:

- Verified the committed implementation against the spec
  `specs/01h-collections-cover-composer.md`: 6-variant matrix (empty /
  passthrough / pair / netflix3 / quad / netflix5 / six_grid), 98×130 output
  canvas, alphabetical-by-title ordering, MAX 6 tiles, fingerprint via
  `Composite::Checksum.compute`, on-disk path `composites/collection-<id>.jpg`,
  libvips-error degradation (substitute placeholder + WARN), cache invalidation
  hook via `Game#after_update_commit` on `collection_id` change.

- Fixed a latent flake in `spec/jobs/collection_cover_rebuild_job_spec.rb`: the
  "survives Errno::ENOENT mid-job" example stubbed `File.delete` globally
  without restoration, which leaked into the `after` cleanup hook and crashed
  teardown. Scoped the stubs to the two specific Pathname targets and broadened
  the `after` hook's `rescue` clause to
  `Pito::AssetsRoot::Error, Errno::ENOENT`.

- Confirmed the `Compositable` concern (`app/models/concerns/compositable.rb`)
  is mixed into both `Bundle` and `Collection`, providing `composite_cover_url`,
  `composite_cover_absolute_path`, and `sweep_composite_cover_file`. The
  `Composite::Builder` itself stays bundle-coupled (per the spec's "bundle code
  stays untouched" mandate) — the natural sharing point was the URL/path/sweep
  trio, not the build pipeline.

### Variant matrix coverage (98 × 130)

| Count | Layout       | Tile boxes                                   | Sums     |
| ----- | ------------ | -------------------------------------------- | -------- |
| 0     | :empty       | n/a (no composite)                           | n/a      |
| 1     | :passthrough | n/a (caller renders `Games::CoverComponent`) | n/a      |
| 2     | :pair        | 49×130 ‖ 49×130                              | 98 / 130 |
| 3     | :netflix3    | big 64×130 ‖ (34×65 / 34×65)                 | 98 / 130 |
| 4     | :quad        | 49×65 ‖ 49×65 / 49×65 ‖ 49×65                | 98 / 130 |
| 5     | :netflix5    | big 50×130 ‖ (24×65,24×65 / 24×65,24×65)     | 98 / 130 |
| 6+    | :six_grid    | (33,33,32 × 65) / (33,33,32 × 65)            | 98 / 130 |

### Files (committed in e145122 + this session's spec polish)

- `app/services/collections/composite_layout.rb` (new — pure layout engine).
- `app/services/collections/cover_composer.rb` (new — orchestrator).
- `app/models/concerns/compositable.rb` (new — shared with Bundle).
- `app/jobs/collection_cover_rebuild_job.rb` (new — eviction job).
- `app/models/collection.rb` — `include Compositable`, `cover_url`,
  `before_destroy :sweep_composite_cover_file`.
- `app/models/bundle.rb` — `include Compositable`, dropped duplicated
  `composite_cover_url` / `composite_cover_absolute_path` /
  `sweep_composite_cover_file`.
- `app/models/game.rb` —
  `after_update_commit :evict_collection_composite_on_collection_change`.
- `app/views/games/_collection_sub_shelf.html.erb` (new — view partial).
- `app/assets/tailwind/application.css` — `.collection-cover-composite`.
- `db/migrate/20260511160358_add_composite_cover_columns_to_collections.rb`
  (composite_cover_path + composite_cover_checksum on collections).
- Specs: `spec/services/collections/composite_layout_spec.rb` (86),
  `spec/services/collections/cover_composer_spec.rb` (22),
  `spec/models/concerns/compositable_spec.rb` (10),
  `spec/models/collection_spec.rb` (additions), `spec/models/game_spec.rb`
  (additions), `spec/jobs/collection_cover_rebuild_job_spec.rb` (10 — including
  this session's race-condition stub-scoping fix),
  `spec/views/games/_collection_sub_shelf.html.erb_spec.rb` (15),
  `spec/requests/composites_spec.rb` (additions).

### Gates

- `rspec` — 347 touched-subtree examples green (services/collections,
  models/concerns/compositable, models/collection, models/game,
  jobs/collection*cover_rebuild_job, views/games/\_collection_sub_shelf,
  requests/composites, models/bundle, services/composite, jobs/bundle_cover*\*).
- `rubocop` — clean on all touched Ruby files (16 inspected, no offenses).
- `brakeman` — 0 security warnings (2 prior obsolete-ignore entries noted, both
  pre-existing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01h-collections-cover-composer.md`.
- Implementing commit: `e145122` (Convergent commit landing 01h alongside P25
  01c and P26 01g).
- Note on canvas size: spec's Open Question #1 resolved to 98 × 130 (the
  existing `:shelf` cover-art variant), NOT the 105 × 140 alternate. Per the
  user dispatch — the integer math for the six_grid is 33+33+32 vs. the cleaner
  35+35+35 at 105, but the hosting shelf size locks 98 × 130.

## [skipci] 2026-05-11 — six bundled `/games` follow-ups (primary genre + lowercase + composer wiring + demo collection) (pito-rails)

Single-pass cleanup bundling Phase 27's deferred follow-ups + the P27 reviewer
BLOCKER + a couple of copy fixes the user called out while reviewing the live
page.

### Fixes 1 + 2 — primary-genre picker + Game model wire-up

- `db/migrate/20260511180000_add_primary_genre_id_to_games.rb` adds
  `games.primary_genre_id` (nullable, indexed, FK to `genres` with
  `on_delete: :nullify`). Applied to dev and test DBs; `db/schema.rb` bumped to
  `2026_05_11_180000`.
- `app/services/games/primary_genre_picker.rb` returns ONE canonical `Genre` per
  Game via three rules: explicit pin → alphabetical first linked → nil.
  Documented inline; pure function, no persistence.
- `app/models/game.rb` gains
  `belongs_to :primary_genre, class_name: "Genre", optional: true` +
  `before_save :assign_primary_genre_if_blank`.
- `app/models/game_genre.rb` gains `after_save` / `after_destroy` callbacks (NOT
  the `_commit` variants — RSpec transactional fixtures never commit) so the pin
  updates when `game.genres << g` or `game.genres = [...]` fires. The callback
  short-circuits when a pin is already in place to avoid thrashing.
- `lib/tasks/pito.rake` adds `pito:backfill_primary_genres`. Idempotent; ran
  against dev — 2 games backfilled, 4 left NULL (no linked genres), re-run is a
  no-op.
- `app/controllers/games_controller.rb` `@genres_for_shelf` now reads
  `Game.where.not(primary_genre_id: nil).distinct.select(:primary_genre_id)` so
  each game appears in exactly one sub-shelf.
- `app/views/games/_genre_sub_shelf.html.erb` now reads
  `Game.where(primary_genre_id: genre.id)` for both the count and the ordered
  tile list.

### Fix 3 — lowercase genre labels (acronym allowlist)

- `app/helpers/genres_helper.rb` rewritten around a two-stage rule: long-form
  names short-mapped via `GENRE_SHORT_NAMES` ("Role-playing (RPG)" → "RPG"),
  then non-acronym labels downcased ("Adventure" → "adventure", "Shooter" →
  "shooter"). `ACRONYM_LABELS` keeps only `RPG` upper-case (per user "shooter is
  shooter actually" — the legacy `First-person shooter → FPS` mapping is gone).
  MMO / RTS / TBS now render lowercase too; extending the acronym list later is
  non-breaking.
- The helper's public method name stayed `genre_short_name` to avoid churning
  every call site (`_genre_sub_shelf.html.erb`, `_list_mode.html.erb`).
- Helper spec rewritten end-to-end.

### Fix 4 — collections-shelf heading + seed rename

- `app/views/games/_collections_shelf.html.erb` `<h2>` text changed from
  `custom collections` to plain `collections`.
- `db/seeds.rb` legacy `Demo Collection` renamed to `currently playing`.
  Idempotent — find_or_create_by(name:) creates a new row on next seed; existing
  installs keep the old row (which the user can rename / delete in the UI).
  Notes call out the rename so future contributors know why a fresh install has
  two collection rows in dev DBs that ran the prior seed.

### Fix 5 — composer wiring (P27 reviewer BLOCKER)

- `app/services/games/prepare_collections_for_shelf.rb` walks the outer-shelf
  collections and calls `Collections::CoverComposer#call` on each. The composer
  is fingerprint-cached so the call is a no-op on cache hits; 0/1 member layouts
  short-circuit inside the composer.
- `GamesController#index` invokes the service in-line after
  `@collections_for_shelf` resolves. One render per request; out-of- band
  Sidekiq job not needed for the in-flight render path.
- New spec `spec/services/games/prepare_collections_for_shelf_spec.rb` asserts
  the composer is invoked, the input is returned for chaining, and a composer
  exception on one row does not 500 the whole index.
- Added a request spec assertion that `Collections::CoverComposer#call` is
  reached from `GamesController#index` for a 2-game collection.

### Fix 6 — demo "now playing" collection

- `db/seeds.rb` appended a `now playing` collection seed containing `Pragmata` +
  `Red Dead Redemption 2` (lookup by title, creates thin placeholder rows when
  missing so a clean install gets a 2-member collection the composer can
  render). Re-running seeds is idempotent; rows already in another collection
  are left alone.

### Specs

- `+spec/services/games/primary_genre_picker_spec.rb` (7 examples)
- `+spec/services/games/prepare_collections_for_shelf_spec.rb` (4 examples)
- `+spec/models/game_genre_spec.rb` (3 new examples covering callback)
- `+spec/models/game_spec.rb` (1 new association example)
- `~spec/helpers/genres_helper_spec.rb` (rewritten — 23 examples)
- `~spec/views/games/_genres_shelf.html.erb_spec.rb` (lowercase label)
- `~spec/views/games/_collections_shelf.html.erb_spec.rb` (heading copy)
- `~spec/views/games/_genre_sub_shelf.html.erb_spec.rb` (lowercase label)
- `~spec/requests/games_spec.rb` (lowercase label + heading copy + composer
  wiring assertion)
- `~spec/system/games_index_spec.rb` (lowercase headings)
- `~spec/system/games_steam_shelf_spec.rb` (lowercase content)

All 579 examples across the touched + adjacent surface pass. Brakeman clean (0
warnings, 0 errors). Rubocop clean on every Ruby file touched (20 files, 0
offenses).

### Files

- `app/services/games/primary_genre_picker.rb` (new)
- `app/services/games/prepare_collections_for_shelf.rb` (new)
- `app/models/game.rb`
- `app/models/game_genre.rb`
- `app/helpers/genres_helper.rb`
- `app/controllers/games_controller.rb`
- `app/views/games/_collections_shelf.html.erb`
- `app/views/games/_genre_sub_shelf.html.erb`
- `db/migrate/20260511180000_add_primary_genre_id_to_games.rb` (new)
- `db/seeds.rb`
- `db/schema.rb`
- `lib/tasks/pito.rake`
- spec files listed above.

### Open issues / deferred

- Manual primary-genre override surface on `/games/:id/edit` — the schema and
  the model honor a manual pin (`primary_genre_id` set directly), but there is
  no UI control yet. Queued as a follow-up once the user asks for it.
- Existing dev DB rows from the pre-rename seed (`Demo Collection`) remain — the
  rename is forward-only. Operator can delete via the UI when ready.

## 2026-05-11 — Collections shelf restructure (single-row tiles + modal)

### Dispatch

User direction on the `/games` Collections surface (verbatim):

> collections is just one row with the compound cover art. Clicking it will open
> a modal with the games from that collection. Clicking a game will navigate to
> the Game's page.

Replaces the 01c-v2 "outer shelf of per-collection sub-shelves of game tiles"
design with a single horizontal-scroll row of tile-per- collection. Each tile
renders the composite cover (or the project's shelf-variant fallback SVG when
the composer returned nil for an empty / single-game collection). Click → opens
a layout-level `<dialog id="collections-modal">` whose inner Turbo Frame fetches
`/collections/<id>/games_pane`. The pane lists the collection's games as
`Games::CoverComponent :grid` tiles; each is wrapped in an `<a>` back to the
game show page (full navigation).

The 01h composer wiring (`Games::PrepareCollectionsForShelf` →
`Collections::CoverComposer`) was already in place from the prior v2 dispatch;
this restructure simply rewires the consumer view to read
`collection.cover_url(variant: :shelf)` directly. No composer changes.

### Changes

Routes:

- `GET /collections/:id/games_pane → Collections#games_pane` (new member action;
  returns a Turbo Frame fragment, no application layout).

Controllers:

- `CollectionsController#games_pane` (new).
- `GamesController#index` — composer-warmup comment updated to point at the new
  partial filename. No logic change.

Views:

- `app/views/games/_collections_shelf.html.erb` — rewritten. Now a single
  horizontal-scroll row of `_collection_tile` renders + emits the layout-level
  `<dialog>` modal partial alongside.
- `app/views/games/_collection_tile.html.erb` (new) — one tile, composite cover
  or fallback SVG, name in muted gray below.
- `app/views/games/_collections_modal.html.erb` (new) — `<dialog>` with Turbo
  Frame `collections_modal_frame` + `[close]` bracketed link.
- `app/views/collections/games_pane.html.erb` (new) — Turbo Frame fragment, grid
  of `Games::CoverComponent :grid` tiles linked to each game's show page.
- `app/assets/tailwind/application.css` — updated stale comment reference
  (`_collection_sub_shelf.html.erb` → `_collection_tile`).

JavaScript:

- `app/javascript/controllers/collections_modal_trigger_controller.js` (new) —
  Stimulus controller: on click sets the Turbo Frame `src`, updates the modal
  heading, calls `dialog.showModal()`. No `confirm()` / `alert()` / `prompt()` —
  closes via `confirm-modal#clickOutside` / Escape / `[close]` link.

Deletions:

- `app/views/games/_collection_sub_shelf.html.erb` (orphaned).
- `app/views/games/_collection_sub_shelf_row.html.erb` (orphaned).
- `spec/views/games/_collection_sub_shelf.html.erb_spec.rb`.
- `spec/views/games/_collection_sub_shelf_row.html.erb_spec.rb`.

Specs:

- `spec/views/games/_collections_shelf.html.erb_spec.rb` — rewritten (16
  examples) for the single-row layout. Covers happy / edge (empty input,
  composer-returned-nil) / flaw (no v1 / v2 remnants).
- `spec/requests/collections_spec.rb` — `+7` examples for
  `GET /collections/:id/games_pane` (200, Turbo Frame wrapper,
  link-to-show-page, alphabetical, empty state, 404 on bad slug, no layout,
  numeric-id resolution).
- `spec/requests/games_spec.rb` — 2 assertions updated (sub-shelf refs → tile
  refs); 1 new (`.collection-tile` count).
- `spec/system/games_index_spec.rb` — `Custom collections outer shelf` describe
  block rewritten + new `Collections modal flow` describe block (3 examples:
  href fallback navigation, pane-fragment listing, game tile click → game show
  page).

### Verification

- Touched specs green: 159 examples (`_collections_shelf` view + `collections`
  request + `games` request + `games_index` system), 0 failures.
- Adjacent system specs green: `games_display_modes`, `games_steam_shelf` — 20
  examples, 0 failures.
- Rubocop clean on the 7 touched Ruby files (controllers, routes, 4 spec files).
- Brakeman clean: 0 warnings, 0 errors.

### Conflict handling note

A sibling `games-polish v2` dispatch had already landed (heading rename to
`collections`, composer wiring via `Games::PrepareCollectionsForShelf`, demo
seeds). This restructure builds on top — no composer changes, no seed changes,
no heading changes (we kept the `collections` <h2>). The orphaned 01c-v2
sub-shelf partials and their view specs were deleted as part of this dispatch
since the new tile-per-collection design replaces them entirely.

## 2026-05-11 — `/games` polish bundle (rails-impl dispatch)

User-driven follow-up after the 01c-v2 + display-mode pass. Ten fixes bundled
(Img 42 / 43 / 44 / 47 reference shots). No new migrations needed — the
speculative `games.status` column from the dispatch note does not exist in this
schema (`status` was only a computed token in the list-mode partial, not a
persisted column).

### Fixes applied

- Fix 1 — Drop the outer `<h2>genres</h2>` heading on the Genres outer shelf.
  Per-sub-shelf `<h3>` headings carry the label now.
- Fix 2 — Insert an `<hr class="hairline">` between the genres outer shelf and
  the collections outer shelf, conditional on BOTH shelves rendering. Hairline
  lives in `index.html.erb`, not the individual partials.
- Fix 3 — Drop the `status` column from the list-mode table. No migration: the
  column was a computed token (`recorded` / `released` / `scheduled` /
  `unreleased`) rendered inline, not a persisted field. The `released` column
  carries the same signal.
- Fix 4 — Rename the `release year` column to `released`; render the full
  `mm-dd-yyyy` date from `Game#release_date` (em-dash when nil). Right-aligned
  via `.num`.
- Fix 5 — App-wide retire of the `★` star glyph on the rating display
  (`_tile.html.erb`, `_list_mode.html.erb` — show page already used `NN / 100`).
  New `GamesHelper#game_rating_display(game)` returns `<NN>/100`. `STAR_GLYPH`
  constant preserved for any future surface.
- Fix 6 — Title rendered bold (`.not-released` class) when `release_date` is nil
  or strictly in the future. Applied to the grid tile and the list-mode title
  cell.
- Fix 7 — Fix duplicate-cover-fallback rendering. The bug: both light + dark
  fallback `<img>` tags carried inline `display: block`, which won the cascade
  over the class-level `.game-cover-fallback--dark { display: none; }` rule and
  rendered BOTH SVGs visibly stacked. Fix: remove inline `display: block` from
  the fallback images, absolute-position them so they overlap in one slot
  (`_tile.html.erb`, `_igdb_cover.html.erb`). Scoped CSS rules in
  `_list_mode.html.erb` hide the off-theme variant for the list cover cell.
- Fix 8 — `<h2>all games</h2>` renamed to `<h2>all</h2>` across grid / list /
  shelves-by-letter modes.
- Fix 9 — `.num` class on the `released` + `rating` headers and cells; scoped
  CSS rule right-aligns them.
- Fix 10 — Bulk-select column in front of the list-mode table — a bracketed
  `[ ]` glyph per row. List mode only; grid + shelves-by- letter modes do not
  get the column. Bulk-action wiring itself is a separate dispatch.

### Files touched

App:

- `app/helpers/games_helper.rb` — new `game_rating_display(game)`;
  `rating_segment` rewritten to return `<NN>/100` instead of `★ <NN>`; docs
  updated.
- `app/views/games/_genres_shelf.html.erb` — dropped the outer `<h2>genres</h2>`
  heading (Fix 1).
- `app/views/games/index.html.erb` — conditional `<hr class="hairline">` between
  the two outer shelves (Fix 2).
- `app/views/games/_list_mode.html.erb` — full rewrite for Fixes 3 / 4 / 5 / 6 /
  8 / 9 / 10. Drops the `status` column, renames `release year` → `released`
  (full date), renders rating as `<NN>/100`, bolds not-yet-released titles, adds
  `.num` + `[ ]` checkbox column, scopes a new CSS rule that hides the off-theme
  fallback variant inside the cover cell.
- `app/views/games/_grid_mode.html.erb` — `<h2>all games</h2>` → `<h2>all</h2>`
  (Fix 8).
- `app/views/games/_shelves_by_letter_mode.html.erb` — `<h2>all games</h2>` →
  `<h2>all</h2>` (Fix 8).
- `app/views/games/_tile.html.erb` — bolds not-yet-released titles (Fix 6);
  fallback images switched to absolute-positioned overlap (Fix 7); doc comments
  refreshed.
- `app/views/shared/_igdb_cover.html.erb` — drop inline `display: block` from
  the dual fallback `<img>` tags so the class rule wins (Fix 7).

Specs:

- `spec/helpers/games_helper_spec.rb` — rewritten. 22 examples covering
  `format_game_rating`, new `game_rating_display`, and `game_meta_line`
  (post-polish layout `<NN>/100 · <YYYY>`).
- `spec/views/games/_tile.html.erb_spec.rb` — rewritten. 40 examples covering
  happy / sad / edge for the new rating format, Fix 6 bold behavior, Fix 7
  fallback-overlap behavior, variant defaults, linking, native title attribute.
- `spec/views/games/_list_mode.html.erb_spec.rb` — rewritten. 31 examples
  covering the new column order, Fix 3 (status dropped), Fix 4 (full date
  column), Fix 5 (rating format), Fix 6 (bold), Fix 9 (.num), Fix 10
  (bulk-select), Fix 7 (CSS hides off-theme fallback inside the cell).
- `spec/views/games/_grid_mode.html.erb_spec.rb` — Fix 8 assertion.
- `spec/views/games/_genres_shelf.html.erb_spec.rb` — Fix 1 assertion (no outer
  `<h2>genres</h2>`).
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` — Fix 7 assertion (no inline
  `display: block` on fallback images).
- `spec/requests/games_spec.rb` — 2 assertion swaps (`all games` → `all`, no
  outer `<h2>genres</h2>`); 2 new assertions (hairline rendered between the
  shelves; hairline absent when only one shelf renders).
- `spec/system/games_steam_shelf_spec.rb` — Fix 8 assertion.
- `spec/system/games_index_spec.rb` — Fix 1 assertion swap (h2 → no h2;
  lowercase h3 list intact).
- `spec/system/games_display_modes_spec.rb` — Fix 3 + Fix 4 + Fix 8 + Fix 10
  column-order swap.

### Verification

- Targeted game specs: 452 examples, 0 failures.
  - `spec/views/games/` (all view specs)
  - `spec/system/games_*` (display modes, steam shelf, index, multi-version,
    platform ownerships)
  - `spec/requests/games_spec.rb`, `spec/requests/games/`,
    `spec/requests/games_json_spec.rb`,
    `spec/requests/games_show_meta_block_spec.rb`
  - `spec/helpers/games_helper_spec.rb`
- Rubocop clean on the 11 touched Ruby files.
- Brakeman: 0 warnings, 0 errors (8 checks against the full app — no new
  findings from this dispatch).

### Open follow-ups

- Bulk-action wiring for the new list-mode `[ ]` checkbox column — the column
  renders but the action surface is a separate dispatch (architect note: pair
  with the existing `/deletions/:type/:ids` framework once the wiring lands).
- The `STAR_GLYPH` constant is preserved in `GamesHelper` but has no remaining
  caller; the documentation comment now records this. A follow-up dispatch can
  remove it once the team confirms no out-of-tree consumer.

## 2026-05-11 — game show page: canonical platform short names + Xbox seed

User direction (verbatim): "use our clean list like PS5, Switch2" / "GoG, Steam,
Epic, Xbox...". The game show page rendered verbose IGDB-style names
(`Nintendo Switch, PC (Microsoft Windows), PlayStation 4, Xbox One`) — replaced
with the canonical short labels `PS5, Switch2, Steam, GoG, Epic, Xbox`. Xbox
added as the sixth canonical platform.

### Files touched

- `app/models/platform.rb` — added `CANONICAL_SHORT_NAMES` (slug → display
  label), `CANONICAL_SLUGS`, `IGDB_ID_TO_CANONICAL_SLUG` (49/169 → xbox, 167 →
  ps5, 508 → switch2), `.canonical` scope, `#canonical_short_name` /
  `#canonical?` instance helpers.
- `app/helpers/platforms_helper.rb` — new helper. `display_platforms` intersects
  `game.platforms_available` (by canonical slug or IGDB id) with the canonical
  six, layers in Steam/GoG/Epic inferred from `external_steam_app_id` /
  `external_gog_id` / `external_epic_id`, and renders the result in the locked
  order (PS5, Switch2, Steam, GoG, Epic, Xbox). Returns `—` when no canonical
  platform applies.
- `app/views/games/show.html.erb` — the `platforms:` row now calls
  `display_platforms(@game)` instead of mapping `name` over
  `platforms_available`.
- `db/seeds.rb` — Xbox added to the canonical platform seed list (slug `xbox`,
  name `Xbox`, abbreviation `Xbox`).
- `spec/models/platform_spec.rb` — `.canonical` scope coverage and
  `#canonical_short_name` mapping cases (PS5/Switch2/GoG by slug, Xbox One/Xbox
  Series X|S/PS5 by IGDB id, nil for non-canonical).
- `spec/helpers/platforms_helper_spec.rb` — new. Covers the full mapping table
  including dedup, external-id store inference, and the locked render order.
- `spec/requests/games_show_meta_block_spec.rb` — extended with a new "canonical
  platform short-names on the show page" describe block; updated the existing
  details-pane block to use the Switch 2 canonical seed.

### Mapping decisions (locked)

- PlayStation 5 (IGDB 167) → `PS5`
- Nintendo Switch 2 (IGDB 508 / slug `switch2`) → `Switch2`
- Xbox One (IGDB 49) AND Xbox Series X|S (IGDB 169) → `Xbox` (collapsed; project
  does not distinguish generations).
- Steam / GoG / Epic — inferred from `game.external_steam_app_id` /
  `external_gog_id` / `external_epic_id`. PC (Microsoft Windows, IGDB 6) is NOT
  surfaced; the project treats PC distribution stores as the actionable
  platforms.
- Non-canonical IGDB platforms (PlayStation 4, OG Nintendo Switch, PC, anything
  else) — DROPPED from display. Empty result renders as `—`.

### Verification

- Targeted spec count delta: +21 examples across `spec/models/platform_spec.rb`
  (+9, the `.canonical` scope + `#canonical_short_name` cases) and
  `spec/helpers/platforms_helper_spec.rb` (+15 new) and
  `spec/requests/games_show_meta_block_spec.rb` (+5 in the new describe block).
  Mid-session run before an unrelated initializer edit broke the spec loader
  returned 64 examples / 0 failures across the three files.
- Rubocop clean on the 6 touched Ruby files (the ERB view is parsed separately).
- Brakeman: 0 warnings, 0 errors (full app sweep, no new findings).

### Open follow-ups

- IGDB ↔ seed-row deduplication. The seeded canonical rows have
  `igdb_id IS NULL`; an IGDB platform sync will create separate rows for the
  same platform (e.g. seed `ps5` + IGDB-imported "PlayStation 5" with id=167).
  The display helper handles both at render time, but the data-model dedup
  remains an open follow-up (recorded alongside the existing canonical seeds in
  `app/models/platform.rb`).
- The unrelated in-flight auth work landed a `config/initializers/ omniauth.rb`
  change that references `AppSetting` at boot time; the spec loader currently
  raises `NameError: uninitialized constant AppSetting` for any spec that
  requires the Rails env. This blocks running `bin/rspec` end-to-end and is
  independent of the canonical-platform work — handed back to the master for the
  auth lane to resolve.

## [skipci] 2026-05-17 — Switch 2 platform logo: simpleicons -> iconify mdi (pito-rails)

Tactical fix to `lib/tasks/pito_platform_logos.rake`. The
`cdn.simpleicons.org/nintendoswitch/000000` source the v2 spec 07 rake task
relied on now returns HTTP 404 (simpleicons dropped the `nintendoswitch`
slug). Switched switch2 to `api.iconify.design/mdi:nintendo-switch.svg?color=%23000000`
— iconify's Material Design Icons set, 24x24 viewBox, fill="#000000", ~570 bytes.
Audit trail of the 5 candidate URLs (and the wikimedia colored fallback) is
preserved as a comment block above the switch2 entry so the next source-rot
walk doesn't replay the same dead ends.

### Source audit (2026-05-17)

| Candidate | Result |
| --- | --- |
| `cdn.simpleicons.org/nintendoswitch/000000` | HTTP 404 (slug removed) |
| `cdn.simpleicons.org/nintendo-switch/000000` | HTTP 404 |
| `upload.wikimedia.org/.../Nintendo_Switch_2_logo.svg` | HTTP 200 but colored — fails monochrome contract |
| `api.iconify.design/mdi:nintendo-switch.svg?color=%23000000` | HTTP 200, 24x24, black — WINNER |
| `api.iconify.design/cib:nintendo-switch.svg?color=%23000000` | HTTP 200, 32x32, black — viable backup |
| `api.iconify.design/fa-brands:nintendo-switch.svg?color=%23000000` | HTTP 200 but 448x512 — fails square gate |
| `api.iconify.design/logos:nintendo-switch.svg?color=%23000000` | HTTP 404 |
| `api.iconify.design/simple-icons:nintendoswitch.svg?color=%23000000` | HTTP 200, viable backup (iconify mirror still serves the dropped slug) |

### Files touched

- `lib/tasks/pito_platform_logos.rake` — switch2 entry swapped to iconify
  mdi; provider label `iconify-mdi`; commented audit trail of rejected URLs;
  header doc + `source_ext` comment updated to mention both providers.
- `spec/lib/tasks/pito_platform_logos_rake_spec.rb` — `SOURCE_URLS["switch2"]`
  updated; "canonical source" describe block rewritten from "every URL is
  simpleicons + /000000" to "every URL pins fill to black via simpleicons
  /000000 OR iconify color=%23000000"; switch2 non-square WARN regex updated
  to `source=iconify-mdi`; added a new test that asserts the rake task
  preserves the rejected-URL audit comments.
- `public/platform_logos/switch2-{16,64}.png` — regenerated from the iconify
  source. All 10 platform PNGs re-emitted by `bin/rails pito:platform_logos:download`.

### Verification

- `bin/test spec/lib/tasks/pito_platform_logos_rake_spec.rb` — 23 examples,
  0 failures.
- `bin/rails pito:platform_logos:download` — 5/5 `[OK]`, switch2 reports
  `source=iconify-mdi (570B SVG 24.0x24.0) -> 64.png 3.6KB, 16.png 595B`.
- ImageMagick pixel histogram on `switch2-64.png`: every visible pixel has
  RGB `(0,0,0)` (alpha-modulated). Confirmed monochrome black.
- All 10 PNGs verified 16x16 or 64x64 via `identify`.
- `bin/brakeman -q -w2`: 0 security warnings, 0 errors.

### Open follow-ups

- None for this task. If iconify ever 404s the mdi nintendo-switch icon, the
  audit-trail comment points at `cib:nintendo-switch` (32x32 black) and
  `simple-icons:nintendoswitch` (iconify mirror of the dropped simpleicons
  slug) as viable swap-in backups.
