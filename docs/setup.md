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
`pito-redis-data`, `pito-meilisearch-data`, `pito-notes`, `pito-assets`) so
they're easy to spot in `docker volume ls` next to other projects' volumes. The
first three back the running services. `pito-notes` and `pito-assets` are
reserved for the Hetzner cutover (Phase 16) — declared in `docker-compose.yml`
so the names are pinned, currently unmounted because Rails runs natively on the
dev host and reads `PITO_NOTES_PATH` / `PITO_ASSETS_PATH` from the environment.

`pito-assets` is the on-disk home for Pito-managed binary assets: Active
Storage's `:local` service root (game cover art today, future channel banners /
video thumbnails) and footage thumbnails (Phase 7.5 §06). It is NOT a copy of
source footage — `Footage#local_path` continues to point at the user's drive;
only Pito-derived assets land under the volume. The `Pito::AssetsRoot` helper
resolves absolute paths under the root for non-Active-Storage byte writes.

`PITO_ASSETS_PATH` controls where the assets root resolves at runtime. The
committed `.env.example` points at `tmp/pito-assets` for dev (relative paths
anchor to the repo root). Production deployments mount the `pito-assets` Docker
volume at `/var/lib/pito-assets` (the helper's default when the env var is
unset). Tests stay on `:test` / `tmp/storage` for Active Storage isolation; the
volume is unused in the test environment.

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

## Google Cloud / OAuth Setup

Phase 7 (Google OAuth + YouTube API foundation) requires a Google Cloud project
with the YouTube APIs enabled and an OAuth 2.0 Web client configured. This is a
**manual, one-shot setup** the user runs once during initial project bootstrap;
the click-by-click steps below exist for repeatability on a fresh machine or a
fresh Google account. Locked by decision 7.3 in
`docs/plans/beta/07-google-oauth-youtube-foundation/specs/7a-google-oauth-and-identity.md`
— sole-user / single-tenant Beta; automation via `gcloud` CLI is revisited
if/when a team scales the project.

This is a deployment-/credentials-time concern, not a first-boot concern — skip
it until Phase 7 work is actually starting.

### 1. Sign in to Google Cloud Console

Visit https://console.cloud.google.com and sign in with the Google account that
**owns the YouTube channels Pito will read**. The OAuth client lives under this
account; the channels Pito syncs are the ones this account can administer.

If Google offers the "$300 free credits" trial, **skip it** — not needed.
YouTube Data API v3 and YouTube Analytics API v2 are free up to their daily
quota; no billing account is required for Pito's read-only usage.

### 2. Create the project

APIs & Services → "Select a project" dropdown → **New Project**.

- **Project name:** `pito` (lowercase).
- **Project ID:** auto-assigned (e.g. `pito-495614` — yours will differ; cite
  this value when configuring credentials in step 6).
- **Organization:** none.
- **Billing:** none.

Click Create and wait for the project to provision.

### 3. Enable the YouTube APIs

APIs & Services → **Library** → search for and enable each:

- **YouTube Data API v3** — channel / video / playlist read access.
- **YouTube Analytics API** (v2) — per-video / per-channel analytics read.

Both must show "API enabled" in their cards before continuing.

### 4. Configure the OAuth consent screen ("Google Auth Platform")

Google's late-2024 UI revamp split this surface across four tabs. Walk through
each in order.

#### Branding tab

- **App name:** `pito` (lowercase).
- **User support email:** your address.
- **App logo:** optional, skip for sole-user setup.
- **Authorized domain:** `pitomd.com`.
- **Developer contact email:** your address.

Save and continue.

#### Audience tab

- **User type:** **External**.
- **Publishing status:** **Testing**. Stay in Testing forever for sole-user use
  — see "Why Testing mode forever" below.
- **Test users:** add your own Google email under "Test users". This is the
  account that will be allowed through the consent screen.

Save and continue.

#### Data Access tab

Declare two scopes Pito needs:

- `https://www.googleapis.com/auth/youtube.readonly` — sensitive scope (channel
  / video read).
- `https://www.googleapis.com/auth/yt-analytics.readonly` — non-sensitive as of
  Google's late-2024 reclassification (analytics read).

No other scopes. Phase 7 is read-only by locked decision; write scopes
(`youtube`, `youtube.upload`) wait for Phase 10.

Save and continue.

#### Clients tab

Create the OAuth 2.0 Web Application client:

- **Application type:** Web application.
- **Name:** `pito-api`.
- **Authorized JavaScript origins:** leave blank.
- **Authorized redirect URIs:** `https://app.pitomd.com/auth/google/callback`. A
  single redirect URI works for both dev and prod because dev uses the
  Cloudflare tunnel mapping `app.pitomd.com` to localhost (see "Dev and prod
  share OAuth credentials" below).

Click Create. A modal shows the **Client ID** and **Client Secret** — these are
shown **once**. Capture both before dismissing.

### 5. Persist credentials into Rails

The Phase 7 spec wires Pito to read OAuth credentials from
`Rails.application.credentials.google_oauth`:

```bash
EDITOR=nano bin/rails credentials:edit
```

Add the `:google_oauth` block (paste the values captured in step 4 — yours will
differ; the worked-example `project_id` is `pito-495614`):

```yaml
google_oauth:
  project_id: pito-495614
  client_id: <your client id>.apps.googleusercontent.com
  client_secret: <your client secret>
```

The interactive `EDITOR=nano bin/rails credentials:edit` flow is the canonical
instruction. (A Ruby-shim variant —
`EDITOR='ruby /tmp/edit-creds.rb' bin/rails credentials:edit` — was used as a
session-specific automation during the original walkthrough, but the simpler
interactive flow is the recommended path for fresh setups.)

Save and exit. The `master.key` decrypts the file at runtime.

### Why Testing mode forever

Pito runs as a single-user app for the foreseeable future, so the friction of
publishing the OAuth consent screen for verification is not worth taking on.
Specifically:

- **100-test-user cap is irrelevant.** Testing mode caps at 100 test users; sole
  user use never approaches it.
- **No app verification overhead.** Publishing for verification means submitting
  scopes for Google review (sensitive scopes especially), demonstrating a
  privacy policy, etc. Testing mode bypasses all of it.
- **7-day refresh-token TTL is fine.** Google expires refresh tokens issued by
  Testing-mode apps after 7 days. Pito refreshes regularly during normal use, so
  the TTL does not bite — Phase 7's `TokenRefresher` keeps the access token
  alive on every API call, which in turn keeps the refresh token in active use.
- **"Google hasn't verified this app" warning is acceptable.** It appears once
  on initial consent and is a click-through ("Advanced" → "Go to pito (unsafe)")
  for the test user. Sole user; sole click-through.

#### When you'd actually need to publish

Trigger conditions for moving to Published / verified status (Theta-phase
concerns):

- Multi-user expansion: Pito grows beyond a sole user (e.g., open beta, team
  use).
- Hitting the 100-test-user cap.
- Removing the "Google hasn't verified this app" warning for non-test users.

Until any of those land, Testing mode is the correct posture.

### Dev and prod share OAuth credentials

The single redirect URI `https://app.pitomd.com/auth/google/callback` works for
both environments because the Cloudflare tunnel maps `app.pitomd.com` to
`127.0.0.1:3027` (the local Web Puma) in development. The same OAuth client
serves both dev OAuth and prod OAuth.

**Tradeoff:** dev and prod share the client secret. Fine for sole user — the
risk surface is just the local machine. If isolation is ever needed (multi-dev,
CI smoke against a staging tunnel, etc.), register a **second** OAuth Web client
in the same Google Cloud project with its own redirect URI (e.g.,
`https://staging.pitomd.com/auth/google/callback`) and a separate
`:google_oauth` credentials block per environment.
