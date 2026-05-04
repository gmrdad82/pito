# Phase 2 — Postgres Migration

> **Goal:** Replace MySQL 8 with Postgres 17 (using the `pgvector/pgvector:pg17`
> Docker image) as Pito's relational database. Preserve all Alpha-era specs as
> the regression baseline. Install the `pgvector` extension at migration time so
> Phase 10 has zero infrastructure work later.

**Depends on:** Phase 1 (dev KB exists; this phase's `plan.md` and `log.md` live
in the new home).

**Unblocks:** Phase 3 (User/Tenant models with `jsonb` and `citext` types),
Phase 10 (vector storage co-located with relational data).

---

## Why Phase 2 is now

Switching the relational store touches every model and every spec. Doing it
before any new schema work — User, Tenant, ApiToken, Google identities, YouTube
tokens, video metadata refactors, embeddings — is dramatically cheaper than
doing it after. Pito at the start of Beta has **only seed data** in the dev
environment; there is no real user data to preserve. This is the cheapest moment
the migration will ever happen.

Postgres is also a hard requirement for `pgvector`. Phase 10 stores vectors in
pgvector columns for SQL-native related-content joins (Meilisearch alone can't
join with relational predicates). Switching now means Phase 10 needs only a
`CREATE EXTENSION` and a column.

The Alpha codebase is prior art (per `beta.md`), but the existing test suite is
the single most useful regression check available — every Alpha spec must pass
against Postgres before this phase is considered done. Specs that don't pass are
either rewritten as adapter-agnostic or explicitly waived in `challenges.md`.

---

## In scope

### Service swap

- Replace MySQL 8 in `docker-compose.yml` with `pgvector/pgvector:pg17`. Use a
  fresh named volume so the old MySQL data isn't accidentally mounted.
- Update Gemfile: remove `mysql2`, add `pg`. `bundle install`.
- Update `config/database.yml`: `postgresql` adapter, encoding `unicode`,
  prepared statements, pool size matching the maximum of (Web Puma threads, MCP
  Puma threads, Sidekiq concurrency) so neither Puma starves the other.
- Update Rails credentials (development + test) with Postgres user, password,
  database name. Production credentials are set during Phase 16.
- Update `.env.example`: replace `MYSQL_*` keys with `DATABASE_URL` (or discrete
  `POSTGRES_*` keys, pick one and document).

### Migrations

- Re-run all Alpha migrations against Postgres on a fresh DB. Identify and fix
  any MySQL-specific patterns surfaced during the run (column types, default
  values, `enum` declarations, raw SQL with backticks).
- Add a new migration that calls `enable_extension :pgcrypto` (for
  `gen_random_uuid()` if anything wants it later) and
  `enable_extension :vector`. Both extensions are installed but not yet used —
  Phase 10 adds the first vector column.
- Verify `db/schema.rb` (or `db/structure.sql` if the project uses SQL schema
  format) generates cleanly under Postgres.

### Application updates

- Audit the codebase for MySQL-specific behaviors and fix them:
  - Case-insensitive uniqueness (MySQL's default `utf8mb4_general_ci`
    collation). Postgres is case-sensitive by default. Use `LOWER()` in unique
    indexes or `citext` columns where case-insensitivity is required.
  - JSON columns: MySQL has `json`; Postgres has `json` and `jsonb`. Prefer
    `jsonb` for new columns; verify any existing `json` column maps acceptably.
  - Boolean columns: MySQL stores as `tinyint(1)`; Postgres as `boolean`. Schema
    migration is automatic, but raw SQL using `0`/`1` literals must use
    `false`/`true`.
  - Auto-increment vs sequences: handled transparently by Rails; verify
    `INSERT ... RETURNING id` patterns work where they appear.
  - `group_by_*` (Chartkick + Groupdate): timezone handling differs; verify
    dashboard charts that aggregate by day/week/month render identically.
  - Active Record Encryption: encrypted blobs in `text` columns are portable;
    verify decryption works against re-seeded records.
- Verify Meilisearch indexer still works (it queries the relational DB during
  reindex).
- Verify Sidekiq jobs that read DB still work (background queue + scheduled
  syncs from Alpha).
- Verify both Puma processes (Web Puma and MCP Puma) start cleanly against
  Postgres. They share the same database config but each maintains its own
  connection pool.

### Tooling and scripts

- Update `bin/setup` to start the Postgres container, run migrations, run seeds.
- Update `bin/dev` (or the Foreman-equivalent script) to start Postgres
  alongside Redis, Meilisearch, Web Puma, MCP Puma, Sidekiq, and the Tailwind
  watcher.
- Update any `bin/db:*` helpers or Rake tasks that assumed MySQL.

### Seed data sanity

- Run full seeds against Postgres; confirm record counts match the Alpha-era
  expectation.
- Spot-check a handful of records via Rails console for byte-equivalence on
  titles, descriptions, encrypted columns.
- Add 5-10 edge-case records during this phase: very long descriptions, unicode
  in titles, null fields where allowed, extreme date ranges. These surface
  MySQL→Postgres edge cases not covered by typical seeds.

### Documentation

- Update `pito/docs/architecture.md`: Postgres section, pgvector mentioned
  (installed, unused), `enable_extension` migration noted, dual-Puma connection
  pool sizing.
- Update `pito/docs/setup.md`: Postgres install via Docker, database creation,
  migration commands, the connection pool considerations for the dual-Puma
  setup.
- Update `.env.example` with the new keys.

### Out of scope

- Adding any vector columns or indexes (Phase 10).
- Schema changes beyond what's needed for the migration. Auth schema is Phase 3.
- Production deployment and production database setup (Phase 16).
- Multi-environment Postgres beyond `development` and `test`. Production
  credentials and config land in Phase 16.

---

## Plan checklist

### Pre-migration audit

- [x] Grep the codebase for MySQL-specific patterns: `mysql2`, `enum`
      declarations using MySQL syntax, MySQL-only data types, raw SQL with
      backticks, `LIMIT` in `update_all`, FULLTEXT indexes (Pito uses
      Meilisearch, but verify no leftovers) (41 findings; three additional
      `CAST(... AS SIGNED)` surfaced mid-flight)
- [x] Document findings in `challenges.md` — these are the items to verify
      post-migration
- [x] Identify any models with case-insensitive uniqueness validations relying
      on MySQL collation behavior
- [x] Identify any `enum` columns and confirm Rails-level enum definitions don't
      depend on MySQL-specific behavior

### Docker + Gemfile

- [x] Update `docker-compose.yml`: replace MySQL service with
      `pgvector/pgvector:pg17`
- [x] Use a new volume name so the old MySQL volume isn't accidentally mounted
      (`postgres_data`)
- [x] Update Gemfile: remove `gem 'mysql2'`, add `gem 'pg'`
- [x] `bundle install` — verify no incompatible transitive dependencies
- [x] Update `config/database.yml`: adapter, host, port, encoding `unicode`,
      pool size matching max(Web Puma threads, MCP Puma threads, Sidekiq
      concurrency)
- [x] Add a new migration enabling `pgcrypto` and `vector` extensions (also
      `citext`, per additions.md)
- [x] `bin/rails db:create db:migrate` against fresh Postgres — clean run
- [x] `bin/rails db:seed` — clean run
- [x] `bin/rails db:schema:dump` (or `db:structure:dump`) produces a clean
      Postgres schema

### Rails credentials

- [x] `rails credentials:edit --environment development` — Postgres user,
      password, database (user-performed; verbatim copy from `:mysql` block)
- [x] `rails credentials:edit --environment test` — same
- [x] Verify Active Record Encryption keys still in place (no change expected)
- [x] Document the credential keys in `pito/docs/setup.md`

### Application updates

- [x] Fix any spec or model code surfaced by the audit
- [x] Verify Meilisearch indexer reindexes against the new DB
- [x] Verify Sidekiq jobs run end-to-end against Postgres
- [~] Verify Chartkick + Groupdate-driven dashboards render correctly (timezone
  behavior is the most likely surprise) (UTC pinned in `config/application.rb`;
  specs green; visual spot-check awaiting user validation per playbook
  2026-05-01-postgres-migration.md)
- [~] Verify both Puma processes (Web Puma at `app.pitomd.com`, MCP Puma at
  `mcp.pitomd.com`) start cleanly and serve requests against Postgres (per-Puma
  DB smoke specs green; live tunnel verification awaiting user validation per
  playbook 2026-05-01-postgres-migration.md)
- [x] Verify the Alpha-era MCP tools (whatever they are at the start of Beta)
      still execute against the new DB

### Seed data sanity

- [x] Run full seeds; confirm record counts match Alpha expectations
- [~] Spot-check a handful of records in Rails console (awaiting user validation
  per playbook 2026-05-01-postgres-migration.md)
- [x] Add 5-10 edge-case records: long descriptions, unicode titles, null
      fields, extreme dates
- [x] Confirm Meilisearch reindex completes against the seeded DB

### Specs

- [x] `bundle exec rspec` — all existing specs green against Postgres (423
      examples passing)
- [x] If any spec relies on MySQL-specific behavior, rewrite as adapter-agnostic
      OR add explicit Postgres assertion (with a comment noting the original
      MySQL behavior)
- [x] Add a new spec asserting the `vector` extension is enabled
      (`ActiveRecord::Base.connection.extension_enabled?('vector')`) so Phase 10
      can rely on it
- [x] Add a new spec asserting the `pgcrypto` extension is enabled (citext also
      asserted)
- [x] Both Puma processes have at least one request spec each that confirms DB
      connectivity (Web Puma: an existing controller spec; MCP Puma: an MCP tool
      spec)

### Documentation

- [x] `pito/docs/architecture.md`: Postgres section added, pgvector noted as
      installed-unused, dual-Puma connection pool sizing documented
- [x] `pito/docs/setup.md`: Postgres install via Docker, database creation,
      migration commands, connection pool considerations
- [~] `.env.example` updated; `MYSQL_*` keys removed (Postgres keys added;
  `MYSQL_*` retained intentionally until post-verification cleanup pass per spec
  section 4b)
- [x] `bin/setup` updated to start Postgres container and run setup
- [x] `bin/dev` updated to start Postgres alongside the rest of the stack

### Validation

- [x] All Alpha specs pass (423 examples)
- [ ] Manual smoke test: web (`app.pitomd.com`) renders all major pages —
      channels, videos, dashboard, search, settings (awaiting user validation
      per playbook 2026-05-01-postgres-migration.md)
- [ ] Manual smoke test: MCP HTTP transport (`mcp.pitomd.com`) responds to a
      tool call (awaiting user validation per playbook
      2026-05-01-postgres-migration.md)
- [ ] Sidekiq web at `/sidekiq` (or wherever it's mounted) loads and shows
      healthy queues (awaiting user validation per playbook
      2026-05-01-postgres-migration.md)
- [x] Brakeman clean
- [x] bundler-audit clean (`pg` gem version verified)
- [ ] Dependabot alerts reviewed after `pg` introduction (awaiting user
      validation per playbook 2026-05-01-postgres-migration.md)
- [x] `pito/docs/design.md` reviewed (no UI changes expected)

---

## Specs requirements

- All Alpha specs pass with zero modifications, OR every modification is
  justified in `challenges.md`.
- New spec: `vector` extension is enabled.
- New spec: `pgcrypto` extension is enabled.
- New spec or smoke check: both Puma processes can establish a DB connection
  (Web Puma via any controller spec; MCP Puma via any MCP tool spec).
- Any MySQL-specific spec patterns rewritten as adapter-agnostic, with a note in
  the spec explaining what changed and why.

## Security requirements

- Postgres credentials live in Rails credentials, never literal in
  `database.yml` or `.env`.
- Use the official `pgvector/pgvector:pg17` image. Verify the image digest if
  reproducible builds matter to the user.
- Brakeman: no new warnings.
- bundler-audit: clean. Especially confirm the `pg` gem version has no open
  advisories.
- Dependabot: review and resolve any new alerts after `pg` is introduced.
- `pito/docs/design.md`: no changes expected (visual UI unchanged).

## Manual testing checklist

The user runs through this before commit:

1. From a clean state, `bin/setup` — Postgres container comes up, migrations
   run, seeds populate without errors
2. `bin/dev` — full stack starts (Postgres, Redis, Meilisearch, Web Puma, MCP
   Puma, Sidekiq, Tailwind watcher); no errors in any process log
3. Visit `app.pitomd.com/` (dashboard), `/channels`, `/videos`, `/saved_views`,
   `/settings` — all render correctly
4. Search bar: typing returns Meilisearch results
5. Create / edit / delete a channel via the web UI; verify in Rails console that
   the record was written to Postgres
6. Bulk-delete a few videos; confirm the BulkDeleteJob (or whatever Alpha named
   it) completes via Sidekiq
7. From Claude desktop or mobile, connect to `mcp.pitomd.com` and call any read
   tool — returns expected data from Postgres
8. `bundle exec rspec` — green
9. `psql` into the dev database; run `\dx` and verify `vector` and `pgcrypto`
   are listed as installed extensions
10. Check `db/schema.rb` (or `db/structure.sql`); confirm it's clean Postgres
    syntax

---

## Challenges to anticipate

- **Case-insensitive uniqueness.** MySQL's default collation hides this;
  Postgres won't. Audit every `validates :foo, uniqueness: true` and any unique
  index. For Pito, slugs and emails are the obvious candidates. Use `citext` for
  emails and slugs; use `LOWER()` indexes or normalize-on-write for other cases.
- **JSONB vs JSON.** Use `jsonb` for any new columns (better indexing, faster
  queries). Existing `json` columns from Alpha can stay as-is during the
  migration; convert opportunistically.
- **Connection pool sizing under dual Puma.** Each Puma process has its own
  pool. If Web Puma runs 5 threads × 2 workers = 10 threads, MCP Puma runs 5 × 2
  = 10, and Sidekiq runs 10 concurrent, the total DB connections under load can
  be 30 plus background processes. Size the Postgres `max_connections`
  accordingly (development is usually fine; production sizing is a Phase 16
  concern).
- **Timezone handling in Groupdate.** `group_by_day` and friends respect the
  database's timezone defaults. Postgres stores timestamps as UTC by default
  with `timestamptz`; ensure the Rails app config matches (`config.time_zone`
  and `config.active_record.default_timezone`). Spot-check at least one chart
  that uses `group_by_*` after migration.
- **VCR cassettes recorded against MySQL behavior.** If any cassette captured
  DB-specific responses, it won't matter for HTTP-level cassettes — but if the
  codebase has any non-HTTP fixtures coupled to MySQL behavior, regenerate them.
- **`enable_extension :vector` requires the right Postgres image.** The standard
  `postgres:17` image doesn't ship with pgvector; the `pgvector/pgvector:pg17`
  image does. Migration will fail clearly if the wrong image is used. Document
  the exact image tag in `setup.md`.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. There is no real user data to preserve — only seeds. (Confirmed at planning
   time; re-verify before destructive `bin/rails db:reset`.)
2. No MySQL-specific stored procedures, triggers, or views exist outside
   standard Rails migrations. If they do, that becomes a sub-task of this phase.
3. Cloudflare tunnels and DNS for `app.pitomd.com` and `mcp.pitomd.com` continue
   pointing at the laptop. (Production deployment is Phase 16; nothing here
   touches it.)
4. The user is OK with `bin/setup` requiring a fresh database — no data
   preservation step in this phase.
5. The image tag `pgvector/pgvector:pg17` is acceptable. (Alternative: standard
   `postgres:17` plus separate `pgvector` install. Not recommended; the bundled
   image is the path of least friction.)
