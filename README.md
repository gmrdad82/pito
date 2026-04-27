# Pito

Personal YouTube management tool. Tracks video performance across multiple channels, manages workspaces, and provides analytics dashboards.

Single-tenant, runs locally.

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

Configure MySQL credentials:

```bash
EDITOR=vim bin/rails credentials:edit
```

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

## Run

```bash
bin/dev            # starts Docker, Puma, Sidekiq, Tailwind
```

Open http://localhost:3000

Seed sample data: `bin/rails db:seed`

## Test

```bash
bundle exec rspec
bundle exec rubocop
```

## License

All rights reserved. This is proprietary software. Unauthorized copying, distribution, or use is strictly prohibited.
