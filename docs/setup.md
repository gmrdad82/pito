# Setup

End-to-end developer setup for Pito. Run these once on a fresh machine.

## Prerequisites

- Docker (with `docker compose`).
- Ruby (managed by `mise.toml` — `mise install`).
- Node-free build: Tailwind CLI ships with the gem, so no Node install is
  required.

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

Expected: `pito-postgres-1`, `pito-redis-1`, `pito-meilisearch-1` all
`(healthy)`.

Volumes are named with the `pito-` prefix (`pito-postgres-data`,
`pito-redis-data`, `pito-meilisearch-data`) so they're easy to spot in
`docker volume ls` next to other projects' volumes.

## 3. Configure credentials

Pito reads three blocks from Rails encrypted credentials: `:postgres` (database
connection), `:owner` (seed-time tenant + user), and `:tokens.pepper` (HMAC key
for API token digests). The `:tokens.pepper` is mandatory before `bin/setup`;
the script halts with a walkthrough if it's absent.

### `:postgres` block

Postgres username/password/database live in Rails encrypted credentials. Open
the editor and add a `:postgres` block:

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

### `:owner` block

`db/seeds.rb` reads `Rails.application.credentials.owner` to seed the
workspace's single Tenant + User. If the block is missing, seeds fall back to
placeholder values and print a warning.

Edit the **development** credentials:

```bash
bin/rails credentials:edit --environment development
```

Add:

```yaml
owner:
  tenant_name: <your-tenant-name>
  username: <your-username>      # alphanumeric, must start with a letter
  email: <your-email>
  password: <your-password>
```

Repeat for the **test** environment so test seeds resolve cleanly:

```bash
bin/rails credentials:edit --environment test
```

The `:owner` block is the single source of truth for the seeded singletons. HTML
routes still operate under the implicit single-user session
(`Current.user = User.first`); login UI lands in Phase 6. JSON API and MCP HTTP
transport require explicit bearer tokens (see `:tokens.pepper` below).

### `:tokens.pepper` block

The auth foundation HMACs every API token digest with a server-side pepper
sourced from this credential. Without it, no token can be minted or
authenticated. Generate a value once and store it:

```bash
bin/rails credentials:edit
```

Add (generate the value with `openssl rand -hex 32`):

```yaml
tokens:
  pepper: <64-char hex>
```

The pepper is set once and rotated never (rotation invalidates every existing
token; pair with mint+revoke ceremonies in a future phase). Full auth model:
`docs/auth.md`.

## 4. Configure environment

Copy the example env files (gitignored) and adjust if your ports collide:

```bash
cp .env.example .env.development
cp .env.example .env.test
```

Pito services bind to `127.0.0.1` on high ports with a `27` suffix marker so
they don't collide with other local projects. See "Local services & ports" below
for the table. Every port is env-overridable (`POSTGRES_PORT`, `REDIS_PORT`,
`MEILISEARCH_PORT`, `PORT`, `MCP_PORT`).

Optional: set a single `DATABASE_URL` instead of discrete keys (commented in
`.env.example`).

### Local services & ports

| Service     | Port  | Bound to    | Override env       |
| ----------- | ----- | ----------- | ------------------ |
| Web Puma    | 3027  | `127.0.0.1` | `PORT`             |
| MCP Puma    | 3028  | `127.0.0.1` | `MCP_PORT`         |
| Postgres    | 54327 | `127.0.0.1` | `POSTGRES_PORT`    |
| Redis       | 64527 | `127.0.0.1` | `REDIS_PORT`       |
| Meilisearch | 7727  | `127.0.0.1` | `MEILISEARCH_PORT` |

The `27` suffix is the pito marker — distinct from sibling projects. Edit
`.env.development` / `.env.test` to override.

## 5. Database create + migrate + seed

```bash
bin/rails db:prepare
bin/rails db:seed
```

`db:seed` creates 1 Tenant + 1 User from the `:owner` credentials block, mints a
default `dev` API token (idempotent), then 100 sample Channels with a
deterministic distribution (7 starred, 6 connected, 2 in the intersection).
Re-running is idempotent.

### Capture the dev token

The seed prints the dev token plaintext to STDOUT inside a banner:

```
================================================================
Dev token minted (save this now — cannot be shown again):
<plaintext>
================================================================
```

**Save this now** — it cannot be retrieved later. Drop it in your password
manager labeled `pito-dev` or set it as `PITO_API_TOKEN` in your shell profile.
The default scope set is
`dev:read dev:write yt:read yt:write project:read project:write` (no
`yt:destructive` or `website:*` — opt in by minting a separate token via
`/settings/tokens`).

If you lose it, revoke it via `/settings/tokens` and mint a new one.

Confirm extensions are enabled:

```bash
psql -h 127.0.0.1 -p 54327 -U pito pito_development -c "\dx"
```

Expected output lists `pgcrypto`, `citext`, `vector`.

## 6. Run the stack

```bash
bin/dev
```

This runs `Procfile.dev`: Web Puma (3027), MCP Puma (3028), Sidekiq, Tailwind
watcher, and the cloudflared tunnel.

### Cloudflare tunnel ingress

The tunnel that fronts `app.pitomd.com` and `mcp.pitomd.com` lives outside this
repo at `~/.cloudflared/config.yml`. Whenever pito's local ports change, point
the tunnel ingress at the new ports:

```yaml
ingress:
  - hostname: app.pitomd.com
    service: http://127.0.0.1:3027
  - hostname: mcp.pitomd.com
    service: http://127.0.0.1:3028
  - service: http_status:404
```

Restart cloudflared after editing — either `cloudflared tunnel run <name>`
directly, or restart `bin/dev` if the tunnel runs under foreman via
`Procfile.dev`. This is a manual step the developer takes whenever ports change;
pito does not manage the tunnel config.

## Connection pool considerations

`config/database.yml` sizes the pool to
`max(RAILS_MAX_THREADS, MCP_THREADS, SIDEKIQ_CONCURRENCY)`. Each Puma process
and Sidekiq each maintain their own pool, so under full load total Postgres
connections from this app are roughly
`WebPuma_threads + MCPPuma_threads + Sidekiq_concurrency`. Development is fine
with the defaults; production sizing is a Phase 16 concern.

## Tests

```bash
bundle exec rspec
```

The test database is created via `bin/rails db:test:prepare` (also called by
`bin/setup`).
