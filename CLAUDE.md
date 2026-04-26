# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Pito — a single-tenant Rails 8 web app for tracking and analyzing YouTube activity across multiple channels. Runs locally as a personal tool.

## Tech Stack

- **Rails 8.1** with Hotwire (Turbo + Stimulus), ERB views, Tailwind CSS
- **MySQL 8** (Docker) — primary datastore
- **Redis 7** (Docker) — Sidekiq queue + Rails cache store
- **Sidekiq** + **sidekiq-cron** for background jobs
- **Chartkick + Groupdate** for charts
- **google-apis-youtube_v3** and **google-apis-youtube_analytics_v2** for YouTube APIs
- **RSpec** with FactoryBot, Faker, Shoulda Matchers, WebMock

## Commands

```bash
bin/setup          # Install deps, start Docker, prepare DB
bin/dev            # Start Docker services + Puma + Sidekiq + Tailwind watcher
bundle exec rspec  # Run test suite
bundle exec rubocop # Lint
```

## Rules

- Never modify files outside this repository folder.
- Commit with meaningful 1-line messages. No AI authoring mentions.
- Always push immediately after committing.
- Do NOT commit until user has tested and validated the changes.
- Git workflow: feature branches → PR into main. No direct work on main.
- After each build step: update `docs/plan.md` (mark done), append to `docs/log.md`, create `docs/testing/step-NN.md` with verification instructions.
- Every step must include RSpec specs and manual testing instructions (browser/console where applicable).

## Build Tracking

- **`docs/plan.md`** — 12-step build plan with checkboxes
- **`docs/log.md`** — chronological session log (what was done, decisions made)
- **`docs/testing/step-NN.md`** — per-step testing/verification instructions

## Configuration Strategy

- `.env.development` / `.env.test` — per-environment infrastructure connection info ONLY (host/port for MySQL, Redis URL). No secrets. Gitignored.
- `.env.example` — template for the above. Committed.
- `rails credentials:edit` — MySQL database/username/password per environment, Sidekiq web auth.
- `config/main.key` — on disk, gitignored. Never in .env.
- CI uses its own env vars defined in `.github/workflows/ci.yml` (no main key needed).
- `AppSetting` table — YouTube OAuth config (client_id, client_secret, redirect_uri). Managed via web UI.
- Per-channel OAuth tokens stored encrypted on Channel rows.

## Visual Style

Craigslist-inspired: white background, black text, blue underlined links (#0000cc), hairline borders, information-dense, no shadows/gradients/rounded corners/big buttons. System sans-serif, 12-14px base.

## Architecture Notes

- YouTube API calls isolated in service objects under `app/services/youtube/`
- All YouTube config is web-managed (AppSetting + Channel encrypted attrs) — no YouTube secrets in env/credentials
- Single-tenant now, architecture leaves room for multi-tenant later
- Sidekiq Web mounted at /sidekiq, protected with HTTP basic auth (credentials: `sidekiq.username`, `sidekiq.password`)

## Project Docs (pre-Rails, in _temp/)

Original planning docs moved to `_temp/` during Rails setup. Contains channel profiles, style guides, workflow docs, and skills overview to be integrated into the app later.
