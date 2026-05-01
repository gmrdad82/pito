# Architecture

This document captures the runtime topology and the platform decisions Pito relies on. It is the seed file from Phase 1 / Phase 2; further phases append rather than rewrite.

## Datastore — Postgres 17 (Phase 2)

Pito's primary relational store is Postgres 17 via the `pgvector/pgvector:pg17` Docker image. Running on `127.0.0.1` and (in development) listening on host port `5433` so it never collides with a host-installed Postgres on `5432`.

### Extensions

A single migration (`db/migrate/<TS>_enable_postgres_extensions.rb`) enables three extensions at the database level:

- `pgcrypto` — `gen_random_uuid()` and other crypto helpers. Phase 3 (auth) consumes it.
- `citext` — case-insensitive text type. Used today only for `saved_views.url`. Phase 3 will use it for emails and slugs.
- `vector` — pgvector. Installed but no columns yet. Phase 10 (embeddings) adds the first vector column.

Bundling `citext` into the Phase 2 extensions migration is an architectural decision: it lets Phase 3 ship without a separate extensions-only migration. The deviation is documented in `pito-dev-kb/plans/beta/02-postgres-migration/additions.md`.

### Timezone

The Rails app pins both `config.time_zone = "UTC"` and `config.active_record.default_timezone = :utc` so Groupdate aggregates render predictably under Postgres `timestamptz`. Charts use UTC bucket boundaries.

### Connection pool sizing

`config/database.yml` sets `pool` to `max(RAILS_MAX_THREADS, MCP_THREADS, SIDEKIQ_CONCURRENCY)`. With current defaults (Web Puma 3 threads, MCP Puma 5 threads, Sidekiq concurrency 5) the pool resolves to 5. Each Puma process maintains its own pool; Sidekiq has its own.

### Credentials

Postgres credentials live in Rails encrypted credentials under the `:postgres` block (`development` and `test` sub-keys). Values are copied verbatim from the legacy `:mysql` block to minimise surprise during the cutover. The `:mysql` block is retained until the post-verification cleanup pass per spec section 4b.

`.env.development` / `.env.test` carry connection metadata only (`POSTGRES_HOST`, `POSTGRES_PORT`). Database name, username, and password live exclusively in Rails encrypted credentials. No secrets in env files.

### json vs jsonb

All JSON columns use `jsonb` (better indexing, faster queries). `t.json` is forbidden in new migrations.

## Search — Meilisearch 1.13

Search index lives in Meilisearch (`meilisearch_data` Docker volume). Reindex is auto-enqueued via the `Searchable` concern on every save/destroy, plus a daily `reindex_search` cron via sidekiq-cron.

## Background jobs — Sidekiq

Backed by Redis (`redis:7` Docker volume `redis_data`). Queues: `default`, `bulk_deletion`, `search`. Concurrency 5 (`config/sidekiq.yml`). Web UI at `/sidekiq` with HTTP basic auth.

## Process model — dual Puma + worker

`Procfile.dev` declares:

- `web` — Web Puma on port 3000 (3 threads).
- `mcp` — MCP HTTP Puma on port 3001 (5 threads).
- `worker` — Sidekiq.
- `css` — Tailwind watcher.
- `tunnel` — cloudflared tunnel exposing `app.pitomd.com` and `mcp.pitomd.com`.

Both Pumas share `database.yml`; each maintains its own connection pool sized by the rule above.
