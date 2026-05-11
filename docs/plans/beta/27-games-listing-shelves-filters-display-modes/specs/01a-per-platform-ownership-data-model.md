# 01a — Per-Platform Ownership Data Model

> Blocking sub-spec. Introduces `Platform` and `GamePlatformOwnership`, plus the
> IGDB sync service / job and the legacy `games.platform_owned_id` drop. Every
> other sub-spec in Phase 27 builds on this shape.

---

## Goal

Replace the single-valued `games.platform_owned_id` pointer with a join table
`game_platform_ownerships` that records each platform the user owns a game on.
Introduce a first-class `Platform` model whose canonical source is IGDB. This
unlocks the filter row's platform-aware semantics (`01b`), the per-platform
ownership editor (`01f`), and MCP / CLI plural ownership (`01g`).

---

## Files touched

Migrations:

- `db/migrate/<ts>_create_platforms.rb`
- `db/migrate/<ts>_create_game_platform_ownerships.rb`
- `db/migrate/<ts>_drop_platform_owned_id_from_games.rb`

Models:

- `app/models/platform.rb`
- `app/models/game_platform_ownership.rb`
- `app/models/game.rb` (associations, scope refresh)

Factories:

- `spec/factories/platforms.rb`
- `spec/factories/game_platform_ownerships.rb`
- `spec/factories/games.rb` (drop `platform_owned_id` references)

Services + jobs:

- `app/services/platforms/sync_from_igdb.rb`
- `app/jobs/platforms/sync_from_igdb_job.rb`

Seeds + cron:

- `db/seeds.rb` (idempotent platform seeds — PS5, Switch 2, Steam, GOG, Epic)
- `config/sidekiq_cron.yml` (weekly IGDB platform sync)

Tasks:

- `lib/tasks/platforms.rake` (`rake platforms:sync_from_igdb`)

Specs:

- `spec/models/platform_spec.rb`
- `spec/models/game_platform_ownership_spec.rb`
- `spec/models/game_spec.rb` (ownership integration)
- `spec/services/platforms/sync_from_igdb_spec.rb`
- `spec/jobs/platforms/sync_from_igdb_job_spec.rb`
- `spec/tasks/platforms_rake_spec.rb`

---

## Model + migration shape

### `platforms`

| Column             | Type     | Constraints                                         |
| ------------------ | -------- | --------------------------------------------------- |
| `id`               | bigint   | PK                                                  |
| `name`             | string   | NOT NULL                                            |
| `slug`             | string   | NOT NULL, unique index, FriendlyId                  |
| `igdb_platform_id` | integer  | unique index, nullable (manual seeds may pre-exist) |
| `abbreviation`     | string   | nullable (e.g. "PS5", "GOG")                        |
| `created_at`       | datetime | NOT NULL                                            |
| `updated_at`       | datetime | NOT NULL                                            |

`Platform` validations:

- `name` presence.
- `slug` presence + uniqueness.
- `igdb_platform_id` uniqueness when present.
- FriendlyId on `slug` (use `slugged` + `history` modules per project default).

`Platform` associations:

- `has_many :game_platform_ownerships, dependent: :restrict_with_error`
- `has_many :games, through: :game_platform_ownerships`

`Platform` scopes:

- `default_scope { order(:name) }` — alphabetical everywhere by default.

### `game_platform_ownerships`

| Column        | Type     | Constraints                                          |
| ------------- | -------- | ---------------------------------------------------- |
| `id`          | bigint   | PK                                                   |
| `game_id`     | bigint   | NOT NULL, FK, indexed                                |
| `platform_id` | bigint   | NOT NULL, FK, indexed                                |
| `acquired_at` | datetime | nullable                                             |
| `store`       | string   | nullable (free-text v1: "Steam", "PSN", "GOG", etc.) |
| `notes`       | text     | nullable                                             |
| `created_at`  | datetime | NOT NULL                                             |
| `updated_at`  | datetime | NOT NULL                                             |

Constraints:

- Unique composite index on `(game_id, platform_id)`.
- FK to `games(id)` ON DELETE CASCADE.
- FK to `platforms(id)` ON DELETE RESTRICT (cannot drop a platform with
  ownerships; the platform sync never deletes — it upserts).

`GamePlatformOwnership` validations:

- `game_id`, `platform_id` presence.
- Uniqueness of `platform_id` scoped to `game_id`.

`GamePlatformOwnership` associations:

- `belongs_to :game`
- `belongs_to :platform`

### `games` (associations + drop)

- `has_many :game_platform_ownerships, dependent: :destroy`
- `has_many :owned_platforms, through: :game_platform_ownerships, source: :platform`
- Drop column `games.platform_owned_id` (and its FK + index).
- Drop any model code that references the old column (associations, scopes,
  validations, serializers).

`Game` scopes added (consumed by `01b`):

- `scope :owned, -> { joins(:game_platform_ownerships).distinct }`
- `scope :not_owned, -> { left_joins(:game_platform_ownerships)  .where(game_platform_ownerships: { id: nil }) }`
- `scope :owned_on, ->(slug) { joins(game_platform_ownerships: :platform)  .where(platforms: { slug: slug }) }`

---

## Service / job decomposition

### `Platforms::SyncFromIgdb` (service)

Responsibilities:

- Fetch the IGDB `/platforms` endpoint via the existing IGDB client (assumes the
  client surface from Phase 4 IGDB integration).
- Upsert each result by `igdb_platform_id`:
  - Create if absent.
  - Update `name` and `abbreviation` if changed.
  - Leave `slug` unchanged unless the row has no slug yet (FriendlyId stable).
- Never delete platforms. Stale entries are kept (a game may still own a retired
  platform).
- Idempotent: running twice yields the same row set.

Returns a result struct `{ created:, updated:, total: }` (integers).

### `Platforms::SyncFromIgdbJob` (Sidekiq)

- Wraps `Platforms::SyncFromIgdb.call`.
- Cron entry in `config/sidekiq_cron.yml` — weekly (Sunday 03:00 UTC).
- Logs the result struct.

### Seed contribution

`db/seeds.rb` ensures these slugs exist by `find_or_create_by!`:

- `ps5`, `switch2`, `steam`, `gog`, `epic`.

(Names: "PlayStation 5", "Nintendo Switch 2", "Steam", "GOG", "Epic Games
Store". Abbreviations: "PS5", "Switch 2", "Steam", "GOG", "Epic".) The seed runs
idempotently; subsequent IGDB sync fills `igdb_platform_id`.

### Rake task

`rake platforms:sync_from_igdb` — invokes the job inline for manual refresh.

---

## Spec pyramid

### Model — `spec/models/platform_spec.rb`

Happy:

- valid factory.
- alphabetical default ordering.
- `friendly_id` resolves both slug and id.

Sad:

- missing `name` rejected.
- missing `slug` rejected.
- duplicate `slug` rejected.
- duplicate `igdb_platform_id` rejected (when present).

Edge:

- two platforms with `nil` `igdb_platform_id` coexist (unique index allows
  multiple NULLs).
- FriendlyId history retains the old slug after rename.

Flaw:

- attempting to delete a `Platform` with ownerships raises
  `ActiveRecord::RecordNotDestroyed`.

### Model — `spec/models/game_platform_ownership_spec.rb`

Happy:

- valid factory.
- `acquired_at`, `store`, `notes` nullable round-trip.

Sad:

- missing `game_id` rejected.
- missing `platform_id` rejected.
- duplicate `(game_id, platform_id)` rejected.

Edge:

- `acquired_at` accepts future timestamps (we don't gate on freshness here).
- cascade delete from `game` removes the ownership row.
- restrict from `platform` raises on platform deletion.

Flaw:

- `store` accepts long strings up to the column limit (verify no silent
  truncation).

### Model — `spec/models/game_spec.rb` (additions)

Happy:

- `game.owned_platforms` returns the joined platforms alphabetically.
- `Game.owned` includes only games with ≥1 ownership.
- `Game.not_owned` includes only games with 0 ownerships.
- `Game.owned_on('ps5')` matches games owned specifically on PS5.

Sad:

- no `platform_owned_id` column accessible after migration.

Edge:

- a game owned on PS5 and Steam appears once in `Game.owned` (DISTINCT).

Flaw:

- `Game.owned_on('nonexistent')` returns an empty relation, does not error.

### Service — `spec/services/platforms/sync_from_igdb_spec.rb`

Happy:

- new IGDB result creates a `Platform`.
- existing IGDB result updates name / abbreviation when changed.
- second run is idempotent (no-op).
- result struct returns correct counts.

Sad:

- IGDB client raises → service re-raises after logging.
- IGDB returns empty list → service returns zero counts, no destructive action.

Edge:

- IGDB result with same `igdb_platform_id` but updated `name` triggers update.
- pre-seeded slug (e.g., `ps5`) gets `igdb_platform_id` filled in on first match
  without changing the slug.

Flaw:

- a stale local platform (no IGDB match) is preserved, not deleted.

### Job — `spec/jobs/platforms/sync_from_igdb_job_spec.rb`

Happy:

- delegates to the service.
- enqueues on the default queue.

Sad:

- exceptions surface (Sidekiq retries).

Edge:

- cron entry validated structurally in `spec/config/sidekiq_cron_spec.rb`
  (existing pattern in the codebase).

### Rake — `spec/tasks/platforms_rake_spec.rb`

Happy:

- task loads.
- invokes the job.

---

## yes / no boundary

No new external boolean inputs in this sub-spec. Future MCP / CLI surfaces that
consume these models stay on yes/no per project rule.

---

## Friendly URL preservation

- `Platform` uses FriendlyId on `slug`.
- `Game#to_param` already returns slug; unchanged here.
- No new public routes in `01a`; routes for the ownership editor land in `01f`.

---

## Manual test recipe

1. `bin/rails db:migrate` — confirm three migrations apply cleanly.
2. `bin/rails db:seed` — verify five platform rows exist:
   ```
   bin/rails runner 'puts Platform.pluck(:slug).sort'
   # => ["epic", "gog", "ps5", "steam", "switch2"]
   ```
3. `rake platforms:sync_from_igdb` (with VCR cassette in dev or a recorded
   fixture) — verify counts in the job output.
4. From `bin/rails console`:
   ```ruby
   g = Game.create!(name: "Test Game")
   ps5 = Platform.find('ps5')
   g.game_platform_ownerships.create!(platform: ps5)
   g.owned_platforms.map(&:slug) # => ["ps5"]
   Game.owned.include?(g)        # => true
   Game.owned_on('ps5').include?(g) # => true
   Game.owned_on('switch2').include?(g) # => false
   ```
5. Attempt `ps5.destroy!` — expect `ActiveRecord::RecordNotDestroyed`.

---

## Cross-stack scope

| Surface    | In scope                                                |
| ---------- | ------------------------------------------------------- |
| Rails web  | Model + migration + service + job only (no UI yet here) |
| Rails MCP  | NO — MCP changes ship in `01g`                          |
| `pito` CLI | NO — CLI changes ship in `01g`                          |
| Website    | NO                                                      |

---

## Open questions

1. **Ship `acquired_at`, `store`, `notes` columns in v1, or defer?** Architect
   recommends ship in v1 — columns are nullable, cheap, and let the editor in
   `01f` cover the metadata story now rather than across two passes.
2. **`store` as free-text vs. enum?** v1 free-text per the master-agent lock.
   Enum can come later if the user wants a controlled vocabulary.
3. **Drop `games.platform_owned_id` outright vs. keep as derived "primary
   platform" pointer?** Architect leans drop. Re-introducing a primary pointer
   later is trivial; carrying dead state isn't.
4. **`Platform` deletion policy.** v1 restrict (preserves history). Could relax
   to `dependent: :nullify` if the user wants soft-removal later, but that
   requires the ownership FK to be nullable — out of scope.
5. **IGDB platform sync error budget.** First run may pull >100 platforms.
   Confirm the IGDB client surface from Phase 4 supports pagination; if not, add
   a TODO in the service for follow-up.
