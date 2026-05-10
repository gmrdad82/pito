# Phase 14 §1 — Game Data Model + IGDB v4 Client

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. The MCP
> game-tool surface lands in `03-steam-shelf-ui-and-video-game-links.md`. The
> Rust CLI parity is realignment work unit 10, deferred.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 6.
> - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md` — source of truth for
>   every IGDB-sourced field (the "Fields we pull from IGDB" table), the
>   suggested local schema, the time-to-beat endpoint, the Twitch OAuth
>   client-credentials grant, the "Things IGDB does NOT provide" list, the
>   Apicalypse cheat-sheet, and the auth/rate-limit gotchas.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
>   `tenant_id` on any new table.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline (post-tenant-drop `games` table is the starting point).
> - `CLAUDE.md` — yes/no booleans at every external boundary, secrets in
>   `Rails.application.credentials`, monospace 13px design.

## Goal

Replace the placeholder Phase 4 `Game` model with the full IGDB-backed data
model from Mobile note 4. Bring up the IGDB API v4 client (Twitch OAuth
client-credentials grant, Apicalypse query payloads, rate limiting, token
caching). Wire a per-game on-demand sync flow plus a nightly refresh cron.
Implement strict last-write-wins semantics on re-sync: every IGDB- sourced
column overwrites local edits; local-only columns survive.

This spec covers the data tier and the IGDB-facing service tier. Bundles (Phase
14 §2), the Steam-shelf UI, and the `video_game_link` join (Phase 14 §3) build
on top of this.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                 |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **API.** IGDB API v4 only. Base URL `https://api.igdb.com/v4`. POST per-endpoint with Apicalypse payload bodies. Source: Note 4.                                                                                                                                                                                                                                                         |
| Q2  | **Auth.** Twitch OAuth 2.0 client-credentials grant. Token endpoint `POST https://id.twitch.tv/oauth2/token`. Two headers per IGDB request: `Client-ID: <id>`, `Authorization: Bearer <token>`. Token lifetime ~60 days; cache + refresh. Credentials live in `Rails.application.credentials.igdb.{client_id, client_secret}`.                                                           |
| Q3  | **Rate limit.** 4 req/s, 8 in flight, 429 on overage. Client-side semaphore + token-bucket. Request retries on 429 with exponential backoff, max 3 attempts, jitter.                                                                                                                                                                                                                     |
| Q4  | **Sync model.** Two paths: (a) on-demand single-game sync triggered by user action (add a game by IGDB ID, "re-sync" button on the game page); (b) nightly Sidekiq cron job that re-syncs every game whose `igdb_synced_at` is older than 7 days. No bulk batch sync. Note 4 says "small library; no batch / cron sync needed" — the nightly is light hygiene, not a batch import.       |
| Q5  | **Re-sync semantics.** Last-write-wins. Every IGDB-sourced column is overwritten on every re-sync, even if locally edited. Local-only columns (`platform_owned`, `played_at`, `notes`, `hours_of_footage_manual`) are NEVER touched by sync. Per Note 4 §"Re-sync semantics".                                                                                                            |
| Q6  | **Tenant-free.** No `tenant_id` on any new table. Per ADR 0003.                                                                                                                                                                                                                                                                                                                          |
| Q7  | **Reference tables.** `genres`, `platforms`, `companies` as thin reference rows keyed by IGDB ID + name. NOT materialized as full IGDB mirrors — populated lazily as games reference them. Per Note 4 §"Suggested local schema".                                                                                                                                                         |
| Q8  | **Time-to-beat.** Pulled from the separate `game_time_to_beats` IGDB endpoint (one extra request per game-sync). Three columns: `ttb_main_seconds`, `ttb_extras_seconds`, `ttb_completionist_seconds`. Nullable (partial coverage on IGDB). Per Note 4.                                                                                                                                  |
| Q9  | **Steam / GOG / Epic IDs.** Stored only. No live calls to those storefronts. Per Note 4 §"Steam / GOG / Epic".                                                                                                                                                                                                                                                                           |
| Q10 | **Active Storage cover art.** Phase 4's `Game.cover_art` Active Storage attachment is **retired** as the primary cover surface. The new primary path is `cover_image_id` (IGDB-sourced, URL built at render time via `https://images.igdb.com/igdb/image/upload/t_cover_big/<image_id>.jpg`). The old attachment column degrades to a manual override path documented in Open Questions. |
| Q11 | **Phase 4 placeholder columns.** `games.publisher` (free string) and `games.platforms` (jsonb of platform/owned/recorded_on triples) become **legacy columns** kept for one phase to avoid a big-bang migration. New code does NOT read or write them. They get dropped in the post-Phase-14 polish window once the views and CLI surfaces fully migrate. (See Open Questions #1.)       |
| Q12 | **`Game.collection_id` (Phase 4).** The Phase 4 `belongs_to :collection, optional: true` association stays. It is conceptually orthogonal to Bundles — `Collection` is a project-workspace pivot, `Bundle` is a video-attribution pivot. No merge.                                                                                                                                       |
| Q13 | **External boundary booleans.** Per CLAUDE.md hard rule: every "yes/no" the user, the controller, the MCP tool, or the CLI sees uses `"yes"` / `"no"` strings. Internal storage stays Boolean.                                                                                                                                                                                           |

## Migration posture (LOCKED)

**Additive on the post-Phase-8 schema.** This phase runs after the Phase 8
destructive-and-reseed has already settled the post-tenant baseline. Therefore:

- `add_column` for new columns on `games`.
- `create_table` for new reference / join tables.
- NO `drop_column` on the legacy Phase 4 columns (`publisher`, `platforms`) —
  those are kept until the polish window. `add_column` lines are decorated with
  comments calling out which legacy columns they effectively supersede.
- Rollback is permitted (mechanical) but not a hard requirement.

If the implementation agent finds a column or table already exists, STOP and
surface — do not silently reuse.

## Files touched

### Schema / migrations

- `db/migrate/<NN>_expand_games_for_igdb.rb` (new) — adds the IGDB columns to
  `games`. Rails 8.1-conventional `<YYYYMMDDHHMMSS>_*.rb`.
- `db/migrate/<NN>_create_game_reference_tables.rb` (new) — creates `genres`,
  `platforms`, `companies`. The implementation agent may merge this with the
  previous migration; recommendation is to keep them separate so the `games`
  change set is auditable on its own.
- `db/migrate/<NN>_create_game_join_tables.rb` (new) — creates `game_genres`,
  `game_platforms`, `game_developers`, `game_publishers`.
- `db/schema.rb` — auto-regenerated. Acceptance check: every column + table
  listed in §"Schema" below appears with the declared type + nullability +
  default.

### Models

- `app/models/game.rb` (heavy edit) — see §"Model: Game".
- `app/models/genre.rb` (new).
- `app/models/platform.rb` (new).
- `app/models/company.rb` (new).
- `app/models/game_genre.rb` (new — join model).
- `app/models/game_platform.rb` (new — join model).
- `app/models/game_developer.rb` (new — join model with role).
- `app/models/game_publisher.rb` (new — join model with role).

### Services

- `app/services/igdb/client.rb` (new) — the central HTTP client. Wraps all IGDB
  v4 endpoints used by pito. Methods: `search_games(query, limit:)`,
  `fetch_game(igdb_id)`, `fetch_time_to_beat(igdb_id)`,
  `fetch_genres(igdb_ids)`, `fetch_platforms(igdb_ids)`,
  `fetch_companies(igdb_ids)`, `fetch_external_games(igdb_id)`.
- `app/services/igdb/token_cache.rb` (new) — token acquisition + caching
  (Rails.cache, key `igdb:twitch_token`). On 401 from IGDB, invalidates and
  re-fetches once before propagating.
- `app/services/igdb/rate_limiter.rb` (new) — token-bucket gate (4 req/s, 8 in
  flight). Wraps every outbound request.
- `app/services/igdb/apicalypse.rb` (new) — small DSL builder that emits the
  Apicalypse query body (`fields ...; where ...; limit N;`). Quoted strings
  escape `"` correctly. Numeric IDs are NOT quoted. Source: Note 4 §"Apicalypse
  cheat-sheet".
- `app/services/igdb/game_mapper.rb` (new) — translates IGDB JSON responses into
  local-row attribute hashes. One method per resource type: `map_game(json)`,
  `map_genre(json)`, etc. Handles the IGDB conventions Note 4 calls out
  (Unix-seconds → Date, `cover.image_id`, `external_games[category=1].uid` →
  `external_steam_app_id`, `involved_companies[developer=true].company.name` →
  developers, `game_time_to_beats.{hastily,normally,completely}` →
  `ttb_{main,extras,completionist}_seconds`).
- `app/services/igdb/sync_game.rb` (new) — orchestrator. Single public method
  `call(game)` performs the read-sync flow: fetch IGDB row → map → assign
  IGDB-sourced fields → upsert reference rows + join rows → stamp
  `igdb_synced_at` + `igdb_checksum` → save. Local-only columns are not touched.

### Jobs

- `app/jobs/game_igdb_sync.rb` (new) — Sidekiq job wrapping
  `Igdb::SyncGame#call`. Single argument `game_id`. On `Igdb::Client::Error`
  variants (429, 5xx, network) Sidekiq retries with backoff. On 4xx validation
  errors (game ID does not exist on IGDB), stamps `last_sync_error` and does NOT
  retry.
- `app/jobs/game_igdb_nightly_refresh.rb` (new) — Sidekiq cron job, runs at
  03:00 UTC daily. Iterates
  `Game.where("igdb_synced_at IS NULL OR igdb_synced_at < ?", 7.days.ago)` and
  enqueues `GameIgdbSync` per game, spaced to respect rate limit (one every
  ~300ms).
- `config/sidekiq.yml` (light edit) — register the nightly cron schedule.

### Controllers

- `app/controllers/games_controller.rb` (heavy edit) — extend the existing
  controller. New actions:
  - `search` — `GET /games/search?q=<query>` returns IGDB matches as HTML (Turbo
    Frame for the game-add UI). Bracketed-link results.
  - `add_from_igdb` — `POST /games` with `params[:game][:igdb_id]`. Creates a
    local `Game` row with just `igdb_id` set, enqueues the sync job, redirects
    to `/games/:id` with flash "syncing…".
  - `resync` — `POST /games/:id/resync`. Enqueues `GameIgdbSync`. Redirects with
    flash. Subject to the action-confirmation pattern if re-sync is destructive
    of local IGDB-field edits — recommendation: skip the confirmation screen
    here because the UI surfaces "this will overwrite any local edits to
    IGDB-sourced fields" as inline copy next to the [ resync ] link, AND because
    the local-only columns are safe.
  - The existing `index` / `show` / `update` / `destroy` actions stay; `update`
    permits ONLY local-only fields (`platform_owned`, `played_at`, `notes`,
    `hours_of_footage_manual`). Smuggling guard on every IGDB-sourced column.
  - The Phase 4 `create` action that opens a blank "Untitled game" gets
    deprecated copy ("create empty game (legacy)") and a flash hint pointing the
    user to `[ search igdb ]`. Removed in the polish window.

### Routes

- `config/routes.rb` (light edit) — extend the `resources :games` block:
  - `collection do; get :search; end`
  - `member do; post :resync; end`

### Views

- `app/views/games/index.html.erb` (heavy rewrite happens in §3 — Steam shelf).
  For §1, the existing index-table layout stays; columns gain `igdb_rating`,
  `release_year`, and a `[ resync ]` action.
- `app/views/games/show.html.erb` (heavy edit) — new structure listed below in
  §"View: show.html.erb".
- `app/views/games/_search_results.html.erb` (new) — Turbo Frame partial for
  `search` action results.
- `app/views/games/_add_form.html.erb` (new) — type-ahead search box rendered on
  `/games` (entry point).
- `app/views/shared/_igdb_cover.html.erb` (new) — small partial that builds an
  IGDB cover URL from `cover_image_id` at one of the named sizes
  (`t_cover_small`, `t_cover_big`, `t_thumb`, `t_screenshot_big`, `t_logo_med`).
  Handles nil with a flat `[ no cover ]` placeholder.

### Stimulus controllers

- `app/javascript/controllers/igdb_search_controller.js` (new) — type-ahead
  input that POSTs `/games/search` on debounced input events, target a Turbo
  Frame for the results. NO `confirm()` / `alert()` / `prompt()` usage
  (CLAUDE.md hard rule).
- `app/javascript/controllers/index.js` — register the new controller.

### Credentials

- The architect cannot edit `config/credentials.yml.enc`. The user runs
  `bin/rails credentials:edit --environment development` and adds:
  ```yaml
  igdb:
    client_id: <twitch_client_id>
    client_secret: <twitch_client_secret>
  ```
  Repeat for `--environment test`. Test runs use VCR fixtures (see §"Tests");
  the test-env credentials only need to be non-nil.

### Tests

See §"Test sweep". New / edited spec files:

- `spec/models/game_spec.rb` (heavy rewrite)
- `spec/models/genre_spec.rb` (new)
- `spec/models/platform_spec.rb` (new)
- `spec/models/company_spec.rb` (new)
- `spec/models/game_genre_spec.rb` (new)
- `spec/models/game_platform_spec.rb` (new)
- `spec/models/game_developer_spec.rb` (new)
- `spec/models/game_publisher_spec.rb` (new)
- `spec/factories/games.rb` (heavy rewrite — drop the Phase 4 trait shape; build
  IGDB-backed fixtures)
- `spec/factories/genres.rb` (new)
- `spec/factories/platforms.rb` (new)
- `spec/factories/companies.rb` (new)
- `spec/factories/game_genres.rb` (new)
- `spec/factories/game_platforms.rb` (new)
- `spec/factories/game_developers.rb` (new)
- `spec/factories/game_publishers.rb` (new)
- `spec/services/igdb/client_spec.rb` (new) — VCR-backed
- `spec/services/igdb/token_cache_spec.rb` (new) — VCR-backed
- `spec/services/igdb/rate_limiter_spec.rb` (new) — pure Ruby
- `spec/services/igdb/apicalypse_spec.rb` (new) — pure Ruby
- `spec/services/igdb/game_mapper_spec.rb` (new) — fixture JSON inputs
- `spec/services/igdb/sync_game_spec.rb` (new) — VCR + factory
- `spec/jobs/game_igdb_sync_spec.rb` (new)
- `spec/jobs/game_igdb_nightly_refresh_spec.rb` (new)
- `spec/requests/games_spec.rb` (heavy rewrite — drop Phase 4 placeholder flows;
  cover search, add_from_igdb, resync, scoped update)
- `spec/fixtures/igdb/<id>_game.json` (new — sample IGDB game payload for The
  Legend of Zelda: Breath of the Wild, IGDB ID 7346)
- `spec/fixtures/igdb/<id>_time_to_beat.json` (new — paired)
- `spec/fixtures/igdb/<id>_external_games.json` (new — paired)
- `spec/fixtures/igdb/<id>_genres.json` (new — paired)
- `spec/fixtures/igdb/<id>_platforms.json` (new — paired)
- `spec/fixtures/igdb/<id>_companies.json` (new — paired)
- `spec/cassettes/igdb/...` (VCR cassettes — generated against real IGDB once
  with the dev credentials, then committed and replayed in CI)

### Out of scope (this spec)

- Bundles + composite covers — Phase 14 §2.
- Steam-shelf UI revamp + `video_game_link` join — Phase 14 §3.
- MCP tool surface (`game_sync`, etc.) — Phase 14 §3.
- CLI parity — realignment work unit 10.
- Live Steam / GOG / Epic API hits — Note 4 explicit non-goal.
- Sales / revenue / units sold data — IGDB does not expose this.
- Full IGDB mirror (every game, every screenshot, etc.) — out of scope; pito
  only stores rows for games the user owns.

## Schema

### `games` table — column additions

The post-Phase-8 `games` table currently has:
`id, collection_id, created_at, platforms (jsonb), publisher, title, updated_at`.
The migration adds the columns below. All type/nullability/default pairs are
explicit so the schema dump is auditable.

| #   | Column                      | Type           | Null | Default | Index                   | Notes                                                                                                                                               |
| --- | --------------------------- | -------------- | ---- | ------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `igdb_id`                   | `bigint`       | NULL | —       | unique                  | IGDB primary key. Nullable for the brief window between local row creation and first sync. Once stamped, never changes.                             |
| 2   | `igdb_slug`                 | `string`       | NULL | —       | unique (where not null) | URL-safe slug from IGDB.                                                                                                                            |
| 3   | `igdb_checksum`             | `string`       | NULL | —       | —                       | IGDB-side hash. Bump → re-sync trigger (the nightly job uses this as a no-op-skip signal once it ages past 7 days).                                 |
| 4   | `summary`                   | `text`         | NULL | —       | —                       | Short blurb. May contain newlines.                                                                                                                  |
| 5   | `cover_image_id`            | `string`       | NULL | —       | —                       | The IGDB image ID. URLs are built at render time via the `_igdb_cover.html.erb` partial. Note 4 §"Cover URLs from `cover.url` default to t_thumb".  |
| 6   | `release_date`              | `date`         | NULL | —       | —                       | First release date. Sourced from `first_release_date` (Unix seconds) → Date.                                                                        |
| 7   | `release_year`              | `integer`      | NULL | —       | btree                   | Derived from `release_date.year` (also pre-computed for filter / shelf grouping).                                                                   |
| 8   | `igdb_rating`               | `decimal(5,2)` | NULL | —       | —                       | IGDB user score 0-100.                                                                                                                              |
| 9   | `igdb_rating_count`         | `integer`      | NULL | —       | —                       |                                                                                                                                                     |
| 10  | `aggregated_rating`         | `decimal(5,2)` | NULL | —       | —                       | Critic aggregate (closest legal proxy to "Metacritic").                                                                                             |
| 11  | `aggregated_rating_count`   | `integer`      | NULL | —       | —                       |                                                                                                                                                     |
| 12  | `total_rating`              | `decimal(5,2)` | NULL | —       | —                       | Combined.                                                                                                                                           |
| 13  | `total_rating_count`        | `integer`      | NULL | —       | —                       |                                                                                                                                                     |
| 14  | `external_steam_app_id`     | `string`       | NULL | —       | btree (where not null)  | Stored only. Note 4: extracted via `external_games[category=1].uid`.                                                                                |
| 15  | `external_gog_id`           | `string`       | NULL | —       | —                       | Stored only.                                                                                                                                        |
| 16  | `external_epic_id`          | `string`       | NULL | —       | —                       | Stored only.                                                                                                                                        |
| 17  | `ttb_main_seconds`          | `integer`      | NULL | —       | —                       | From `game_time_to_beats.hastily`. Partial coverage on IGDB (NULL when absent).                                                                     |
| 18  | `ttb_extras_seconds`        | `integer`      | NULL | —       | —                       | From `game_time_to_beats.normally`.                                                                                                                 |
| 19  | `ttb_completionist_seconds` | `integer`      | NULL | —       | —                       | From `game_time_to_beats.completely`.                                                                                                               |
| 20  | `platform_owned_id`         | `bigint`       | NULL | —       | btree                   | FK to `platforms.id`. Local-only — survives re-sync. Note 4 §"Local-only fields".                                                                   |
| 21  | `played_at`                 | `date`         | NULL | —       | —                       | Local-only. Single-date for v1; `played_sessions` table is a future hook.                                                                           |
| 22  | `notes`                     | `text`         | NULL | —       | —                       | Local-only. Free-form, no character limit.                                                                                                          |
| 23  | `hours_of_footage_cached`   | `integer`      | NULL | —       | —                       | Local-only. Derived (sum of duration of joined videos in seconds, divided by 3600). Recomputed by a callback on `video_game_link` create / destroy. |
| 24  | `hours_of_footage_manual`   | `integer`      | NULL | —       | —                       | Local-only. Manual override; takes precedence over `_cached` when non-null. Surfaces in the show page as an editable field.                         |
| 25  | `igdb_synced_at`            | `datetime`     | NULL | —       | btree                   | Stamped by `Igdb::SyncGame` after a successful sync. NULL means "never synced" (the brief window after add_from_igdb).                              |
| 26  | `last_sync_error`           | `text`         | NULL | —       | —                       | Mirrors the Phase 12 `videos.last_sync_error` pattern. Cleared on successful sync.                                                                  |

`title` (existing Phase 4 column) survives. The mapper writes
`igdb_payload["name"]` into `title`; a re-sync overwrites whatever the user
typed locally (last-write-wins per Q5).

### Legacy columns (kept for one phase)

- `publisher` (string, Phase 4) — superseded by `companies` table +
  `game_publishers` join. Leave in place; new code does not read or write it.
  Drop in the polish window.
- `platforms` (jsonb, Phase 4) — superseded by `platforms` table +
  `game_platforms` join. Leave in place; new code does not read or write it.
  Drop in the polish window.

The implementation agent decorates these columns in `Game` with a
`# DEPRECATED — Phase 14 polish drops this; use #companies / #platforms`
comment. The model removes the `platforms_must_be_array_of_allowed_triples`
validator AND the `belongs_to :collection` association stays exactly as Phase 4
had it (per Q12).

### `genres` table (new)

| Column       | Type       | Null | Default | Index  | Notes                             |
| ------------ | ---------- | ---- | ------- | ------ | --------------------------------- |
| `id`         | `bigint`   | NOT  | (pk)    | —      | Local PK.                         |
| `igdb_id`    | `bigint`   | NOT  | —       | unique | IGDB-side ID. Stable.             |
| `name`       | `string`   | NOT  | —       | —      | Display name (e.g., "Adventure"). |
| `slug`       | `string`   | NULL | —       | —      | IGDB slug.                        |
| `created_at` | `datetime` | NOT  | —       | —      |                                   |
| `updated_at` | `datetime` | NOT  | —       | —      |                                   |

### `platforms` table (new)

| Column         | Type       | Null | Default | Index  | Notes                                 |
| -------------- | ---------- | ---- | ------- | ------ | ------------------------------------- |
| `id`           | `bigint`   | NOT  | (pk)    | —      | Local PK.                             |
| `igdb_id`      | `bigint`   | NOT  | —       | unique | IGDB-side ID. Stable.                 |
| `name`         | `string`   | NOT  | —       | —      | Display name (e.g., "PlayStation 5"). |
| `abbreviation` | `string`   | NULL | —       | —      | IGDB-side. e.g., "PS5".               |
| `slug`         | `string`   | NULL | —       | —      |                                       |
| `created_at`   | `datetime` | NOT  | —       | —      |                                       |
| `updated_at`   | `datetime` | NOT  | —       | —      |                                       |

### `companies` table (new)

Renamed away from "developer" / "publisher" because Note 4's
`involved_companies` model uses one Company entity with role flags
(`developer: bool`, `publisher: bool`, `porting: bool`, `supporting: bool`). The
local schema mirrors that with the role on the join, not the entity.

| Column       | Type       | Null | Default | Index  | Notes                 |
| ------------ | ---------- | ---- | ------- | ------ | --------------------- |
| `id`         | `bigint`   | NOT  | (pk)    | —      | Local PK.             |
| `igdb_id`    | `bigint`   | NOT  | —       | unique | IGDB-side ID. Stable. |
| `name`       | `string`   | NOT  | —       | —      | Display name.         |
| `slug`       | `string`   | NULL | —       | —      |                       |
| `created_at` | `datetime` | NOT  | —       | —      |                       |
| `updated_at` | `datetime` | NOT  | —       | —      |                       |

### `game_genres` join (new)

| Column     | Type     | Null | Default | Index                           |
| ---------- | -------- | ---- | ------- | ------------------------------- |
| `id`       | `bigint` | NOT  | (pk)    | —                               |
| `game_id`  | `bigint` | NOT  | —       | btree, FK → games (cascade)     |
| `genre_id` | `bigint` | NOT  | —       | btree, FK → genres (cascade)    |
| —          | —        | —    | —       | unique on `(game_id, genre_id)` |

### `game_platforms` join (new)

| Column        | Type     | Null | Default | Index                              |
| ------------- | -------- | ---- | ------- | ---------------------------------- |
| `id`          | `bigint` | NOT  | (pk)    | —                                  |
| `game_id`     | `bigint` | NOT  | —       | btree, FK → games (cascade)        |
| `platform_id` | `bigint` | NOT  | —       | btree, FK → platforms (cascade)    |
| —             | —        | —    | —       | unique on `(game_id, platform_id)` |

### `game_developers` join (new)

| Column       | Type     | Null | Default | Index                             |
| ------------ | -------- | ---- | ------- | --------------------------------- |
| `id`         | `bigint` | NOT  | (pk)    | —                                 |
| `game_id`    | `bigint` | NOT  | —       | btree, FK → games (cascade)       |
| `company_id` | `bigint` | NOT  | —       | btree, FK → companies (cascade)   |
| —            | —        | —    | —       | unique on `(game_id, company_id)` |

### `game_publishers` join (new)

| Column       | Type     | Null | Default | Index                             |
| ------------ | -------- | ---- | ------- | --------------------------------- |
| `id`         | `bigint` | NOT  | (pk)    | —                                 |
| `game_id`    | `bigint` | NOT  | —       | btree, FK → games (cascade)       |
| `company_id` | `bigint` | NOT  | —       | btree, FK → companies (cascade)   |
| —            | —        | —    | —       | unique on `(game_id, company_id)` |

### Foreign keys to add

- `games.platform_owned_id → platforms.id` (`ON DELETE SET NULL`).
- All four `game_*` join FKs as listed above (`ON DELETE CASCADE`).

## Model: Game

Heavy edit. The model layer:

```ruby
class Game < ApplicationRecord
  # Phase 4 legacy — removed in polish window.
  # validates :platforms ...  REMOVED. The jsonb column survives but
  # has no validator.

  # Phase 4 stays.
  belongs_to :collection, optional: true
  has_many :footages, dependent: :nullify

  # Phase 14 §1.
  belongs_to :platform_owned, class_name: "Platform", optional: true

  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres
  has_many :game_platforms, dependent: :destroy
  has_many :platforms_available, through: :game_platforms,
           source: :platform
  has_many :game_developers, dependent: :destroy
  has_many :developers, through: :game_developers, source: :company
  has_many :game_publishers, dependent: :destroy
  has_many :publishers, through: :game_publishers, source: :company

  validates :title, presence: true, length: { maximum: 255 }
  validates :igdb_id, uniqueness: true, allow_nil: true,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :igdb_slug, uniqueness: true, allow_nil: true
  validates :hours_of_footage_manual,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true

  scope :synced,        -> { where.not(igdb_synced_at: nil) }
  scope :unsynced,      -> { where(igdb_synced_at: nil) }
  scope :stale,         -> { where("igdb_synced_at < ?", 7.days.ago) }
  scope :with_steam,    -> { where.not(external_steam_app_id: nil) }

  def cover_url(size: "t_cover_big")
    return nil if cover_image_id.blank?
    "https://images.igdb.com/igdb/image/upload/#{size}/#{cover_image_id}.jpg"
  end

  def hours_of_footage
    hours_of_footage_manual.presence || hours_of_footage_cached
  end

  def synced?
    igdb_synced_at.present?
  end
end
```

The `cover_url` size whitelist mirrors Note 4: `t_thumb` (90×90),
`t_cover_small` (90×128), `t_cover_big` (227×320), `t_screenshot_med`,
`t_screenshot_big`, `t_logo_med`. The view layer calls
`cover_url(size: "t_cover_big")` for the show page and `t_cover_small` for
shelves. Per-bundle composite covers (Phase 14 §2) read from `t_cover_big` to
source the input tiles.

## Service layer: IGDB client

### `Igdb::Client`

```ruby
module Igdb
  class Client
    BASE_URL = "https://api.igdb.com/v4"

    def initialize(token_cache: TokenCache.new, rate_limiter: RateLimiter.shared)
      @token_cache = token_cache
      @rate_limiter = rate_limiter
    end

    # Methods. Each performs one POST against the named endpoint with the
    # given Apicalypse body. Returns parsed JSON array (every IGDB read
    # endpoint returns an array — the mapper reduces to one row when
    # the caller wants a single result).
    def search_games(query, limit: 10)
    def fetch_game(igdb_id)
    def fetch_time_to_beat(igdb_id)
    def fetch_genres(igdb_ids)
    def fetch_platforms(igdb_ids)
    def fetch_companies(igdb_ids)
    def fetch_external_games(igdb_id)

    private

    def post(endpoint, body)
      @rate_limiter.acquire do
        token = @token_cache.token
        response = Net::HTTP.post(
          URI("#{BASE_URL}/#{endpoint}"),
          body,
          "Client-ID" => Rails.application.credentials.igdb.client_id,
          "Authorization" => "Bearer #{token}",
          "Content-Type" => "text/plain"
        )

        case response.code.to_i
        when 200 then JSON.parse(response.body)
        when 401 then handle_401(endpoint, body)  # one retry after token refresh
        when 429 then raise RateLimited.new(retry_after: response["Retry-After"])
        when 400..499 then raise ValidationError.new(response.body)
        when 500..599 then raise ServerError.new(response.code)
        end
      end
    end
  end

  class Error < StandardError; end
  class RateLimited < Error
    attr_reader :retry_after
    def initialize(retry_after:); @retry_after = retry_after; super; end
  end
  class ValidationError < Error; end
  class ServerError < Error; end
  class AuthError < Error; end
end
```

Note 4 cheat-sheet integration: every `post` body is built via `Apicalypse` (see
below). Endpoints used:

- `games` — `fetch_game`, `search_games`
- `game_time_to_beats` — `fetch_time_to_beat`
- `genres` — `fetch_genres`
- `platforms` — `fetch_platforms`
- `companies` — `fetch_companies`
- `external_games` — `fetch_external_games`

`search_games` uses the dedicated search syntax:
`search "<query>"; fields name, slug, cover.image_id, first_release_date; limit <N>;`.
No `where` clause is allowed in the same query (Note 4 gotcha #6).

### `Igdb::TokenCache`

Caches the Twitch client-credentials token in `Rails.cache` under key
`"igdb:twitch_token"` for `expires_in - 60s`. On miss, hits
`POST https://id.twitch.tv/oauth2/token?client_id=...&client_secret=...&grant_type=client_credentials`.
On 401 from IGDB, the cache is invalidated; the client retries the original
request once with a fresh token.

### `Igdb::RateLimiter`

Token-bucket. Capacity 4 / refill rate 4 per 1.0s. Concurrency cap 8 in flight
(Mutex + counter). `acquire(&block)` blocks until a token is available, runs the
block, returns its value. Implementation lives process-local (one bucket per
Rails process); the nightly cron uses `sleep 0.3` between enqueues to spread
load across Sidekiq workers.

### `Igdb::Apicalypse`

Tiny DSL builder:

```ruby
Igdb::Apicalypse.new
  .fields("name", "slug", "cover.image_id", "genres.id", "genres.name")
  .where("id = 7346")
  .limit(1)
  .to_s
# => "fields name, slug, cover.image_id, genres.id, genres.name; where id = 7346; limit 1;"
```

Quoted strings escape `"`. Numeric IDs do NOT get quoted. Multi-clause `where`
joins via `&` (AND) per Note 4. The builder is intentionally small — pito only
uses a handful of patterns.

### `Igdb::GameMapper`

Stateless module. One method per resource type. Translates IGDB JSON into
local-row attribute hashes. Conventions per Note 4:

- `first_release_date` (Unix seconds) → `Time.at(...).to_date`
- `cover.image_id` (string) → `cover_image_id`
- `external_games[category=1].uid` → `external_steam_app_id` (string)
- `external_games[category=5].uid` → `external_gog_id` (architect picks the GOG
  category — Note 4 says "Same pattern; the `category` enum identifies the
  source"; implementation agent verifies the exact category number against IGDB
  docs and stamps it as a constant in the mapper)
- `external_games[category=26].uid` → `external_epic_id` (same caveat — verify
  the category)
- `involved_companies[developer=true].company.{id,name,slug}` → one `companies`
  row + one `game_developers` join row each
- `involved_companies[publisher=true].company.{id,name,slug}` → same shape,
  `game_publishers`
- `genres[]` → upsert `genres` rows, create `game_genres` joins
- `platforms[]` → upsert `platforms` rows, create `game_platforms` joins
- `game_time_to_beats.{hastily,normally,completely}` → `ttb_main_seconds`,
  `ttb_extras_seconds`, `ttb_completionist_seconds`
- Note 4 gotcha #4: `category` and `status` fields on Game are deprecated; use
  `game_type` and `game_status`. Read both during transition; we don't write
  either today (no schema column for them). Decision: skip.

### `Igdb::SyncGame`

Orchestrator. Single public method:

```ruby
class Igdb::SyncGame
  def initialize(client: Igdb::Client.new); @client = client; end

  def call(game)
    raise ArgumentError, "no igdb_id" if game.igdb_id.blank?

    game_json = @client.fetch_game(game.igdb_id).first
    raise Igdb::Client::ValidationError, "not found on IGDB" if game_json.nil?

    ttb_json   = @client.fetch_time_to_beat(game.igdb_id).first
    extern_json = @client.fetch_external_games(game.igdb_id)

    attrs = Igdb::GameMapper.map_game(game_json, ttb_json, extern_json)

    Game.transaction do
      game.update!(attrs.merge(
        igdb_synced_at: Time.current,
        last_sync_error: nil
      ))
      sync_genres(game, game_json["genres"])
      sync_platforms(game, game_json["platforms"])
      sync_developers(game, game_json["involved_companies"])
      sync_publishers(game, game_json["involved_companies"])
    end

    game
  rescue Igdb::Client::ValidationError => e
    game.update!(last_sync_error: e.message)
    raise
  end
end
```

Last-write-wins: every IGDB-sourced column is in `attrs`. Local-only columns
(`platform_owned_id`, `played_at`, `notes`, `hours_of_footage_manual`) are NOT
in `attrs`; they pass through the `update!` untouched.

The four `sync_*` private methods upsert reference rows by `igdb_id` (Genre /
Platform / Company), then replace the join rows for this game (delete-and-create
— this is the simplest correct shape; the join volume per game is small, max ~15
genres, ~5 platforms, ~5 companies).

## Job: `GameIgdbSync`

```ruby
class GameIgdbSync
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(game_id)
    game = Game.find(game_id)
    Igdb::SyncGame.new.call(game)
  rescue Igdb::Client::RateLimited => e
    sleep(e.retry_after.to_i.clamp(1, 60))
    raise # let Sidekiq retry with backoff
  rescue Igdb::Client::ValidationError
    # local row stamped with last_sync_error inside SyncGame; no retry
  end
end
```

## Job: `GameIgdbNightlyRefresh`

```ruby
class GameIgdbNightlyRefresh
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform
    Game.synced.stale.find_each do |game|
      GameIgdbSync.perform_async(game.id)
      sleep 0.3 # ~3 enqueues per second to respect IGDB rate limit
    end
  end
end
```

`config/sidekiq.yml` registration:

```yaml
:schedule:
  game_igdb_nightly_refresh:
    cron: '0 3 * * *'
    class: GameIgdbNightlyRefresh
```

## View: show.html.erb

Section order on `/games/:id`:

1. **Cover + title block** — left column renders the IGDB cover at `t_cover_big`
   size; right column renders title (h1), release_year, developer / publisher
   names. `[ resync ]` bracketed-link in the action row. `[ open on igdb ]`
   bracketed-link to `https://www.igdb.com/games/<igdb_slug>` (built from
   `igdb_slug`).
2. **Summary** — IGDB summary text. Plain paragraph.
3. **Ratings** — IGDB rating, aggregated rating, total rating, each with sample
   count (Note 4: "UI should display rating count alongside the score so a small
   sample is visible").
4. **Time to beat** — three rows: main / extras / completionist. Render "—" when
   NULL. Display in hours:minutes (e.g., "23h 30m").
5. **Genres / platforms** — comma-separated lists.
6. **External IDs** — Steam app ID / GOG ID / Epic ID as bracketed links to the
   storefront landing page (built lexically; pito does not call those APIs).
7. **Local-only fields** (editable, single fieldset, posts to
   `PATCH /games/:id`):
   - `platform_owned` — select dropdown of Platforms (sourced from
     `platforms_available` for this game).
   - `played_at` — date input.
   - `notes` — textarea.
   - `hours_of_footage_manual` — numeric input. Tooltip: "leave blank to compute
     from linked videos".
8. **Sync metadata** — `igdb_synced_at` ("synced 3 hours ago"),
   `last_sync_error` (inline warning if present).

Design system per `docs/design.md` (monospace 13px, bracketed-link convention,
no animation, cursor pointer on clickables).

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows `games` table with all columns from §"games table —
      column additions" present with correct types and nullability.
- [ ] `db/schema.rb` shows `genres`, `platforms`, `companies` tables with the
      listed columns + indexes.
- [ ] `db/schema.rb` shows `game_genres`, `game_platforms`, `game_developers`,
      `game_publishers` join tables with `(game_id, *)` unique index each.
- [ ] FK `games.platform_owned_id → platforms.id` exists with
      `ON DELETE     SET NULL`.
- [ ] All four `game_*` join FKs exist with `ON DELETE CASCADE`.
- [ ] Migration runs cleanly: `bin/rails db:migrate` succeeds; rollback if
      attempted runs without raising (mechanical reversibility).
- [ ] Phase 4 legacy columns `publisher` and `platforms` (jsonb) still exist
      (kept until polish window).

### Models

- [ ] `Game` declares the new associations (`genres`, `platforms_available`,
      `developers`, `publishers`, `platform_owned`).
- [ ] `Game` no longer enforces the Phase 4
      `platforms_must_be_array_of_allowed_triples` validator.
- [ ] `Game.cover_url` returns a well-formed URL when `cover_image_id` is
      present and `nil` when blank.
- [ ] `Game.hours_of_footage` prefers `_manual` over `_cached` and falls back to
      `_cached` when manual is nil.
- [ ] `Genre`, `Platform`, `Company` validate `igdb_id` presence + uniqueness +
      `name` presence.
- [ ] All four join models validate `(game_id, <other>_id)` uniqueness.

### Services

- [ ] `Igdb::Client.new.search_games("zelda", limit: 5)` returns an array of
      hashes (VCR cassette).
- [ ] `Igdb::Client.new.fetch_game(7346)` returns a single-element array (VCR
      cassette).
- [ ] `Igdb::TokenCache#token` caches the token across calls; invalidation on
      401 forces a refresh on the next call.
- [ ] `Igdb::RateLimiter` blocks the 5th request in a 1-second window until a
      token frees.
- [ ] `Igdb::RateLimiter` allows up to 8 concurrent in-flight requests and
      blocks the 9th.
- [ ] `Igdb::Apicalypse#to_s` produces the documented format
      (semicolon-terminated, comma-separated fields, AND via `&`).
- [ ] `Igdb::GameMapper.map_game(json, ttb, extern)` returns a hash with every
      IGDB-sourced column populated (local-only columns absent from the hash).
- [ ] `Igdb::SyncGame#call(game)` overwrites IGDB-sourced columns, preserves
      local-only columns, stamps `igdb_synced_at`, clears `last_sync_error`.

### Jobs

- [ ] `GameIgdbSync` enqueues on the `:default` queue.
- [ ] `GameIgdbSync` retries on `RateLimited` and `ServerError` (up to 5
      attempts).
- [ ] `GameIgdbSync` does NOT retry on `ValidationError`.
- [ ] `GameIgdbNightlyRefresh` is registered with sidekiq-cron at `0 3 * * *`.
- [ ] `GameIgdbNightlyRefresh#perform` enqueues sync for every game with
      `igdb_synced_at < 7.days.ago`.
- [ ] `GameIgdbNightlyRefresh#perform` does NOT enqueue sync for games with no
      `igdb_id` (those rows aren't IGDB-backed).

### Controllers

- [ ] `GET /games/search?q=zelda` returns 200 with HTML containing IGDB results
      (Turbo Frame).
- [ ] `POST /games` with `igdb_id=7346` creates a Game row, enqueues
      `GameIgdbSync`, redirects to `/games/:id` with flash.
- [ ] `POST /games/:id/resync` enqueues `GameIgdbSync`, redirects with flash.
- [ ] `PATCH /games/:id` permits only `platform_owned_id`, `played_at`, `notes`,
      `hours_of_footage_manual`.
- [ ] `PATCH /games/:id` smuggling guard: `igdb_id`, `cover_image_id`,
      `summary`, `igdb_rating`, etc. silently dropped.

### Credentials

- [ ] `Rails.application.credentials.igdb.client_id` non-nil in development +
      test.
- [ ] `Rails.application.credentials.igdb.client_secret` non-nil in both.

### Tests

- [ ] `bundle exec rspec spec/models/` green for every new / edited model spec.
- [ ] `bundle exec rspec spec/services/igdb/` green.
- [ ] `bundle exec rspec spec/jobs/` green for the two new jobs.
- [ ] `bundle exec rspec spec/requests/games_spec.rb` green.
- [ ] VCR cassettes for IGDB endpoints checked into `spec/cassettes/igdb/` and
      replay deterministically.

## Test sweep (exhaustive)

### `Game` model unit specs (`spec/models/game_spec.rb`)

**Associations:**

- `belongs_to :collection, optional: true` (carryover)
- `has_many :footages, dependent: :nullify` (carryover)
- `belongs_to :platform_owned, class_name: "Platform", optional: true`
- `has_many :game_genres, dependent: :destroy`
- `has_many :genres, through: :game_genres`
- `has_many :game_platforms, dependent: :destroy`
- `has_many :platforms_available, through: :game_platforms, source: :platform`
- `has_many :game_developers, dependent: :destroy`
- `has_many :developers, through: :game_developers, source: :company`
- `has_many :game_publishers, dependent: :destroy`
- `has_many :publishers, through: :game_publishers, source: :company`

**Validations — `title`:**

- Presence required
- Length ≤ 255 (boundary case 255 + 256)
- Unicode allowed
- Default value "Untitled game" when not set explicitly (carryover)

**Validations — `igdb_id`:**

- Allowed nil (unsynced row)
- Unique (build a second game with same id → invalid)
- Numericality, integer, > 0
- Negative rejected
- Zero rejected
- Float rejected

**Validations — `igdb_slug`:**

- Allowed nil
- Unique when present

**Validations — `hours_of_footage_manual`:**

- Allowed nil
- Integer ≥ 0
- Negative rejected
- Float rejected

**Scopes:**

- `.synced` includes only rows with `igdb_synced_at` set
- `.unsynced` is the complement
- `.stale` includes only rows with `igdb_synced_at < 7.days.ago` (and none with
  NULL — `synced.stale` is the right composition)
- `.with_steam` includes only rows with `external_steam_app_id` non- blank

**Methods:**

- `cover_url` returns nil when `cover_image_id` is blank
- `cover_url` returns the well-formed URL pattern when present
- `cover_url(size: "t_thumb")` substitutes the size token
- `cover_url(size: "<unknown>")` raises a clear ArgumentError (whitelist
  enforcement)
- `hours_of_footage` returns `_manual` when set
- `hours_of_footage` falls back to `_cached` when `_manual` is nil
- `hours_of_footage` returns nil when both are nil
- `synced?` true when `igdb_synced_at` set, false otherwise

**Edge cases:**

- Very long title (300 chars): rejected
- Title containing emoji: accepted
- Title containing only whitespace: rejected (presence)
- IGDB ID collision: second game with same `igdb_id` invalid

### `Genre`, `Platform`, `Company` model unit specs

Each model:

- `igdb_id` presence + uniqueness + numericality > 0
- `name` presence
- Unicode in `name` accepted
- Long names (255 boundary) — accepted to 255, rejected at 256

### Join model unit specs

For `GameGenre`, `GamePlatform`, `GameDeveloper`, `GamePublisher`:

- `belongs_to :game`
- `belongs_to :<reference>`
- Composite uniqueness `(game_id, <reference>_id)`
- Cascade-on-delete from each side

### `Igdb::Client` specs (VCR-backed)

- `search_games("zelda", limit: 5)` returns an array of hashes, length ≤ 5
- `search_games("zelda")` defaults to limit 10
- `search_games("")` rejects with ArgumentError
- `search_games("'; drop;")` quote-escapes correctly (does NOT pass through to
  the body unescaped)
- `fetch_game(7346)` returns a one-element array with `name`, `summary`,
  `cover.image_id`
- `fetch_game(99999999999)` returns `[]` (not found)
- `fetch_time_to_beat(7346)` returns a one-element array OR `[]` for
  partial-coverage games
- `fetch_genres([31, 32])` returns matching genre rows
- `fetch_platforms([6, 48])` returns matching platform rows
- `fetch_companies([1, 2])` returns matching company rows
- `fetch_external_games(7346)` returns the game's external storefront links

**Auth flow:**

- Valid token (cached): one HTTP call against IGDB
- 401 from IGDB: token invalidated, retry once with fresh token, succeeds
- 401 twice in a row: raises `Igdb::Client::AuthError`

**Rate limit:**

- 429 with `Retry-After` 5: raises `Igdb::Client::RateLimited` with
  `retry_after = 5`
- 429 without `Retry-After`: raises with `retry_after = 1` (default)

**HTTP errors:**

- 400 → `ValidationError(<body>)`
- 404 → empty array (returned cleanly)
- 500 → `ServerError(500)`
- Network timeout → propagates as `Net::OpenTimeout` for Sidekiq retry

**Apicalypse body shape:**

- The body POSTed to `/games` for `fetch_game(7346)` literally equals the
  documented Apicalypse string (regex-asserted in a spec)
- The body for `search_games("zelda", limit: 5)` matches
  `search "zelda"; fields ...; limit 5;`

### `Igdb::TokenCache` specs

- First call hits Twitch, caches the token
- Second call (within TTL) does NOT hit Twitch
- Third call (after TTL elapses, simulated via `travel`) hits Twitch again
- `invalidate!` clears the cache
- Twitch returning 400 raises `Igdb::Client::AuthError` with body
- Twitch returning 200 with malformed JSON raises clear error

### `Igdb::RateLimiter` specs

- Within 1 second, requests 1-4 acquire immediately
- Request 5 in the same window blocks until at least 1.0s has passed since
  request 1
- Concurrent: 8 in flight → ninth blocks until one completes
- `acquire(&block)` returns block's value
- Block raising propagates the exception AND releases the slot

### `Igdb::Apicalypse` specs

- `.fields("a", "b").to_s` → `"fields a, b;"`
- `.where("id = 1").to_s` includes `"where id = 1;"`
- `.where("a > 1").where("b < 2").to_s` joins with `&` (AND)
- `.limit(10).to_s` includes `"limit 10;"`
- `.search("zelda").to_s` includes `'search "zelda";'`
- Search query containing `"`: escaped to `\"`
- Search query empty / nil: ArgumentError
- Limit non-integer: ArgumentError
- `.fields().to_s` with no fields: ArgumentError

### `Igdb::GameMapper` specs

Fixture inputs from `spec/fixtures/igdb/`. For `7346` (Breath of the Wild):

- `map_game(json)` returns a hash with:
  - `title: "The Legend of Zelda: Breath of the Wild"`
  - `igdb_slug: "the-legend-of-zelda-breath-of-the-wild"`
  - `summary: "..."` (matches fixture)
  - `cover_image_id: "..."` (matches fixture)
  - `release_date: 2017-03-03`
  - `release_year: 2017`
  - `igdb_rating: 95.x` (decimal; matches fixture within rounding)
  - `total_rating: ...`, etc.
- `map_external_games([{category: 1, uid: "1086940"}, ...])` →
  `{external_steam_app_id: "1086940", external_gog_id: nil, external_epic_id: nil}`
- `map_time_to_beat({hastily: 180_000, normally: 360_000, completely: 720_000})`
  →
  `{ttb_main_seconds: 180000, ttb_extras_seconds: 360000, ttb_completionist_seconds: 720000}`
- `map_time_to_beat(nil)` (game with no TTB row) →
  `{ttb_main_seconds: nil, ttb_extras_seconds: nil, ttb_completionist_seconds: nil}`
- Unix-second `first_release_date` → correct Date in UTC
- Missing `cover.image_id`: `cover_image_id: nil`
- Missing `genres`: empty array (not nil)

### `Igdb::SyncGame` specs

- `call(game)` with valid `igdb_id` populates every IGDB-sourced column from the
  fixture
- `call(game)` does NOT touch local-only columns (`platform_owned_id`,
  `played_at`, `notes`, `hours_of_footage_manual`) — set them before call,
  assert they survive
- `call(game)` stamps `igdb_synced_at` and clears `last_sync_error`
- `call(game)` with non-existent `igdb_id` (IGDB returns `[]`): raises
  `Igdb::Client::ValidationError`, stamps `last_sync_error`
- Sync creates `Genre` rows for genres new to the install
- Sync upserts (does NOT duplicate) when a `Genre` already exists for the same
  `igdb_id`
- Sync replaces `game_genres` join rows on re-sync (delete-and-create semantics;
  pre-existing joins removed)
- Same shape for platforms / developers / publishers
- Transaction: if any sub-step raises, the whole `update!` rolls back (verify by
  stubbing one of the `sync_*` methods to raise)
- Local edits: set `notes` to "my notes", `played_at` to a date, call sync;
  assert both survive verbatim
- Last-write-wins: set `title` locally to "My Renamed Game", call sync, assert
  title is overwritten with IGDB's value

### `GameIgdbSync` job specs

- `perform(game_id)` invokes `Igdb::SyncGame.new.call(game)`
- On `RateLimited`: sleeps for `retry_after`, raises (Sidekiq retries)
- On `ServerError`: raises (Sidekiq retries)
- On `ValidationError`: catches, no re-raise (no Sidekiq retry)
- Default retry count: 5 (Sidekiq config)
- Job is enqueued on the `:default` queue

### `GameIgdbNightlyRefresh` job specs

- Enqueues sync for stale synced games
- Does NOT enqueue for never-synced games (`igdb_synced_at IS NULL`)
- Does NOT enqueue for fresh games (`igdb_synced_at < 7.days.ago` filter —
  verify boundary at exactly 7 days)
- `sleep 0.3` is invoked between enqueues (mock `sleep`, assert call count)
- With zero stale games, perform completes without error and without enqueues
- Sidekiq cron registration: `cron: '0 3 * * *'` exact match

### `GamesController` request specs (`spec/requests/games_spec.rb`)

**`GET /games/search?q=zelda` (happy):**

- 200, renders results partial as Turbo Frame
- Results contain at least one IGDB hit
- Each result shows title, release_year, cover image, `[ add ]` button POSTing
  to `/games` with `igdb_id`

**`GET /games/search?q=` (sad):**

- Blank query → 200 with empty-state copy
- Query > 100 chars → 422 (truncate or reject — implementation agent's call;
  spec encodes the chosen behavior)

**`POST /games` with valid `igdb_id`:**

- Creates a Game row with the given `igdb_id`
- Enqueues `GameIgdbSync`
- 302 to `/games/:id` with flash "syncing…"
- Subsequent visit to `/games/:id` (after job runs) shows full data

**`POST /games` with duplicate `igdb_id`:**

- 422 with flash "already in your library — [ open ]"
- Does NOT create a duplicate row
- Does NOT enqueue sync

**`POST /games/:id/resync`:**

- Enqueues `GameIgdbSync`
- 302 to `/games/:id` with flash "syncing…"
- 404 when game does not exist

**`PATCH /games/:id` (happy — local-only fields):**

- Permits `platform_owned_id`, `played_at`, `notes`, `hours_of_footage_manual`
- Updates each, redirects, flash
- The `after_update_commit` hook does NOT enqueue sync (these are local-only
  fields)

**`PATCH /games/:id` (smuggling guards — silently dropped):**

- `igdb_id` in params: value unchanged
- `cover_image_id` in params: value unchanged
- `summary` in params: value unchanged
- `igdb_rating` in params: value unchanged
- Every other IGDB-sourced column smuggled: value unchanged

**`DELETE /games/:id`:**

- Existing Phase 4 behavior preserved
- Cascade: `game_genres`, `game_platforms`, `game_developers`, `game_publishers`
  join rows destroyed

**Backward compatibility (Phase 4 placeholder create):**

- `POST /games` with no body still creates an "Untitled game" row (deprecated
  copy in the flash)

### Edge cases (full sweep)

- Game with `igdb_id` set but `igdb_synced_at` NULL: `[ resync ]` visible, all
  IGDB-sourced fields render as "—"
- Game synced once, then the IGDB row is deleted on IGDB's side: a re-sync
  raises `ValidationError`, stamps `last_sync_error`, leaves the local row
  intact (pito is the local source of truth)
- Game with no cover (`cover_image_id` NULL): `_igdb_cover.html.erb` renders the
  `[ no cover ]` placeholder
- Game with no time-to-beat row: all three `ttb_*` columns NULL, view renders
  "—"
- IGDB returns a game with 50 genres (unrealistic but possible): all 50 join
  rows created; index page joins efficiently
- Twitch credential rotation: `igdb:twitch_token` cache survives Rails restart
  only as long as Rails.cache survives (file-store on disk in dev — verify
  behavior)
- Network timeout to IGDB: Sidekiq retries the job; the user sees
  `last_sync_error` set to "timed out" after retries exhaust
- Apicalypse query injection attempt: title contains `"; drop table games; --`.
  The Apicalypse builder escapes the inner `"`; IGDB receives a literal string,
  not a query injection. Spec asserts the request body doesn't contain raw
  injection.
- IGDB ID smuggled via `PATCH /games/:id`: dropped by strong params, asserted by
  `expect { … }.not_to change { game.reload.igdb_id }`

## Manual playbook (post-implementation)

1. **Update credentials.** Run
   `bin/rails credentials:edit --environment development`. Add the `igdb:` block
   per §"Credentials". Repeat for `--environment test` (test values just need to
   be non-nil — VCR cassettes are authoritative).
2. **Migrate.**
   ```bash
   bin/rails db:migrate
   ```
   Reseed not required (additive migration).
3. **Visit `/games`.** Confirm empty state OR existing Phase 4 rows. Existing
   rows have `igdb_synced_at = NULL` and render with "—" in IGDB columns.
4. **Add a game by IGDB.** Visit `/games`. Click `[ search igdb ]`, type
   "zelda", click `[ add ]` next to a result. Confirm redirect to `/games/:id`
   with flash "syncing…". Refresh after ~1s; confirm IGDB-sourced fields
   populate.
5. **Re-sync.** Click `[ resync ]` on the same game. Confirm `igdb_synced_at`
   updates within a few seconds.
6. **Local-only edits.** On the game show page, set `notes`, `played_at`,
   `hours_of_footage_manual`. Save. Click `[ resync ]`. Confirm local-only
   fields survive verbatim.
7. **Last-write-wins.** Open a Rails console, set
   `Game.find(:id).update!(title: "MY EDITED TITLE")`. Reload the show page.
   Click `[ resync ]`. Confirm title overwrites back to IGDB's value.
8. **Nightly refresh smoke.** From `bundle exec rails console`:
   `GameIgdbNightlyRefresh.new.perform`. Confirm Sidekiq enqueues N
   `GameIgdbSync` jobs at one per ~300ms.
9. **Rate-limit smoke.** Hammer `Igdb::Client.new.fetch_game(7346)` 10 times in
   a tight loop in the console. Confirm the 5th+ calls block ~1s each (4 req/s
   ceiling).
10. **Run the suite.**
    ```bash
    bundle exec rspec
    ```
    Confirm green. Spec count delta logged in `log.md`.

## Cross-stack scope

| Surface         | Status                                                                                    |
| --------------- | ----------------------------------------------------------------------------------------- |
| Rails web app   | **In scope.** Primary lane.                                                               |
| MCP rack app    | **Skipped here.** MCP `game_*` tools land in `03-steam-shelf-ui-and-video-game-links.md`. |
| Doorkeeper      | **Untouched.**                                                                            |
| `pito` CLI      | **Skipped.** Realignment work unit 10.                                                    |
| Astro / website | **N/A.**                                                                                  |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **`/games` page heading.** Currently "games" (lowercase per design system).
   Confirm or shift.
2. **Empty-state copy on `/games` (no rows).** Currently "no games yet." Suggest
   shift to "no games yet. [ search igdb ] to add one."
3. **`[ search igdb ]` button label.** Alternatives: `[ add game ]`,
   `[ + game ]`, `[ search ]`.
4. **Search results empty state.** "no results for '<query>'." vs. "nothing on
   igdb matches '<query>'."
5. **Add-game flash.** "syncing…" vs "queued — refresh to see metadata." vs
   "added; metadata loading in background."
6. **Re-sync flash.** "syncing…" vs "refreshing from igdb…"
7. **Last-write-wins inline copy.** Suggested: "re-sync overwrites any local
   edits to igdb-sourced fields. local notes, played-on date, footage hours, and
   platform-owned survive." Confirm or shorten.
8. **`last_sync_error` inline copy prefix.** "sync error:" vs "couldn't sync:"
   vs "igdb error:".
9. **`[ no cover ]` placeholder.** vs `[ no art ]` vs `[ ? ]`.
10. **External-store link labels.** `[ steam ]` / `[ gog ]` / `[ epic ]` vs
    `[ steam page ]` / `[ gog page ]` / `[ epic page ]`.
11. **Rating display format.** "95 (1.2k votes)" vs "95 / 100 (1234 votes)" vs
    "95 ★ (1234)".
12. **Time-to-beat empty cell.** "—" vs "no data" vs blank.

## Open questions (architect cannot decide; master agent surfaces)

1. **Phase 4 legacy `publisher` + `platforms` columns — drop now or defer to
   polish?** Recommendation: defer. Dropping mid-Phase-14 would force the
   Steam-shelf UI (Phase 14 §3) and the CLI (work unit 10) to migrate
   atomically; deferring lets the new shape stabilize first. The legacy columns
   get a one-line "DEPRECATED" comment in the model + a follow-up entry in
   `docs/orchestration/follow-ups.md`. Master agent confirms.

2. **Phase 4 `Game.cover_art` Active Storage attachment — kept, dropped, or
   repurposed as manual override?** Note 4 says cover URLs are built at render
   time from `cover_image_id`. The Active Storage attachment served the Phase 4
   placeholder use case. Options:
   - (a) Drop entirely. Simpler. Loses any locally-uploaded cover for games not
     on IGDB.
   - (b) Keep. New `cover_url` method prefers `cover_image_id` and falls back to
     the Active Storage variant URL. Complex but preserves a use case.
   - (c) Rename to `manual_cover_art`, surface only on the show page edit form,
     document as "use this when IGDB has no cover image ID for the game."
     Recommendation: **(c)**. The use case is rare but real (some IGDB rows lack
     cover_image_id; user-uploaded fallback works). Master agent picks.

3. **GOG / Epic IGDB category numbers.** Note 4 mentions Steam = category 1
   explicitly; the GOG and Epic categories are referenced without the numeric
   value. Implementation agent verifies against
   `https://api-docs.igdb.com/#external-game-enums` at the time of
   implementation, stamps the constants in `Igdb::GameMapper`, and surfaces in
   the log if either is unstable.

4. **Rate-limiter scope: process-local vs Redis-backed?** Process- local is
   simpler but a multi-Sidekiq-worker setup may collectively exceed 4 req/s if
   each worker has its own bucket. Recommendation: **process-local for v1**;
   Sidekiq queue config caps concurrency such that the aggregate stays well
   under 4 req/s. If a future Hetzner deploy with multiple Sidekiq processes
   shows 429s, switch to a Redis-backed limiter (`Concurrent::RateLimiter` over
   Redis).

5. **`igdb_synced_at` precision (datetime vs date) for the nightly stale
   check.** Recommendation: datetime. Sub-day precision matters when a manual
   re-sync happens at 14:00 and the nightly fires at 03:00 the next day —
   without sub-day precision the manual re-sync would not protect against the
   redundant nightly enqueue. Master agent confirms.

6. **Do we cache IGDB cover image bytes locally?** Note 4: "downloaded once and
   cached" for composite cover sources. For non-composite uses (the show page,
   the Steam shelf), the IGDB CDN serves the image directly to the browser — no
   local cache needed. Phase 14 §2 (composite covers) introduces a cache for the
   bundle-cover pipeline. Confirm: the show page ALWAYS hits images.igdb.com, no
   local proxy.

7. **What happens when IGDB renames a `slug`?** IGDB-side slugs are said to be
   stable but rename happens for trademark / acquisition reasons. Our
   `igdb_slug` index is unique. On re-sync, the mapper blindly writes the new
   slug; if a different game already used that slug locally, the unique
   constraint raises. Recommendation: the mapper catches
   `ActiveRecord::RecordNotUnique` on slug collision, falls back to NULL, stamps
   `last_sync_error`, lets the user resolve manually. Master agent confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. `/games` page heading → `games` (lowercase).
2. Empty state → `no games yet. [ search igdb ] to add one.`
3. Search button label → `[ search igdb ]`.
4. Search results empty → `no results for '<query>'.`
5. Add-game flash → `added; metadata loading in background.`
6. Re-sync flash → `refreshing from igdb…`
7. Last-write-wins inline prose →
   `re-syncing overwrites igdb-sourced fields. local notes, played-on, footage hours, and platform-owned survive.`
8. `last_sync_error` prefix → `igdb error:`
9. `[ no cover ]` placeholder → `[ no cover ]` (matches across all specs).
10. External store link labels → `[ steam ]` / `[ gog ]` / `[ epic ]` (terse).
11. Rating display format → `95 / 100 (1234 votes)`.
12. Time-to-beat empty cell → `—` (em dash; project convention for "no data").

### Open-question decisions

1. **Phase 4 legacy `publisher` + `platforms` columns.** Defer drop. Add a
   one-line "DEPRECATED" comment in the model + a follow-up entry in
   `docs/orchestration/follow-ups.md`.
2. **`Game.cover_art` Active Storage attachment.** Option (c). Rename to
   `manual_cover_art`. Surface only on the show page edit form. Documented as
   "use this when IGDB has no cover image ID for the game."
3. **GOG / Epic IGDB category numbers.** Implementation agent verifies against
   IGDB external-game-enums docs at implementation time, stamps constants in
   `Igdb::GameMapper`, surfaces in the log if unstable.
4. **Rate-limiter scope.** Process-local for v1. If multi-Sidekiq- process
   deploys later show 429s, switch to Redis-backed limiter.
5. **`igdb_synced_at` precision.** Datetime (sub-day). Required so a manual
   re-sync at 14:00 protects against the next nightly enqueue.
6. **IGDB cover image caching for show / shelf pages.** No local cache. The IGDB
   CDN serves directly. Composite cover pipeline (Spec 02) does its own bytes
   cache.
7. **IGDB slug rename collision.** Mapper catches
   `ActiveRecord::RecordNotUnique`, falls back to NULL on `igdb_slug`, stamps
   `last_sync_error`. User resolves manually.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`). Touches:

- `db/migrate/`, `db/schema.rb`
- `app/models/`, `app/services/igdb/`, `app/jobs/`, `app/controllers/`,
  `app/views/games/`, `app/views/shared/`, `app/javascript/controllers/`
- `config/routes.rb`, `config/sidekiq.yml`
- `spec/**`

No `extras/cli/`, no `extras/website/`, no `docs/` (that is the docs- keeper's
separate dispatch after validation).

## Reviewer checkpoints (post-implementation)

1. `bundle exec rspec` — green.
2. `bundle exec rubocop` — green or no new violations.
3. `bundle exec brakeman -q` — green or no new findings.
4. `git grep 'tenant\|Tenant' app/models/game.rb app/services/igdb/` → zero
   matches (post-tenant-drop verification).
5. `git grep 'platforms_must_be_array_of_allowed_triples'` → zero matches.
6. Manual playbook §1-§10.
7. VCR cassettes deterministic across two consecutive runs.
8. Spec file count delta logged in `log.md`.
