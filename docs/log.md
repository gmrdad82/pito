# Log

## 2026-04-26

### Session 1

**Step 1: Rails app foundation** — completed

- Moved original planning docs (channels, workflows, skills) to `_temp/`
- Installed Ruby 3.4.9 via mise (mise.toml + .ruby-version)
- Generated Rails 8.1.3 app in repo root: `rails new . --skip-test --database=mysql --css=tailwind`
- Configured Gemfile: Sidekiq, sidekiq-cron, Redis, Chartkick, Groupdate, google-apis-youtube_v3, google-apis-youtube_analytics_v2, dotenv-rails, RSpec, FactoryBot, Faker, Shoulda Matchers, WebMock, RuboCop rails-omakase
- Configured database.yml: utf8mb4 encoding, host/port from .env, credentials from rails credentials:edit
- Created docker-compose.yml: MySQL 8 (port 3307) + Redis 7 (port 6380) with healthchecks
- Created .env.example with MYSQL_HOST, MYSQL_PORT, REDIS_URL
- Rewrote bin/dev: checks Docker, starts/waits for Compose services, then runs Foreman (Puma + Sidekiq + Tailwind)
- Configured Sidekiq initializer with Redis URL, sidekiq-cron loader, cron schedule file (jobs commented until Step 6)
- Set Redis as cache store in development
- Set Sidekiq as Active Job queue adapter
- Mounted Sidekiq::Web at /sidekiq in routes
- Configured RSpec with FactoryBot, Shoulda Matchers, WebMock
- Pinned Chartkick + Chart.js in importmap
- Wrote CLAUDE.md and README.md
- Verified: Rails boots, RSpec runs (0 examples, 0 failures)

**Decisions:**
- Used mise.toml (not just .ruby-version) because mise had a bug with --path .ruby-version; kept .ruby-version too for compatibility
- Kept solid_queue/solid_cache/solid_cable gems from Rails generator (only used in production config, won't interfere with Sidekiq in dev)
- MySQL uses empty root password for local dev simplicity
