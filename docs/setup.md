# Setup

End-to-end developer setup for Pito. Run these once on a fresh machine.

## Prerequisites

- Docker (with `docker compose`).
- Ruby (managed by `mise.toml` — `mise install`).
- Node-free build: Tailwind CLI ships with the gem, so no Node install is required.

## 1. Clone and bundle

```bash
git clone <repo-url> pito && cd pito
bundle install
```

## 2. Bring up Postgres + Redis + Meilisearch

```bash
docker compose up -d
```

Verify all three are healthy:

```bash
docker compose ps
```

Expected: `pito-postgres-1`, `pito-redis-1`, `pito-meilisearch-1` all `(healthy)`.

## 3. Configure credentials

Postgres username/password/database live in Rails encrypted credentials. Open the editor and add a `:postgres` block alongside the existing `:mysql` block:

```bash
EDITOR=vim bin/rails credentials:edit
```

Add the following (development and test reuse the same docker-compose user):

```yaml
postgres:
  development:
    database: pito_development
    username: pito
    password: "Pass123#"
  test:
    database: pito_test
    username: pito
    password: "Pass123#"
```

The legacy `:mysql` block is retained until the Phase 2 cleanup pass and may be removed once the migration is verified.

## 4. Configure environment

Copy the example env files (gitignored) and adjust if your ports collide:

```bash
cp .env.example .env.development
cp .env.example .env.test
```

The defaults expect Postgres on `127.0.0.1:5433`, Redis on `:6380`, Meilisearch on `:7700`. Override `POSTGRES_HOST`/`POSTGRES_PORT` if your host already runs Postgres on `5432`.

Optional: set a single `DATABASE_URL` instead of discrete keys (commented in `.env.example`).

## 5. Database create + migrate + seed

```bash
bin/rails db:prepare
bin/rails db:seed
```

Confirm extensions are enabled:

```bash
psql -h 127.0.0.1 -p 5433 -U pito pito_development -c "\dx"
```

Expected output lists `pgcrypto`, `citext`, `vector`.

## 6. Run the stack

```bash
bin/dev
```

This runs `Procfile.dev`: Web Puma (3000), MCP Puma (3001), Sidekiq, Tailwind watcher, and the cloudflared tunnel.

## Connection pool considerations

`config/database.yml` sizes the pool to `max(RAILS_MAX_THREADS, MCP_THREADS, SIDEKIQ_CONCURRENCY)`. Each Puma process and Sidekiq each maintain their own pool, so under full load total Postgres connections from this app are roughly `WebPuma_threads + MCPPuma_threads + Sidekiq_concurrency`. Development is fine with the defaults; production sizing is a Phase 16 concern.

## Tests

```bash
bundle exec rspec
```

The test database is created via `bin/rails db:test:prepare` (also called by `bin/setup`).
