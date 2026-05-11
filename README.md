# Pito

Personal YouTube management tool. Tracks video performance across multiple
channels, manages workspaces, surfaces "best time to publish" heatmaps, runs a
games library tied to videos, and pushes activity to Slack / Discord webhooks.

Single-install, multi-user (auth-only — every authenticated user has
install-wide access; no per-user data isolation). Runs locally for development
and self-hosted in production.

## Features

- Channel + video import, sync, and starring; bulk sync / bulk delete with an
  in-page confirmation framework (no JS `alert` / `confirm`).
- Workspaces — channels and videos pages render as multi-pane layouts;
  `SavedView` persists URL state for quick restore.
- Analytics — daily-views, views-by-channel, top-videos, engagement charts via
  Chartkick + Chart.js; viewer-time heatmaps (day-of-week × hour-of-day) per
  video and per channel, rolled up in the authenticated user's timezone.
- Games surface — primary-genre picker, nested shelves, collections modal,
  multi-version game grouping. Backed by IGDB metadata; cover-art variants via
  Active Storage + libvips.
- Authentication — email + password local sign-in, TOTP 2FA enrollment (with
  QR-code SVG via `rotp` + `rqrcode`), and new-location approval on suspicious
  sign-in.
- Webhooks — Slack and Discord push targets for activity events, rendered in the
  user's timezone.
- Search — Meilisearch full-text over videos (channels intentionally not
  indexed; they hold no title / description in this phase).
- Embeddings — pgvector-backed similarity over notes; Voyage AI as the embedding
  provider behind a per-target AppSetting flag.
- MCP — Model Context Protocol server (stdio + dedicated HTTP Puma) exposes a
  scoped tool catalog for Claude Mobile and the `pito` CLI. See `docs/mcp.md`.
- CLI — unified Rust `pito` binary (Ratatui TUI default, subcommands for
  `pito footage` import and more). See `extras/cli/`.

## Stack

- Ruby 3.4.9, Rails 8.1 with Hotwire (Turbo + Stimulus), ERB, Tailwind CSS,
  ViewComponent, Draper
- Postgres 17 (Docker, `pgvector/pgvector:pg17`) — primary datastore, with
  pgvector, pgcrypto, citext
- Redis 7 (Docker) — Sidekiq queue + Rails cache
- Meilisearch v1.13 (Docker) — full-text search over videos
- Sidekiq + sidekiq-cron — background jobs (daily channel sync, viewer-time
  refresh at 03:00, daily reindex, daily digest)
- Chartkick + Groupdate + Chart.js — charts
- Doorkeeper — OAuth 2.0 server (Authorization Code + PKCE only, for Claude
  Mobile)
- `rotp` + `rqrcode` — TOTP 2FA enrollment + verification
- `friendly_id` — renameable slugs (Project, Bundle, Collection, MilestoneRule)
  and identifier reuse (Channel, Video, Game, Footage)
- `image_processing` + `ruby-vips` (libvips) — Active Storage variants for game
  cover art
- `aasm` — state machines for Timeline and Video
- `commonmarker` + `neighbor` — GFM rendering + pgvector cosine queries on notes
- `google-apis-youtube_v3` + `google-apis-youtube_analytics_v2` — YouTube APIs
- MCP gem — Model Context Protocol server
- Rust (Ratatui) — unified `pito` CLI binary at `extras/cli/`
- Cloudflare Pages — marketing site at `extras/website/`
- Active Record Encryption — encrypts sensitive AppSetting fields and OAuth
  refresh tokens at rest

## Requirements

- Ruby 3.4.9 (via [mise](https://mise.jdx.dev/) — see `mise.toml`)
- Docker & Docker Compose
- libvips (system package — required by `ruby-vips` for cover-art variants)
- Bundler

## Getting started

```bash
cp .env.example .env.development
cp .env.example .env.test
bin/setup
```

Configure credentials:

```bash
EDITOR=vim bin/rails credentials:edit
```

```yaml
postgres:
  development:
    database: pito_development
    username: pito
    password: ""
  test:
    database: pito_test
    username: pito
    password: ""
owner:
  email: you@example.com
  password: change-me
sidekiq:
  development:
    username: admin
    password: admin
  production:
    username: admin
    password: changeme
```

YouTube API credentials (`api_key`, `client_id`, `client_secret`,
`redirect_uri`) live on the `AppSetting` singleton and are managed from the web
UI (Settings → YouTube). Sensitive fields use Active Record Encryption.

If transitioning from a previous install that stored YouTube credentials under
`Rails.application.credentials.google_oauth`, run the one-shot, idempotent
backfill:

```bash
bin/rails pito:backfill_youtube_credentials
```

The task never overwrites a value already set on the singleton; the credentials
block is left in place as a manual revert path.

Seed sample data:

```bash
bin/rails db:seed
```

## Run

```bash
bin/dev
```

Starts Docker services (Postgres, Redis, Meilisearch), Puma, Sidekiq, the
Tailwind watcher, and the MCP HTTP Puma.

Open http://localhost:3000

## Search

Meilisearch powers full-text search over videos. After seeding data, click
`[reindex]` on the settings page to index all records. A daily `ReindexAllJob`
keeps the index fresh.

## Test

```bash
bundle exec rspec
bundle exec rubocop
```

For parallel runs (per-CPU Postgres test DBs):

```bash
bin/parallel_setup        # one-time after a fresh checkout
bundle exec parallel_rspec spec/
```

## Production

Pito is designed to sit behind Cloudflare. The production environment sets
`config.assume_ssl = true` and `config.force_ssl = true`, and trusts the
Cloudflare IPv4 + IPv6 ranges via `config.action_dispatch.trusted_proxies` so
`request.remote_ip` resolves to the originating client rather than the
Cloudflare edge. A drift watchdog flags changes in the upstream Cloudflare IP
ranges. Refresh the lists from
[Cloudflare IPv4](https://www.cloudflare.com/ips-v4) and
[Cloudflare IPv6](https://www.cloudflare.com/ips-v6) when the watchdog fires.

## Status

Beta 2. Phases 1–10, 12–28 shipped: auth + sessions + API tokens + Doorkeeper,
Google OAuth + YouTube client tier, workspaces + saved views, project workspace
UI, video import + sync diff dialog, games + IGDB + multi-version grouping,
login security + 2FA, webhooks + timezones + viewer analytics, friendly URLs,
CLI parity surfaces. Phase 11 (video workflow features) has an architect spec
ready; implementation is queued.

See `docs/architecture.md` for the runtime topology, `docs/auth.md` for the auth
model, `docs/mcp.md` for the MCP tool surface, `docs/setup.md` for first-run
setup, and `docs/plans/beta/` for per-phase plans and logs.

## License

All rights reserved. This is proprietary software. Unauthorized copying,
distribution, or use is strictly prohibited.
