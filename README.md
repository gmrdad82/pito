# Pito

Personal YouTube management tool. Tracks video performance across multiple
channels, manages workspaces, and provides analytics dashboards.

Single-tenant, runs locally.

## Stack

- Ruby 3.4.9, Rails 8.1 with Hotwire (Turbo + Stimulus), ERB, Tailwind CSS
- Postgres 17 (Docker, `pgvector/pgvector:pg17`) — primary datastore
- Redis 7 (Docker) — Sidekiq queue + cache
- Meilisearch v1.13 (Docker) — full-text search
- Sidekiq + sidekiq-cron — background jobs
- Chartkick + Chart.js — charts and analytics

## Requirements

- Ruby 3.4.9 (via [mise](https://mise.jdx.dev/) — see `mise.toml`)
- Docker & Docker Compose
- Bundler

## Setup

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
sidekiq:
  development:
    username: admin
    password: admin
  production:
    username: admin
    password: changeme
```

Seed sample data:

```bash
bin/rails db:seed
```

## Run

```bash
bin/dev
```

Starts Docker services (Postgres, Redis, Meilisearch), Puma, Sidekiq, and
Tailwind watcher.

Open http://localhost:3000

## Search

Meilisearch powers full-text search across channels and videos. After seeding
data, click `[ reindex ]` on the settings page to index all records.

## Test

```bash
bundle exec rspec
bundle exec rubocop
```

## License

All rights reserved. This is proprietary software. Unauthorized copying,
distribution, or use is strictly prohibited.
