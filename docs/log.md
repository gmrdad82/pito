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
- Configured RSpec with FactoryBot, Shoulda Matchers, WebMock
- Pinned Chartkick + Chart.js in importmap
- Wrote CLAUDE.md and README.md
- Verified: Rails boots, RSpec runs (0 examples, 0 failures)

**Decisions:**
- Used mise.toml (not just .ruby-version) because mise had a bug with --path .ruby-version; kept .ruby-version too for compatibility
- Kept solid_queue/solid_cache/solid_cable gems from Rails generator (only used in production config, won't interfere with Sidekiq in dev)
- MySQL uses empty root password for local dev simplicity

---

**Step 2: Craigslist-style layout + top nav + Sidekiq Web** — completed

- Created Craigslist-inspired Tailwind CSS: blue underlined links (#0000cc), dense tables, plain form inputs, small bordered buttons
- Created application layout with top nav: `pito · Dashboard · Channels · Compare · Production · Notes · Settings · Sidekiq`
- Created `nav_link` helper (bold span for current page, link for others)
- Created placeholder controllers and views for all nav pages
- Added Sidekiq::Web with HTTP basic auth from credentials (`sidekiq.username`, `sidekiq.password`)
- Added pry-rails for console
- Fixed CI workflow: MySQL/Redis via GitHub Actions services, test DB creds via env vars
- Split `.env` into `.env.development` and `.env.test` (both gitignored); `.env.example` is committed
- CI has its own env vars defined in the workflow file
- Fixed RSpec force-setting `RAILS_ENV=test` (user has `RAILS_ENV=development` globally)
- database.yml test section reads from env vars first (for CI), falls back to credentials (for local)
- 16 specs, 0 failures

**Decisions:**
- Force `ENV["RAILS_ENV"] = "test"` in rails_helper (not `||=`) because user has RAILS_ENV=development globally
- Sidekiq Web protected with HTTP basic auth via rails credentials, not left open
- CI test job uses env vars for DB config (no master key needed in CI)
- Separate .env.development/.env.test files instead of single .env

---

**Step 3: Models + migrations + encrypted attrs + factories + model specs** — completed

- Created 6 migrations: AppSetting, Channel, Video, VideoStat, Production, Note
- Added 7th migration: `owned` boolean on channels (default false) to distinguish owned channels (with OAuth/private analytics) from public competitor channels (public data only via API key)
- Configured Active Record Encryption (keys in credentials) for: AppSetting.value (deterministic), Channel.oauth_access_token, Channel.oauth_refresh_token
- Model validations: presence, uniqueness (with DB-level unique indexes)
- Enums: Production.status (idea/in_progress/published/archived), Note.kind (idea/log/todo/reference)
- Associations: Channel has_many Videos → has_many VideoStats; Video has_one Production (optional)
- Scopes: Channel.owned, Channel.public_only
- Class methods: AppSetting.get(key), AppSetting.set(key, value)
- Created FactoryBot factories for all 6 models with traits (:owned for Channel, :with_video for Production)
- 45 specs (27 model + 16 navigation + 2 Sidekiq), 0 failures
- Updated layout: "P" logo in header, added footer with © year
- RuboCop clean

**Decisions:**
- `owned` boolean (default false) instead of separate table or STI — simpler, same schema works for both channel types
- AppSetting.value encrypted with `deterministic: true` so we can query by encrypted value (needed for lookups)
- Production belongs_to :video is optional (can plan a production before filming/uploading)
- VideoStat uniqueness scoped to [video_id, date] — one stats row per video per day

---

**Step 4: Settings page for OAuth credentials** — completed

- Built Settings page with form to manage YouTube OAuth config (client_id, client_secret, redirect_uri) via AppSetting
- SettingsController with index (GET) and update (PATCH) actions
- Empty fields don't overwrite existing values (safe partial updates)
- Client secret uses password input type
- Fixed CI: Active Record Encryption keys provided via config when ENV["CI"] is set (no master key needed)
- 7 request specs for settings CRUD + flash messages
- 52 total specs, 0 failures

**Decisions:**
- Single form with all three OAuth fields rather than individual key/value CRUD — simpler UX for a fixed set of settings
- CI encryption keys hardcoded in test.rb behind ENV["CI"] guard — these are throwaway test keys, not real secrets

---

**Step 5: Purge Production, Notes, Compare + nav overhaul** — completed

- Dropped productions and notes tables (reversible down-migration)
- Removed Production, Note models, factories, specs, controllers, views
- Removed Compare controller, view, route
- Removed icon.png and icon.svg (replaced by Pito.png)
- New header: Pito.png logo + "Pito" text (both link to /), nav `Channels · Videos · Settings`
- Removed Dashboard, Compare, Production, Notes, Sidekiq from nav
- Added Videos controller + placeholder view
- Favicon now uses Pito.png
- Removed has_one :production from Video model
- 43 specs, 0 failures

**Decisions:**
- Sidekiq Web stays mounted at /sidekiq with auth but is not linked from anywhere in the UI — admin-only tool
- Logo links to / (Dashboard) with aria-label, no separate Dashboard nav link needed

---

**Step 6: Visual baseline** — completed (also covers Steps 7-8)

- Rewrote `app/assets/tailwind/application.css`: Verdana 12px base, compact headings (14/13/12px), blue links (#0000cc), visited (#551a8b), YouTube red for danger only (#cc0000), muted #555
- Dense tables with zebra rows, plain form inputs with blue focus outline
- Bracketed submit buttons: lowercase bold 13px, no border/background, blue on hover (`[ save ]`)
- Fixed 32px header: Pito.png logo (14px, nudged up 1px for alignment) + bracketed nav `[ Channels ] · [ Videos ] · [ Settings ]`
- Bracketed nav links: underline on text only (brackets/spaces outside `<a>` tag)
- Footer: copyright left, "Version 0.0.1.alpha" right
- Settings form constrained to 480px max-width
- Added `.rubocop.yml` exclusion for `app/assets/**/*` (CSS files were parsed as Ruby)
- 43 specs, 0 failures

**Decisions:**
- Merged Steps 7 (header/nav) and 8 (button style) into Step 6 since the visual overhaul naturally covered all three
- Used `!important` on `.header-logo` to override Tailwind preflight's `height: auto` on images
- Wrapped settings form in constraining div rather than inline style on form (Tailwind preflight interference)
