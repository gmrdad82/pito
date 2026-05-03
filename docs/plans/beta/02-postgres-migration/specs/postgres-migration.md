# Spec — Phase 2: Postgres Migration

> **Phase:** 02 — Postgres Migration **Lane:** Lane 1 only (Rails app,
> infrastructure) **Implementer:** `pito-rails` subagent on `step-postgres` git
> worktree branch **Source plan:**
> `pito-dev-kb/plans/beta/02-postgres-migration/02-plan.md` **Master plan:**
> `pito-dev-kb/plans/beta/beta.md`

---

## 1. Goal

Replace MySQL 8 with Postgres 17 (`pgvector/pgvector:pg17` image) as Pito's
relational store, install the `pgcrypto`, `vector`, and `citext` extensions in a
single migration, fix any MySQL-specific application code surfaced by the swap,
re-seed against the new database, update tooling and documentation, and prove
the migration with a green spec suite plus a manual smoke pass across both Puma
processes. After this spec lands, Phase 3 (auth) can immediately use `citext`
for emails and slugs and Phase 10 (embeddings) can immediately add vector
columns — no further extension migrations.

---

## 2. Scope deviations from `02-plan.md`

The architect has decided the following adjustments to the plan as written. Each
is committed scope for this spec:

- **`citext` is bundled into the Phase 2 extensions migration.** `02-plan.md`
  enables only `pgcrypto` and `vector`. The Phase 3 plan calls for a separate
  `enable_extension :citext` migration. We move it forward into the same
  migration here to avoid a second extensions-only migration two phases later.
  Phase 3's spec will simply use `citext` columns; it will no longer ship the
  extension migration itself.
- **Lane 2 (a/b) is explicitly out of scope.** Phase 2 is pure infrastructure.
  No `pito-sh` work, no MCP-tool work beyond restarting MCP Puma and confirming
  a tool call still resolves. Per ADR 0002, Lane 2 fans out from Lane 1 only
  when a feature has a Lane 1 surface to mirror; an infra swap has none.
- **No data preservation step.** Alpha data is prototype seed material per
  `beta.md`. The migration drops the MySQL container and its volume cleanly
  (using the safe-teardown rubric in section 5) and re-seeds from scratch
  against Postgres. No dump-and-load script is part of this phase.
- **One atomic spec covers the entire phase.** Service swap, Gemfile,
  database.yml, extensions migration, application audit fixes, seeds, scripts,
  docs, and the manual test recipe are all delivered together on a single
  `step-postgres` branch. There is no sub-PR split.
- **Pool sizing rule is fixed.** `database.yml` `pool` value is
  `max(Web Puma threads, MCP Puma threads, Sidekiq concurrency)`. With current
  defaults — Web Puma 3 threads (`config/puma.rb`), MCP Puma 5 threads
  (`config/puma_mcp.rb`), Sidekiq concurrency 5 (`config/sidekiq.yml`) — the
  pool is 5. The rule is documented in `database.yml` as a comment so future
  tuning lands correctly.

---

## 3. Files touched

| File                                                                         | Change                                                            | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pito/docker-compose.yml`                                                    | edit                                                              | Replace `mysql` service with `postgres` using `pgvector/pgvector:pg17`. Drop `./docker/mysql/init.sql` mount. Rename volume `mysql_data` → `postgres_data`. Update healthcheck to `pg_isready`. The service env block sets `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` — values must match the `:postgres` credentials block (which itself was copied verbatim from `:mysql`) so the container is reachable with the same auth as MySQL was. Sensible defaults inline (e.g., `POSTGRES_USER: ${POSTGRES_USER:-pito}`) match the existing local development MySQL values. |
| `pito/docker/mysql/init.sql`                                                 | delete                                                            | MySQL bootstrap user/grant script — no Postgres equivalent needed (Rails creates the DB; auth via env).                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `pito/docker/mysql/`                                                         | delete (rename)                                                   | Remove empty MySQL docker dir; if a Postgres equivalent is introduced, place under `pito/docker/postgres/` (none required for development at this phase).                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `pito/Gemfile`                                                               | edit                                                              | Remove `gem "mysql2", "~> 0.5"`. Add `gem "pg", "~> 1.5"`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `pito/Gemfile.lock`                                                          | regenerate                                                        | Result of `bundle install` after Gemfile change. Commit.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `pito/config/database.yml`                                                   | replace                                                           | Postgres adapter, `unicode` encoding, host/port via env, pool sized per the rule above, credentials via `Rails.application.credentials.dig(:postgres, …)` — exact key parity with the existing `Rails.application.credentials.dig(:mysql, …)` calls (same shape, same keys: `:username`, `:password`, `:database`). Drop `collation`, `charset`, `variables.sql_mode`.                                                                                                                                                                                                           |
| `pito/config/application.rb`                                                 | edit                                                              | Set `config.time_zone = "UTC"` and `config.active_record.default_timezone = :utc` explicitly so Groupdate aggregates render predictably under `timestamptz`. Document the choice in `architecture.md`.                                                                                                                                                                                                                                                                                                                                                                           |
| `pito/db/migrate/<TS>_enable_postgres_extensions.rb`                         | create                                                            | Single migration that calls `enable_extension :pgcrypto`, `enable_extension :citext`, `enable_extension :vector`. Idempotent via `enable_extension`.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `pito/db/schema.rb`                                                          | regenerate                                                        | Re-dumped after migrations run against Postgres; will include the three `enable_extension` lines.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `pito/bin/setup`                                                             | edit                                                              | Wait for `postgres` health (replace `mysql_healthy` check with `postgres_healthy`). Update credential bootstrap message to show the `postgres:` block instead of `mysql:`.                                                                                                                                                                                                                                                                                                                                                                                                       |
| `pito/bin/dev`                                                               | edit                                                              | Update `SERVICES` list from `mysql redis` to `postgres redis meilisearch` (Meilisearch was already started by `docker compose up -d` but not gated on health; gating it here matches the stack the user actually runs).                                                                                                                                                                                                                                                                                                                                                          |
| `pito/.env.example`                                                          | edit                                                              | Add `POSTGRES_HOST` (default `127.0.0.1`) and `POSTGRES_PORT` (default `5433` to avoid collisions with a host Postgres on 5432). Do NOT remove `MYSQL_HOST` / `MYSQL_PORT` in this pass — they are removed in the post-cutover cleanup step (section 4b). Optionally also document `DATABASE_URL` as an override.                                                                                                                                                                                                                                                                |
| `pito/.env.development`                                                      | edit                                                              | Add `POSTGRES_*` keys alongside `MYSQL_*`; same port choice. `MYSQL_*` removed in cleanup.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `pito/.env.test`                                                             | edit                                                              | Same.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `pito/Procfile.dev`                                                          | edit (if needed)                                                  | No change expected — Procfile already declares `web` (Web Puma) and `mcp` (MCP Puma) and `worker`. Verify both come up cleanly post-migration; only edit if a process name needs adjusting.                                                                                                                                                                                                                                                                                                                                                                                      |
| `pito/config/credentials/development.yml.enc`                                | edit (via `bin/rails credentials:edit --environment development`) | Add a sibling `:postgres` block alongside the existing `:mysql` block. Keys: `username`, `password`, `database`. **Values copied verbatim from the existing `:mysql` block** — minimize surprise; one credential set for one project. Do NOT delete the `:mysql` block in this pass; it stays for rollback until cutover is verified, then is removed in the cleanup step (section 4b). **Done by user, not committed by Claude** — credentials require the master key.                                                                                                          |
| `pito/config/credentials/test.yml.enc`                                       | edit (via `bin/rails credentials:edit --environment test`)        | Same protocol as development: add `:postgres` block with values copied verbatim from the existing `:mysql` block; leave `:mysql` in place until cleanup.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `pito/config/credentials.yml.enc`                                            | no change                                                         | Production credentials (the shared file) are out of scope for Phase 2 — handled in Phase 16.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `pito/docs/architecture.md`                                                  | create or edit                                                    | Add Postgres section: image tag, extensions installed and their purpose, dual-Puma connection-pool sizing rule, UTC timezone choice. (File may not exist yet — Phase 1 deliverable. If absent, create with this section as the seed.)                                                                                                                                                                                                                                                                                                                                            |
| `pito/docs/setup.md`                                                         | create or edit                                                    | Add Postgres install via Docker, the credentials block to paste, `bin/setup` flow, manual `psql \dx` confirmation. (Same Phase 1 caveat.)                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `pito/docs/design.md`                                                        | no change                                                         | Visual UI is unchanged. Cited for completeness; gate item only.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `pito/spec/system/extensions_spec.rb` (or `pito/spec/db/extensions_spec.rb`) | create                                                            | Asserts `ActiveRecord::Base.connection.extension_enabled?('pgcrypto')`, `'citext'`, `'vector'` are all true.                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `pito/spec/requests/web_puma_db_smoke_spec.rb`                               | create or reuse                                                   | Any existing Web Puma controller spec that hits the DB satisfies this; add a tiny dedicated spec only if no existing controller spec already exercises a DB read.                                                                                                                                                                                                                                                                                                                                                                                                                |
| `pito/spec/mcp/mcp_puma_db_smoke_spec.rb`                                    | create or reuse                                                   | Same — any existing MCP tool spec that reads the DB counts; add a dedicated assertion only if missing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `pito/spec/**/*`                                                             | edit (as surfaced)                                                | Any spec that fails under Postgres because of MySQL-specific assumptions (collation, raw SQL, group*by*\* timezone) gets rewritten as adapter-agnostic. Each rewrite gets a one-line comment naming the original MySQL assumption and the Postgres replacement. List of touched specs is recorded in the phase `log.md` as work proceeds.                                                                                                                                                                                                                                        |
| `pito/db/seeds.rb` and `pito/db/seeds/*`                                     | edit (as surfaced)                                                | If any seed relies on MySQL-permissive behavior (e.g., implicit type coercion, case-insensitive uniqueness via collation), tighten. Add 5–10 edge-case records as called out by the plan: long unicode descriptions, null optional fields, extreme date ranges.                                                                                                                                                                                                                                                                                                                  |
| `pito/CLAUDE.md`                                                             | edit                                                              | Tech-stack line currently says "MySQL 8 (Docker)". Update to "Postgres 17 + pgvector/pgcrypto/citext (Docker)". One-line edit.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `pito-dev-kb/plans/beta/02-postgres-migration/02-plan.md`                    | edit                                                              | Tick checkboxes as they complete. Move the `enable_extension :citext` checkbox up from Phase 3's plan (cross-link in `additions.md`).                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `pito-dev-kb/plans/beta/02-postgres-migration/log.md`                        | append                                                            | Session entries per `beta.md` quality gates.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `pito-dev-kb/plans/beta/02-postgres-migration/additions.md`                  | append                                                            | Note the `citext` bundling addition with rationale (mirror of section 2 of this spec).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `pito-dev-kb/plans/beta/03-auth-foundation/03-plan.md`                       | edit (small)                                                      | Add a note that `citext` is already enabled by Phase 2; remove the duplicate `enable_extension :citext` checkbox from the Phase 3 challenges list.                                                                                                                                                                                                                                                                                                                                                                                                                               |

The spec stays inside the `pito` repo for code; documentation tracking lives in
`pito-dev-kb`. No edits to `pito-sh`, `pito-website`, or any unrelated
subproject.

---

## 4. Implementation steps

Run top-to-bottom. Each step has an action, expected outcome, and a rollback
note. The implementer halts and pings the architect on any unexpected failure.

1. **Ensure clean working tree.**
   - Action: `cd pito && git status` should be clean. Create worktree branch
     `step-postgres`.
   - Expected: branch exists, tree clean.
   - Rollback: `git worktree remove`.

2. **Run the safe-MySQL-teardown enumeration (do not destroy yet).**
   - Action: enumerate exact container, volume, and network names per section 5.
     Print the list and STOP. Wait for architect confirmation before any
     destructive action.
   - Expected: list printed, no Docker resources removed.
   - Rollback: nothing to undo.

3. **Drain Sidekiq and pause the reindex cron.**
   - Action: stop new work from entering the DB-touching queues before MySQL
     teardown:
     - Drain queues `bulk_deletion` and `search` (used by `BulkDeleteJob`,
       `SearchIndexJob`, `SearchRemoveJob`, `ReindexAllJob`). Wait until each is
       empty.
     - Pause the `reindex_search` cron entry in `config/sidekiq_cron.yml`
       (`0 4 * * *`) for the duration of the cutover.
     - The `Searchable` concern (`app/models/concerns/searchable.rb:32,36`)
       auto-enqueues a Meilisearch update on every save/destroy — confirm no app
       processes are running that could enqueue mid-cutover.
   - Expected: Sidekiq Web shows zero in-flight jobs across `bulk_deletion` and
     `search`; the `reindex_search` cron is paused.
   - Rollback: unpause the cron; queues resume naturally on next worker boot.

4. **After confirmation, tear down MySQL safely.**
   - Action:
     `docker compose stop mysql && docker compose rm -f mysql && docker volume rm <project>_mysql_data`.
     Use exactly the names produced in step 2. Never `prune`.
   - Expected: MySQL container and volume gone; Redis and Meilisearch untouched.
   - Rollback: re-create from `docker-compose.yml` is not possible after volume
     removal — confirmed acceptable per architect decision (no data
     preservation).

5. **Edit `docker-compose.yml`.**
   - Action: replace the `mysql` service block with a `postgres` service using
     `pgvector/pgvector:pg17`. Map host port `5433` → container `5432` (avoid
     5432 collisions). Set the env block so `POSTGRES_USER`,
     `POSTGRES_PASSWORD`, `POSTGRES_DB` match the values currently in the
     `:mysql` credentials block (which become the `:postgres` block in step 11).
     Use `${POSTGRES_USER:-<verbatim>}`-style defaults so the values come from
     `.env.development` first and fall back to the verbatim copy of the existing
     MySQL values. Mount a fresh named volume
     `postgres_data:/var/lib/postgresql/data`. Healthcheck:
     `pg_isready -U "$POSTGRES_USER"`. Drop the `init.sql` mount.
   - Expected: `docker compose config` parses cleanly;
     `docker compose up -d postgres` starts and reaches healthy. The container
     is reachable using the same username/password/database that MySQL was —
     minimize surprise.
   - Rollback: `git restore docker-compose.yml`.

6. **Delete `docker/mysql/init.sql` and the now-empty `docker/mysql/`
   directory.**
   - Action: `git rm pito/docker/mysql/init.sql && rmdir pito/docker/mysql`.
   - Expected: directory gone.
   - Rollback: `git restore`.

7. **Edit `Gemfile`: remove `mysql2`, add `pg`.**
   - Action: replace `gem "mysql2", "~> 0.5"` with `gem "pg", "~> 1.5"`.
   - Expected: `bundle install` resolves cleanly; `Gemfile.lock` updated.
   - Rollback: `git restore Gemfile Gemfile.lock`.

8. **Replace `config/database.yml`.**
   - Action: write Postgres-flavoured `database.yml`. `adapter: postgresql`,
     `encoding: unicode`, `host` from `POSTGRES_HOST` env, `port` from
     `POSTGRES_PORT` env,
     `pool: <%= [ENV.fetch("RAILS_MAX_THREADS", 5).to_i, ENV.fetch("MCP_THREADS", 5).to_i, ENV.fetch("SIDEKIQ_CONCURRENCY", 5).to_i].max %>`,
     credentials via `Rails.application.credentials.dig(:postgres, :username)`,
     `dig(:postgres, :password)`, `dig(:postgres, :database)` — i.e.,
     one-for-one key-rename of the existing `dig(:mysql, …)` calls. (Per-env
     credential files already scope to development vs. test; no extra env-key
     nesting under `:postgres`.) Document the pool rule as a comment.
   - Expected:
     `bin/rails runner 'puts ActiveRecord::Base.connection.adapter_name'` prints
     `PostgreSQL`.
   - Rollback: `git restore config/database.yml`.

9. **Edit `config/application.rb` for timezone defaults.**
   - Action: set `config.time_zone = "UTC"` and
     `config.active_record.default_timezone = :utc`. (If already implicit, make
     it explicit so Groupdate's behaviour is documented.)
   - Expected: app boots, `Time.zone.name == "UTC"`.
   - Rollback: `git restore config/application.rb`.

10. **Update `.env.example`, `.env.development`, `.env.test`.**

- Action: ADD `POSTGRES_HOST=127.0.0.1` and `POSTGRES_PORT=5433` (and any
  `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` defaults that mirror the
  existing MySQL values verbatim, for the docker-compose `${VAR:-default}`
  fallbacks). Do NOT remove the existing `MYSQL_*` keys in this pass — they
  remain in place until the post-cutover cleanup step (section 4b) so a rollback
  during the migration window stays one-line. Mention `DATABASE_URL` as an
  optional override in `.env.example` (commented out).
- Expected: each file lists `POSTGRES_*` keys alongside the still-present
  `MYSQL_*` keys.
- Rollback: `git restore .env.*`.

11. **User edits Rails credentials — parity with the existing MySQL block.**
    - Goal: handle Postgres credentials exactly like MySQL is handled today.
      Same files, same shape, same values. Minimize surprise; one credential set
      for one project. Production credentials are out of scope (Phase 16).
    - Protocol (development):
      - Open development credentials:
        `bin/rails credentials:edit --environment development`.
      - Locate the existing `:mysql` block. Capture its values verbatim
        (`username`, `password`, `database`).
      - Add a sibling `:postgres` block with the same three keys (`username`,
        `password`, `database`). Copy values verbatim — no changes, no renames,
        no environment-specific tweaks.
      - Save and close. The encrypted file
        `config/credentials/development.yml.enc` updates in place.
    - Protocol (test): repeat with
      `bin/rails credentials:edit --environment test` against
      `config/credentials/test.yml.enc`. Same verbatim copy from the existing
      `:mysql` block.
    - Shape (each per-environment file ends up with sibling top-level keys):
      ```yaml
      mysql:
        username: <existing>
        password: <existing>
        database: <existing>
      postgres:
        username: <same as mysql.username>
        password: <same as mysql.password>
        database: <same as mysql.database>
      ```
      `database.yml` reads via
      `Rails.application.credentials.dig(:postgres, :username)` etc. — exact key
      parity with the previous `dig(:mysql, :username)` calls.
    - **Do NOT delete the `:mysql` block in this step.** It stays in both
      per-environment credential files until the post-cutover cleanup (section
      4b). Rationale: easy one-line rollback during the migration window.
    - Implementer does NOT run `credentials:edit` directly (master key
      required); the user performs the edit.
    - Expected:
      `bin/rails runner 'p Rails.application.credentials.dig(:postgres, :username)'`
      (in `RAILS_ENV=development`) prints the same value
      `dig(:mysql, :username)` previously returned. Same for `:password` and
      `:database`. Same again under `RAILS_ENV=test`.
    - Rollback: user re-edits credentials, removes the `:postgres` block. The
      untouched `:mysql` block keeps the legacy code path working.

12. **Generate the extensions migration.**
    - Action: `bin/rails g migration EnablePostgresExtensions`. In the file,
      write:
      ```ruby
      class EnablePostgresExtensions < ActiveRecord::Migration[8.1]
        def change
          enable_extension "pgcrypto"
          enable_extension "citext"
          enable_extension "vector"
        end
      end
      ```
    - Expected: file exists under
      `db/migrate/<TS>_enable_postgres_extensions.rb`.
    - Rollback: `git rm` the migration file.

13. **Convert `t.json` to `t.jsonb` in existing migrations.**
    - Action: edit the four `t.json` columns identified by the audit so
      re-running migrations against Postgres produces `jsonb` from the start:
      - `db/migrate/20260426150307_create_videos.rb:11` — `t.json :tags` →
        `t.jsonb :tags`.
      - `db/migrate/20260426222642_create_bulk_operations.rb:6-8` —
        `parameters`, `target_video_ids`, `dry_run_preview` all from `t.json` →
        `t.jsonb`.
    - Per the no-data-preservation decision, editing migration history in place
      is acceptable here (fresh DB, no rollback chain to honour). `db/schema.rb`
      will follow on the next dump (step 14).
    - Expected: grep for `t.json ` in `db/migrate/` returns no hits; `t.jsonb`
      hits are the four above.
    - Rollback:
      `git restore db/migrate/20260426150307_create_videos.rb db/migrate/20260426222642_create_bulk_operations.rb`.

14. **Create + migrate + seed against fresh Postgres.**
    - Action: `bin/rails db:create db:migrate db:seed`.
    - Expected: clean run. `db/schema.rb` regenerates with
      `enable_extension "pgcrypto"`, `"citext"`, `"vector"` lines and `jsonb`
      columns at lines previously occupied by `json` (current Alpha references:
      `db/schema.rb:40, 42, 45, 166`).
    - Rollback: `bin/rails db:drop`, then `git restore db/schema.rb`.

15. **Audit + fix MySQL-specific code.**
    - Action: grep for: `mysql2`, backtick-quoted SQL identifiers, `tinyint(1)`,
      raw `0`/`1` boolean literals, MySQL-specific `enum` syntax, FULLTEXT
      indexes, case-insensitive uniqueness validations relying on collation,
      `LIMIT` in `update_all`. For each finding, fix in place and note in
      `challenges.md`. Pay particular attention to slug/email uniqueness —
      convert to `LOWER()`-indexed or note that Phase 3 will switch the column
      to `citext`. Apply the citext-scope checklist from section 4a (migrate
      `saved_views.url` to `citext`; add explicit `case_sensitive: false` to the
      five named uniqueness validators). Apply the bug fix listed in section 8a
      (`create_video.rb` JSON tags coercion + matching spec).
    - Expected: grep returns no MySQL-specific patterns except in (a) historical
      `db/migrate/*` files (acceptable — they ran once against MySQL; under
      Postgres they re-run cleanly because Rails translates portable types) and
      (b) intentional comments documenting the port. Document any non-obvious
      fix in `challenges.md`.
    - Rollback: per-file `git restore`.

16. **Run the full spec suite.**
    - Action: `bundle exec rspec`.
    - Expected: green. Failures fall into three categories: (a)
      MySQL-collation-dependent specs — rewrite as adapter-agnostic; (b)
      timezone-dependent Groupdate specs — confirm UTC handling, freeze time,
      adjust expectations; (c) genuine bugs — fix and note.
    - Rollback: per-spec `git restore`; if a spec's behaviour cannot be
      preserved under Postgres without product-level change, escalate to
      architect rather than weaken the assertion.

17. **Add the extensions spec.**
    - Action: write `spec/db/extensions_spec.rb` asserting `pgcrypto`, `citext`,
      `vector` are enabled via
      `ActiveRecord::Base.connection.extension_enabled?`.
    - Expected: green spec, three assertions.
    - Rollback: `git rm` the file.

18. **Confirm the per-Puma DB smoke specs.**
    - Action: identify one existing Web Puma request spec that hits the DB (any
      controller spec listing channels) and one MCP tool spec that hits the DB.
      If both exist, no new specs needed — note in the phase log which specs
      cover the gate. If either is missing, write a minimal one.
    - Expected: at least one spec per Puma exercises a DB read end-to-end.
    - Rollback: `git rm` any new specs.

19. **Restart both Pumas and Sidekiq.**
    - Action: stop the running `bin/dev` foreman session if any, restart with
      the new database. Both `web` and `mcp` Procfile entries must come up;
      `worker` (Sidekiq) must come up.
    - Expected: all three processes log a successful boot. No `mysql2` errors,
      no pool-exhaustion warnings.
    - Rollback: stop foreman; the database persists.

20. **Repopulate Meilisearch from Postgres, then unpause cron.**
    - Action: with Postgres healthy and Sidekiq running, run
      `ReindexAllJob.perform_now`
      (`bin/rails runner 'ReindexAllJob.perform_now'`) to push the freshly
      seeded Postgres records into Meilisearch. Once green, unpause the
      `reindex_search` cron entry in `config/sidekiq_cron.yml` that was paused
      in step 3.
    - Expected: job completes without errors; the search bar returns results for
      known-seeded titles; the cron is back on schedule.
    - Rollback: none — read-only against Postgres. If reindex fails, leave the
      cron paused and escalate.

21. **Spot-check Chartkick + Groupdate dashboards.**
    - Action: open a dashboard page that uses `group_by_day` / `group_by_week` /
      `group_by_month`. Compare bucket boundaries against expectation.
    - Expected: buckets align with UTC days/weeks/months. Any drift relative to
      Alpha is timezone-related and documented.
    - Rollback: revert `application.rb` timezone change if it produces visible
      regressions, then re-investigate.

22. **Update `pito/docs/architecture.md` and `pito/docs/setup.md`.**
    - Action: add the Postgres section, the connection-pool rule, the extensions
      list, the timezone decision, the `bin/setup` flow, the credentials block
      to paste, the `psql \dx` confirmation step.
    - Expected: docs reflect the implemented reality.
    - Rollback: `git restore docs/`.

23. **Update `pito/CLAUDE.md`** (one-line tech-stack edit) and **tick checkboxes
    in `02-plan.md`**, append `additions.md` (citext bundling), append `log.md`
    (session summary).
    - Expected: plan tracking is current.
    - Rollback: `git restore` the affected docs.

24. **Run the gate suite.**
    - Action: `bundle exec rspec`, `bin/brakeman`, `bin/bundler-audit`, review
      Dependabot.
    - Expected: all green.
    - Rollback: per-finding fixes; do not silence warnings without architect
      approval.

25. **Hand off to manual test.**
    - Action: post the manual test recipe (section 7) to the user. Wait for
      green from the user before any commit. Per `beta.md`, Claude does not
      commit on the user's behalf.
    - Expected: user signs off.
    - Rollback: address any issues raised, re-run gate suite, re-hand-off.

26. **(After user verification) Run the cleanup pass — see section 4b.**
    - The cleanup is a separate implementer pass, kicked off only after the
      architect confirms with the user that the migration is verified working.
      It is NOT part of the same pass that runs steps 1–25.

---

## 4a. Citext scope (narrow)

The audit confirmed most uniqueness validations in the pito codebase use opaque
identifiers (YouTube channel/video/playlist/playlist-item IDs, hex token
digests, dates) where case sensitivity is irrelevant. The `citext` extension is
enabled (per section 2 and the extensions migration), but Phase 2 migrates
exactly **one** column to a `citext` type:

- `saved_views.url` — free-text URL with `scoped_to(:kind)` uniqueness. Case
  differences must not create duplicates.

All other models with `validate_uniqueness_of(...).case_insensitive`
shoulda-matchers stay on `string`/`text` columns because their values are opaque
ASCII identifiers:

- `channels.youtube_channel_id`
- `videos.youtube_video_id`
- `playlists.youtube_playlist_id`
- `playlist_items.youtube_playlist_item_id`
- `app_settings.key`

For these, the model-side validators must declare `case_sensitive: false`
explicitly. MySQL's default case-insensitive collation hid the omission;
Postgres will not. Add the keyword where missing so shoulda-matchers keep
passing.

Checklist (folded into step 15 of section 4):

- [ ] `saved_views.url` migrated to `citext` (with the scoped uniqueness index
      preserved).
- [ ] Each model named above declares `case_sensitive: false` on its uniqueness
      validator. Audit and add where absent.
- [ ] Shoulda-matcher specs for all five remain green under Postgres.

---

## 4b. Cleanup after verification

This is a **separate implementer pass**, kicked off only after the architect
confirms with the user that the migration in section 4 is verified working (all
acceptance criteria green, all manual test recipe steps green, the user has
signalled OK). The cleanup is NOT part of the same pass that runs steps 1–25.

Rationale: keeping the `:mysql` credential block and `MYSQL_*` env keys around
during the migration window means a one-line rollback if anything regresses.
Once the cutover is stable, the legacy keys are dead weight and get removed.

Cleanup actions:

1. **Remove the `:mysql` block from per-environment credential files.**
   - User runs `bin/rails credentials:edit --environment development` and
     deletes the top-level `:mysql:` block. Saves.
   - User runs `bin/rails credentials:edit --environment test` and deletes the
     top-level `:mysql:` block. Saves.
   - Verification:
     `bin/rails runner 'p Rails.application.credentials.dig(:mysql, :username)'`
     returns `nil` in both environments. `dig(:postgres, :username)` still
     returns the expected value.

2. **Remove `MYSQL_*` env vars.**
   - Strip `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`,
     `MYSQL_DATABASE` (and any other `MYSQL_*` keys) from `.env.example`,
     `.env.development`, `.env.test`.
   - Verification: `git grep -i MYSQL .env.example .env.development .env.test`
     returns no hits.

3. **Remove leftover `MYSQL_*` references in tooling and docs.**
   - Audit and clean: `pito/bin/setup`, `pito/config/deploy.yml` (comments),
     `pito/README.md`, `pito/CLAUDE.md`. Replace any `MYSQL_*` reference with
     the `POSTGRES_*` equivalent or remove if obsolete.
   - Verification:
     `git grep -i mysql pito/bin pito/config pito/README.md pito/CLAUDE.md`
     returns no functional hits (only intentional historical notes, e.g., a
     one-line "Phase 2 replaced MySQL with Postgres" note in `architecture.md`,
     are acceptable).

4. **Re-run the gate suite.** `bundle exec rspec`, `bin/brakeman`,
   `bin/bundler-audit`. All green.

5. **Append a `log.md` entry** noting the cleanup pass completed and what was
   removed.

6. **Hand off the cleanup diff to the user for review and commit.** Same
   workflow as the main pass: implementer does not commit; the user validates
   and signs off.

This cleanup pass is small (a credentials edit, a few file deletions, a docs
grep-and-fix). It does not require its own branch — the implementer can run it
on `step-postgres` if the main pass is not yet merged, or on a new branch
(`step-postgres-cleanup`) if the main pass has already landed.

---

## 5. Safe MySQL teardown rubric

Destructive Docker actions on a developer machine can take out unrelated
projects. Before any teardown, the implementer follows this protocol exactly.

### 5.0 Resource classification

The user's machine hosts a second project (`client-api`) sharing the Docker
daemon. The implementer classifies every resource encountered during enumeration
into one of three buckets and acts only on bucket (b).

**(a) DO NOT TOUCH — non-pito or shared infrastructure.** Leaving these intact
is non-negotiable, regardless of confirmation:

- Container `client-api-mysql-dev-1` (image `mysql:8.0`) — belongs to the
  client-api project.
- Container `client-api-redis-1` (exited) — belongs to the client-api project.
- Network `client-api_default` — client-api project network.
- Anonymous volumes
  `ad833d7b82cb4e42926b0fa4b7f05d9b417d2961f19ab71fc5fc3fe46e02507f` and
  `b8e152e68028299c641abf2db9026564f60cc56349e197c1b6bedf3548d976e5` — origin
  unknown; preserve unless positively identified as pito's during enumeration.
- Built-in Docker networks `bridge`, `host`, `none`.

**(b) Pito-owned, destroy with explicit confirmation.** Targets of section 5.3:

- Container `pito-mysql-1`.
- Volume `pito_mysql_data`.
- Host bind file `pito/docker/mysql/init.sql` (and the now-empty
  `pito/docker/mysql/` directory).

**(c) Pito-owned, KEEP RUNNING in this phase.** Untouched by Phase 2; required
by the running stack:

- Containers `pito-redis-1`, `pito-meilisearch-1`.
- Volumes `pito_redis_data`, `pito_meilisearch_data`.
- Network `pito_default` — shared with redis and meilisearch; do NOT delete.

If enumeration surfaces a resource that does not fall cleanly into one of the
three buckets, the implementer halts and pings the architect. No guessing.

### 5.1 Enumeration (run, print, STOP)

The implementer runs each command below and prints the output verbatim in the
session, **then halts** for the architect to confirm the names with the user
before any destructive command.

```bash
# Containers known to compose
docker compose ps -a --format '{{.Name}}\t{{.Service}}\t{{.State}}'

# Volumes attached to this compose project
docker compose config --volumes

# Concrete volume names as Docker stores them (project-prefixed)
docker volume ls --filter "label=com.docker.compose.project=$(basename "$PWD")" --format '{{.Name}}'

# Networks for this project
docker network ls --filter "label=com.docker.compose.project=$(basename "$PWD")" --format '{{.Name}}'

# Image currently used by the mysql service (for record only — do not remove images here)
docker compose images mysql
```

The implementer expects exactly one MySQL container, one volume named
`<project>_mysql_data`, and possibly one network. If anything else appears
(e.g., a leftover `mysql` container from another project, an orphan volume), the
implementer halts and pings the architect — does not guess.

### 5.2 STOP-and-confirm protocol

After printing enumeration output, the implementer says:

> "Awaiting confirmation: about to remove container `<exact-name>`, volume
> `<exact-name>`, leaving Redis (`<name>`) and Meilisearch (`<name>`) untouched.
> Confirm before I proceed."

The architect relays to the user. **No destructive action runs without explicit
user confirmation through the architect.**

### 5.3 Permitted destructive commands

After confirmation, only these commands are allowed, with the exact names from
enumeration substituted:

```bash
docker compose stop mysql
docker compose rm -f mysql
docker volume rm <project>_mysql_data
```

### 5.4 Forbidden commands

The following are **never** run, regardless of confirmation:

- `docker system prune` (any flags)
- `docker volume prune` (any flags)
- `docker container prune` (any flags)
- `docker network prune` (any flags)
- `docker volume rm` without the exact `<project>_mysql_data` name
- `docker compose down -v` (removes all volumes including Redis and Meilisearch)
- `docker rm -f $(docker ps -aq)` or any wildcard form

If a non-destructive alternative exists, it is preferred. The bias is always
toward leaving more state intact than necessary.

---

## 6. Acceptance criteria

The phase is complete when **all** of the following hold:

- [ ] `docker compose ps` shows `postgres` healthy; `mysql` is gone.
- [ ] `bundle exec rspec` is green. Every Alpha spec passes against Postgres, or
      the spec was rewritten adapter-agnostic with a comment documenting the
      change, or it is explicitly waived in `challenges.md`.
- [ ] New extensions spec asserts `connection.extension_enabled?('pgcrypto')`,
      `'citext'`, `'vector'` are all true.
- [ ] At least one Web Puma request spec exercises a DB read end-to-end and
      passes.
- [ ] At least one MCP Puma tool spec exercises a DB read end-to-end and passes.
- [ ] `bin/dev` brings up Web Puma, MCP Puma, Sidekiq worker, and the Tailwind
      watcher cleanly. No `mysql2` errors, no pool exhaustion in logs.
- [ ] Sidekiq web at the configured mount point loads and shows healthy queues.
- [ ] Meilisearch reindex completes without errors against Postgres.
- [ ] Chartkick + Groupdate dashboards render. Bucket boundaries align with UTC.
- [ ] Seed run produces the expected record counts (matching Alpha-era
      expectations) plus the 5–10 new edge-case records.
- [ ] `psql -h 127.0.0.1 -p 5433 -U pito pito_development -c '\dx'` lists
      `pgcrypto`, `citext`, `vector`.
- [ ] `db/schema.rb` is clean Postgres syntax with the three `enable_extension`
      lines at the top.
- [ ] `bin/brakeman` is clean (or any new warning is documented in
      `security.md`).
- [ ] `bin/bundler-audit` is clean. `pg` gem version has no open advisories.
- [ ] Dependabot alerts reviewed; any new alerts triaged in `security.md`.
- [ ] `pito/docs/architecture.md` and `pito/docs/setup.md` reflect the Postgres
      reality.
- [ ] `02-plan.md` checkboxes ticked, `log.md` has the session entry,
      `additions.md` notes the citext bundling.
- [ ] `pito/CLAUDE.md` tech-stack line updated to Postgres.
- [ ] User has manually run the recipe in section 7 and signed off.

---

## 7. Manual test recipe

The user runs through this end-to-end before authorising commit. The implementer
posts this verbatim in the handoff message.

1. **Clean state check.** From `pito/`, confirm `git status` shows only the
   expected files. Stop any running `bin/dev` session.
2. **Confirm credentials (development).** Run
   `RAILS_ENV=development bin/rails runner 'p Rails.application.credentials.dig(:postgres, :username)'`.
   Should return the same value as `dig(:mysql, :username)` did before the
   migration (verbatim copy). Repeat for `:password` and `:database`. If any
   return `nil`, run `bin/rails credentials:edit --environment development` and
   add the `:postgres` block per step 11 of section 4.
3. **Confirm credentials (test).** Run
   `RAILS_ENV=test bin/rails runner 'p Rails.application.credentials.dig(:postgres, :username)'`.
   Same expectation as above. If `nil`, edit
   `bin/rails credentials:edit --environment test`.
4. **Confirm Postgres container is reachable with those credentials.** Connect
   via
   `psql -h 127.0.0.1 -p 5433 -U <username-from-credentials> <database-from-credentials>`
   and enter the password from credentials when prompted. The connection should
   succeed and drop you at a `pito_development=#` prompt. Run `\q` to exit.
   (This proves docker-compose `POSTGRES_USER` / `POSTGRES_PASSWORD` /
   `POSTGRES_DB` match the credentials block — same auth as MySQL was.)
5. **Run setup.** `bin/setup`. Postgres container comes up healthy, migrations
   run, seeds populate. No errors.
6. **Start the stack.** `bin/dev`. All processes from `Procfile.dev` start:
   `web`, `mcp`, `worker`, `css`, `tunnel`. No `mysql2` errors. No pool
   warnings.
7. **Web smoke (Web Puma).** Visit `https://app.pitomd.com/` (via the
   cloudflared tunnel). Click through `/`, `/channels`, `/videos`,
   `/saved_views`, `/settings`. All render.
8. **Search.** Type a known-seeded title in the search bar. Meilisearch returns
   results.
9. **CRUD smoke.** Create a channel via the web UI. Open a Rails console
   (`bin/rails c`) and confirm `Channel.last` reflects the input.
10. **Background job smoke.** Bulk-delete a couple of seeded videos. Confirm the
    job completes via Sidekiq Web (`/sidekiq` with HTTP basic auth) — queue
    empties.
11. **MCP smoke (MCP Puma).** From a configured Claude desktop or a `curl` with
    a valid bearer, hit `https://mcp.pitomd.com/mcp` and call any read-only tool
    (e.g., `list_channels`). Result returns the seeded channels.
12. **Specs.** `bundle exec rspec`. Green.
13. **Extensions confirmation.** Reconnect via `psql` (using the credentials
    from step 4) and run `\dx`. Lists `pgcrypto`, `citext`, `vector`.
14. **Schema confirmation.** Open `db/schema.rb`. Top of file shows
    `enable_extension "pgcrypto"`, `"citext"`, `"vector"`. No MySQL-isms
    anywhere.
15. **Charts confirmation.** Open the dashboard page. `group_by_day` charts
    render with sensible UTC buckets.

If every step is green, the user signals OK and the implementer commits + pushes
per `beta.md` workflow. After the commit lands and the migration is confirmed
stable, the architect kicks off the cleanup pass per section 4b (remove the
now-dead `:mysql` credential block, `MYSQL_*` env keys, and any leftover
`MYSQL_*` references in tooling/docs).

---

## 8. Risks and open questions

- **Active Record Encryption keys.** Encrypted columns in Alpha were stored
  under MySQL `text`. Postgres also uses `text`; the encrypted blob is portable.
  The risk is the keys themselves — verify they survive the credentials edit
  (the credentials file is patched, not rewritten). The implementer reads back
  encrypted records after re-seeding to confirm decryption works. If decryption
  fails on read, escalate.
- **Existing migration file portability.** Alpha migrations were written against
  MySQL. Most Rails column types map cleanly, but a migration using
  `t.string :foo, limit: 191` (a MySQL utf8mb4 index-length workaround) or any
  raw
  `execute "ALTER TABLE \`foo\`…"`will fail under Postgres. The implementer scans`db/migrate/`
  during step 13 and fixes in-place rather than via a new migration (these run
  against a fresh DB, so editing history is acceptable per the
  no-data-preservation decision).
- **Port 5433 collision.** The default avoids the host's 5432. If 5433 is also
  taken, the implementer escalates rather than silently picking another port.
- **Sidekiq concurrency env var.** `config/sidekiq.yml` hardcodes concurrency
  to 5. The pool-sizing formula references `SIDEKIQ_CONCURRENCY` env. If the env
  is unset, the formula falls back to 5, matching the YAML. Document this; don't
  change Sidekiq's config in this phase.
- **`view_component` and `draper` Postgres compatibility.** Both gems are
  DB-agnostic; no expected risk. Flag here only as a sanity-check item.
- **MCP token table.** A migration `20260428151207_create_mcp_access_tokens.rb`
  exists. Phase 3 will replace this with `api_tokens`. Phase 2 only re-runs the
  existing migration as-is against Postgres; no schema rewrite here.
- **Cloudflared tunnel.** Config in `Procfile.dev` references
  `tunnel: cloudflared tunnel run pito`. Tunnel config is unaffected by the DB
  swap; flagged only because the user's manual test relies on it.
- **`bin/setup` credential-detection logic.** The current `bin/setup` greps for
  the MySQL credentials block and prints a help message if missing. The Postgres
  rewrite does the same for the new key path. The implementer ports the logic
  literally; doesn't re-engineer.

---

## 8a. In-scope bug fixes surfaced by the migration

The audit surfaced a real bug that MySQL silently masked but Postgres
`json`/`jsonb` will reject (or store as a JSON string scalar instead of an
array). Fix as part of Phase 2:

- **`create_video` JSON tags coercion.** `app/mcp/tools/create_video.rb:29`
  assigns a comma-separated string (`"tag1,tag2"`) directly to `videos.tags`.
  Replace the assignment with
  `tags.to_s.split(',').map(&:strip).reject(&:blank?)` so the column receives a
  proper JSON array. Update the matching test
  `pito/spec/mcp/tools/create_video_spec.rb:30` (currently asserts
  `expect(video.tags).to eq("tag1,tag2")`) to assert array equality
  (`eq(["tag1", "tag2"])`).

This is the only behavioural bug fix in scope for Phase 2. Any further bugs
uncovered during step 15 are documented in `challenges.md` and escalated to the
architect for in-scope vs. follow-up triage.

---

## 9. Out of scope

The following are **explicitly not** part of this spec:

- Any new schema beyond the extensions migration. No `users`, `tenants`,
  `api_tokens` tables — those are Phase 3.
- Adding any vector columns or vector indexes. Phase 10.
- Adding any `citext` columns beyond the single one called out in section 4a
  (`saved_views.url`). The extension is enabled here so Phase 3 can use it
  broadly (emails, slugs); only the one Phase-2-relevant column is migrated now.
- Production Postgres setup, Hetzner provisioning, Kamal config. Phase 16.
- Multi-environment Postgres beyond `development` and `test`. Production
  credentials and config land in Phase 16.
- Lane 2a (`pito-sh`) or Lane 2b (MCP tool surface) work. Per ADR 0002, an
  infrastructure swap has no Lane 2 surface to fan out to. Restarting MCP Puma
  and confirming a tool call resolves is acceptance, not Lane 2 implementation.
- Backup tooling for Postgres dumps, pgvector data, or Meilisearch snapshots.
  Phase 14.
- Rate limiting, CSP, or other security hardening on the Pumas. Phase 15.
- Login UI, sessions, OAuth server. Phase 12.
- Any rewrite of `Procfile.dev` process names or splitting the worker into
  multiple queues.
- Any change to `pito-sh`, `pito-website`, or this `pito-dev-kb` repo beyond
  plan/log/additions tracking under `02-postgres-migration/`.

---

_End of spec._
