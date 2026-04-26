# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Pito — a single-tenant Rails 8 web app for tracking, analyzing, and managing YouTube activity across multiple channels. Runs locally as a personal tool. Architecture leaves room for future multi-tenancy but does not implement it now.

## Tech Stack

- **Rails 8.1** with Hotwire (Turbo + Stimulus), ERB views, Tailwind CSS
- **MySQL 8** (Docker) — primary datastore, utf8mb4
- **Redis 7** (Docker) — Sidekiq queue + Rails cache store
- **Sidekiq** + **sidekiq-cron** for background jobs
- **Chartkick + Groupdate + Chart.js** for charts
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
- Commit with meaningful 1-line messages. No Co-Authored-By, no multi-line bodies, no AI authoring mentions.
- Always push immediately after committing. Always pull with --rebase.
- Do NOT commit until user has tested and validated the changes.
- Git workflow: feature branches (step-XX) → PR into main. No direct work on main.
- After each build step: update `docs/plan.md` (mark done), append to `docs/log.md`.
- Every step must include RSpec specs. Provide manual testing instructions in conversation, not in files.

## Build Tracking

- **`docs/plan.md`** — build plan with checkboxes
- **`docs/log.md`** — chronological session log (what was done, decisions made)

## Configuration Strategy

- `.env.development` / `.env.test` — per-environment infrastructure connection info ONLY (host/port for MySQL, Redis URL). No secrets. Gitignored.
- `.env.example` — template for the above. Committed.
- `rails credentials:edit` — MySQL database/username/password per environment, Sidekiq web auth, Active Record Encryption keys.
- `config/master.key` — on disk, gitignored. Never in .env.
- CI uses its own env vars defined in `.github/workflows/ci.yml` (no master key needed).
- `AppSetting` table — YouTube OAuth config (client_id, client_secret, redirect_uri), max_panes, max_concurrent_uploads. Managed via web UI.
- Per-channel OAuth tokens stored encrypted on Channel rows.

## Visual Style

Craigslist / 2000s tool aesthetic with modern build:
- **Font:** Verdana 12px base, line-height 1.4
- **Colors:** white bg (#fff), text #1a1a1a, links blue (#0000cc), danger/destructive YouTube red (#cc0000), muted #555, borders #ddd
- **Bracketed link convention:** all links wrapped in `[ ]` — e.g. `[ Channels ] · [ Videos ]`
- **Layout:** full width, compact spacing, no shadows/gradients/rounded corners, no icon fonts (HTML entities only)
- **Header:** fixed, Pito.png logo + "Pito" + nav links, 32px height
- **Navigation:** `[ Channels ] · [ Videos ] · [ Settings ]` — logo/name link to Dashboard
- **Sidekiq Web** at /sidekiq with HTTP basic auth, no link in nav or Settings

## Architecture Notes

- YouTube API calls isolated in service objects under `app/services/youtube/`
- All YouTube config is web-managed (AppSetting + Channel encrypted attrs) — no YouTube secrets in env/credentials
- Channel.connected boolean distinguishes channels with active OAuth from locally-added public channels
- Workspace model: Channels and Videos pages are multi-pane workspaces (up to max_panes side-by-side)
- Picker pages (no panes) with bulk mode for multi-select operations
- SavedView persists workspace URLs for quick restore
- Single-tenant now, architecture leaves room for multi-tenant later

## Project Docs (pre-Rails, in _temp/)

Original planning docs moved to `_temp/` during Rails setup. Contains channel profiles, style guides, workflow docs, and skills overview to be integrated into the app later.
