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
