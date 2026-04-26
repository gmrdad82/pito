# Pito

Personal YouTube analytics tool. Tracks video performance across multiple channels, logs production effort, and shows simple comparisons.

Single-tenant, runs locally.

## Prerequisites

- Ruby 3.4.9 (managed via mise — see `mise.toml`)
- Docker & Docker Compose
- Bundler

## Setup

1. Clone and install dependencies:

```bash
bundle install
```

2. Copy environment file:

```bash
cp .env.example .env
```

`.env` contains infrastructure connection info only (no secrets):

```
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3307
REDIS_URL=redis://127.0.0.1:6380/0
```

3. Configure MySQL credentials via Rails encrypted credentials:

```bash
EDITOR=vim rails credentials:edit
```

Add this block:

```yaml
mysql:
  development:
    database: pito_development
    username: root
    password: ""
  test:
    database: pito_test
    username: root
    password: ""
```

4. Run setup (starts Docker, prepares DB):

```bash
bin/setup
```

5. Start the app:

```bash
bin/dev
```

This starts Docker services (MySQL, Redis), then Puma, Sidekiq, and Tailwind watcher.

Open http://localhost:3000

## Google Cloud Setup (for YouTube API)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (or use existing)
3. Enable **YouTube Data API v3** and **YouTube Analytics API**
4. Create **OAuth 2.0 Client ID** (Web application)
5. Set redirect URI to `http://localhost:3000/oauth/google/callback`
6. Open the app → **Settings** → paste Client ID, Client Secret, and Redirect URI
7. Go to **Channels** → **Connect a channel** → authorize via Google

## Running Tests

```bash
bundle exec rspec
```

## Linting

```bash
bundle exec rubocop
```

## Background Jobs

Sidekiq dashboard: http://localhost:3000/sidekiq

Recurring sync jobs are configured in `config/sidekiq_cron.yml`.
