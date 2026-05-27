# pito — Beta Reboot Plan

> Status: draft. Captures the back-to-Rails-8-roots reboot. Tasks are
> atomic (≤5 min each). Check off as you go. Re-open scope only after
> a milestone lands.

## Sign-off

- [x] Drafted — 2026-05-27
- [x] Audited — 2026-05-27

## North star

Pito returns to Rails 8 defaults. One self-hosted Rails app, single-user,
JSON + HTML hybrid via Hotwire. The UI is an OpenCode-style **web terminal**:
monospace, slash commands, streamed responses over Turbo Streams + Action
Cable. No Rust client. No npm/node. No Redis. No Meilisearch.

Models survive in spirit; the schema is rebuilt from scratch (no real data
yet). Specs are wiped clean and revisited later. Voyage AI stays for
recommendations. PostgreSQL handles search via `to_tsvector` + `pg_trgm`.

## Locked decisions

| Topic | Decision |
|---|---|
| UI stack | Turbo + Stimulus + importmap-rails (zero node) |
| CSS | tailwindcss-rails (standalone CLI, zero node) |
| Components | `view_component` gem, no Lookbook |
| Jobs | SolidQueue (Postgres) |
| Cache | SolidCache (Postgres) |
| Cable | SolidCable (Postgres) |
| Redis | dropped entirely |
| Search | PostgreSQL FTS (`to_tsvector`) + `pg_trgm` |
| Vectors | `neighbor` + pgvector (Voyage embeddings) |
| Auth | TOTP-only (rotp + rqrcode), single user (me) |
| YouTube | omniauth-google-oauth2 + omniauth-rails_csrf_protection |
| Test framework | RSpec retained, all specs wiped |
| Image variants | image_processing + ruby-vips kept |
| Rust CLI | deleted |
| Astro site | kept (extras/website/) |
| Streaming | Turbo Streams over Action Cable |
| i18n | All copy + keybindings in `config/locales/**.yml` |
| Brand | `pito` lowercase except sentence start |
| DB | safe to drop and rebuild (dev only, no real data) |

## Model recommendations (cheap-first)

Each task carries a `model:` hint. Pick by complexity, not by feel.

| Hint | Suggested model | When |
|---|---|---|
| `[manual]` | you, by hand | GitHub UI, credentials, design choices, sketches |
| `[flash]` | DeepSeek V4 Flash / Gemini 2.0 Flash / GPT-4o-mini | Renames, deletions, file audits, gemfile edits, locale YAML |
| `[haiku]` | Claude Haiku 3.5 | Single-file refactors, small ViewComponents, basic controllers |
| `[sonnet]` | Claude Sonnet 4 | Multi-file refactors, command router, ActionCable plumbing, FTS queries |
| `[pro]` | DeepSeek V4 Pro / Claude Opus 4 | Architecture, security, schema audit, command DSL design |

`[manual]` = no agent; you do it. `[flash]` is the default workhorse.

## Phase index

- P0 — Pre-flight & snapshots
- P1 — Rust CLI removal
- P2 — xterm.js + esbuild + node tooling removal
- P3 — Spec body wipe
- P4 — Sidekiq → SolidQueue
- P5 — Redis → SolidCache + SolidCable
- P6 — Gem cull (Doorkeeper, MCP, Meilisearch, et al.)
- P7 — Model + schema audit & rebuild
- P8 — PostgreSQL search (FTS + trigram)
- P9 — Asset pipeline & Tailwind
- P10 — ViewComponent baseline
- P11 — UI shell: web terminal layout
- P12 — Command router + handler registry
- P13 — Action Cable streaming
- P14 — Auth reset (TOTP + Google YouTube OAuth)
- P15 — Locales reset
- P16 — Dockerfile + docker-compose + Kamal
- P17 — GitHub repo polish (README, description, topics, tags)
- P18 — AGENTS.md as the single skill source of truth
- P19 — docs/ prune & rewrite

---

## P0 — Pre-flight & snapshots

- [x] T0.1 Create branch `reboot/beta` from `main`. model: [manual]
- [x] T0.2 Tag current main as `v0.0.2-pre-reboot`. model: [manual]
- [x] T0.3 Copy current Gemfile.lock to `docs/reboot/snapshots/Gemfile.lock.pre`. model: [manual]
- [x] T0.4 Copy current schema to `docs/reboot/snapshots/schema.rb.pre`. model: [manual]
- [x] T0.5 Dump current `app/` tree to `docs/reboot/snapshots/app-tree.txt`. model: [flash]
- [x] T0.6 Dump current `config/locales/` tree to `docs/reboot/snapshots/locales-tree.txt`. model: [flash]
- [x] T0.7 Stop dev services: kill `bin/dev`, `redis`, `meilisearch`, sidekiq workers. model: [manual]
- [x] T0.8 Drop dev DB: `bin/rails db:drop`. model: [manual]
- [x] T0.9 `docker compose down -v` to wipe Postgres/Redis/Meilisearch volumes. model: [manual]

## P1 — Rust CLI removal

- [x] T1.1 Delete `extras/cli/` directory. model: [flash]
- [x] T1.2 Delete `Cargo.toml` at repo root. model: [flash]
- [x] T1.3 Delete `Cargo.lock` at repo root. model: [flash]
- [x] T1.4 Delete `target/` build dir. model: [flash]
- [x] T1.5 Delete `.deepseek/` (Rust agent dir). model: [flash]
- [x] T1.6 Delete `docs/tui.md`. model: [flash]
- [x] T1.7 Remove `Cargo.*` + `extras/cli/**` lines from `.gitignore` + `.dockerignore`. model: [flash]
- [x] T1.8 Remove `extras/cli` path filter from `.github/workflows/*.yml`. model: [flash]
- [x] T1.9 Remove "Rust TUI" references from `docs/architecture.md`. model: [haiku]
- [x] T1.10 Remove "TUI" references from `docs/design.md`. model: [haiku]
- [x] T1.11 Remove `rust` row from AGENTS.md skill table. model: [flash]
- [x] T1.12 Commit: "Rust CLI removal". model: [manual]

## P2 — xterm.js + esbuild + node tooling removal

- [x] T2.1 Delete `package.json` + `package-lock.json`. model: [flash]
- [x] T2.2 Delete `node_modules/`. model: [flash]
- [x] T2.3 Delete `app/javascript/application.js` (xterm boot). model: [flash]
- [x] T2.4 Delete `app/assets/builds/`. model: [flash]
- [x] T2.5 Delete `.prettierrc.json` + `.prettierignore`. model: [flash]
- [x] T2.6 Delete `bin/build` if present; remove esbuild lines from `Procfile.dev`. model: [flash]
- [x] T2.7 Update `.gitignore` to remove node_modules + esbuild lines (keep `.wrangler` for Astro). model: [flash]
- [x] T2.8 Update `.dockerignore` to drop node_modules + builds. model: [flash]
- [x] T2.9 Commit: "Remove xterm.js experiment". model: [manual]

## P3 — Spec body wipe

- [x] T3.1 Empty every file under `spec/models/` (keep file names). model: [flash]
- [x] T3.2 Empty every file under `spec/services/`. model: [flash]
- [x] T3.3 Empty every file under `spec/channels/`. model: [flash]
- [x] T3.4 Empty every file under `spec/requests/`. model: [flash]
- [x] T3.5 Empty every file under `spec/sidekiq/` (will be deleted in P4). model: [flash]
- [x] T3.6 Empty every file under `spec/lib/`. model: [flash]
- [x] T3.7 Reset `spec/rails_helper.rb` to the rspec-rails generator template. model: [haiku]
- [x] T3.8 Reset `spec/spec_helper.rb` to the rspec-rails generator template. model: [haiku]
- [x] T3.9 Empty `spec/support/` factories/helpers (keep dir). model: [flash]
- [x] T3.10 `bundle exec rspec` should report 0 examples, 0 failures. model: [manual]
- [x] T3.11 Commit: "Wipe specs and reset Rspec". model: [manual]

## P4 — Sidekiq → SolidQueue

- [x] T4.1 Remove `sidekiq` + `sidekiq-cron` from Gemfile. model: [flash]
- [x] T4.2 Add `gem "solid_queue"` to Gemfile. model: [flash]
- [x] T4.3 `bundle install`. model: [manual]
- [x] T4.4 Run `bin/rails solid_queue:install`. model: [manual]
- [x] T4.5 Delete `config/sidekiq.yml` + `config/sidekiq_cron.yml` + `config/initializers/sidekiq.rb`. model: [flash]
- [x] T4.6 Delete `app/sidekiq/` directory (middleware + folders). model: [flash]
- [x] T4.7 In `config/application.rb`, set `config.active_job.queue_adapter = :solid_queue`. model: [haiku]
- [x] T4.8 Remove sidekiq mount + auth from `config/routes.rb`. model: [haiku]
- [x] T4.9 Strip `include Sidekiq::Job` / `sidekiq_options` from every file under `app/jobs/**`; ensure each inherits `ApplicationJob`. model: [sonnet]
- [x] T4.10 Audit `app/jobs/` and `app/services/**` for `.perform_async` / `Sidekiq::Stats` / `Sidekiq::Cron` references; replace `.perform_async` with `.perform_later`. model: [sonnet]
- [x] T4.11 Migrate cron entries from `sidekiq_cron.yml` into `config/recurring.yml` (SolidQueue syntax). model: [sonnet]
- [x] T4.12 Update `Procfile.dev`: drop `worker: sidekiq`, no replacement needed (SolidQueue runs in Puma in dev). model: [flash]
- [x] T4.13 Re-create dev DB: `bin/rails db:create db:migrate` + load SolidQueue tables. model: [manual]
- [x] T4.14 Smoke test: enqueue one job, confirm SolidQueue picks it up. model: [manual]
- [x] T4.15 Commit: `[skipci] sidekiq → solid_queue migration` (combined with P3 wipe in commit). model: [manual]

## P5 — Redis → SolidCache + SolidCable

- [x] T5.1 Remove `gem "redis"` from Gemfile. model: [flash]
- [x] T5.2 Add `gem "solid_cache"` + `gem "solid_cable"` to Gemfile. model: [flash]
- [x] T5.3 `bundle install`. model: [manual]
- [x] T5.4 Run `bin/rails solid_cache:install` and `solid_cable:install`. model: [manual]
- [x] T5.5 Rewrite `config/cable.yml` to use the `solid_cable` adapter. model: [haiku]
- [x] T5.6 `config/cache.yml` already wired for solid_cache (cache.yml was generated earlier). model: [haiku]
- [x] T5.7 `config/environments/production.rb` already has `config.cache_store = :solid_cache_store`. model: [haiku]
- [x] T5.8 Remove any remaining `Redis.new` / `Redis.current` references in `app/`. model: [sonnet]
- [x] T5.9 Remove Redis service from `docker-compose.yml`. model: [flash]
- [x] T5.10 Remove Redis volume + healthcheck blocks. model: [flash]
- [x] T5.11 Remove `REDIS_*` env vars from `.env.example`, `.env.development`, `.env.test`. model: [flash]
- [x] T5.12 `bin/rails db:migrate` + load cache/cable schemas. model: [manual]
- [x] T5.13 Smoke test: `Rails.cache.write/read`; broadcast on a test cable channel. model: [manual]
- [x] T5.14 Commit: drop redis; solid_cache + solid_cable. model: [manual]

## P6 — Gem cull

- [x] T6.1 Remove `meilisearch` from Gemfile. model: [flash]
- [x] T6.2 Remove `doorkeeper` from Gemfile. model: [flash]
- [x] T6.3 Remove `mcp` from Gemfile. model: [flash]
- [x] T6.4 Remove `chartkick` from Gemfile. model: [flash]
- [x] T6.5 Remove `groupdate` from Gemfile. model: [flash]
- [x] T6.6 Remove `aasm` from Gemfile. model: [flash]
- [x] T6.7 Remove `friendly_id` from Gemfile. model: [flash]
- [x] T6.8 Remove `commonmarker` from Gemfile. model: [flash]
- [x] T6.9 Remove `dotenv-rails` from Gemfile. model: [flash]
- [x] T6.10 Remove `pry-rails` from Gemfile (keep `debug` only). model: [flash]
- [x] T6.11 Remove `google-apis-youtube_analytics_v2` from Gemfile (analytics out of v1 scope). model: [flash]
- [x] T6.12 Keep: `jbuilder`, `rack-attack`, `image_processing`, `ruby-vips`, `neighbor`, `rotp`, `rqrcode`, `omniauth-*`, `google-apis-youtube_v3`. model: [manual]
- [x] T6.13 Delete `config/initializers/doorkeeper*.rb`. model: [flash]
- [x] T6.14 Delete `config/initializers/friendly_id.rb`. model: [flash]
- [x] T6.15 Remove `use_doorkeeper` + OAuth registration routes from `config/routes.rb`. model: [haiku]
- [x] T6.16 Delete `app/controllers/oauth/` + `app/controllers/well_known_controller.rb`. model: [flash]
- [x] T6.17 No Meilisearch imports in Voyage services (clean). model: [sonnet]
- [x] T6.18 Search `app/` for removed-gem symbols; remove or stub. model: [sonnet]
- [x] T6.19 `bundle install`; ensure `bin/rails runner "puts 1"` boots. model: [manual]
- [-] T6.20 Commit: gem cull. model: [manual]

## P7 — Model + schema audit & rebuild

> The dev DB is already dropped. We rebuild the schema from a single
> "beta" migration after the audit.

- [ ] T7.1 Produce a model audit table at `docs/reboot/model-audit.md`: every model in `app/models/` + columns of intent {keep, drop, defer}. model: [pro]
- [ ] T7.2 Review the audit by hand; lock keep/drop per row. model: [manual]
- [ ] T7.3 Delete every model file flagged "drop" (TotpBackupCode stays — backups are still useful). model: [flash]
- [ ] T7.4 Delete every concern under `app/models/concerns/` no longer referenced. model: [flash]
- [ ] T7.5 Delete every decorator under `app/decorators/` no longer referenced. model: [flash]
- [ ] T7.6 Delete every policy under `app/policies/` (single-user app, no policies for v1). model: [flash]
- [ ] T7.7 Wipe `db/migrate/` entirely. model: [flash]
- [ ] T7.8 Generate one fresh migration `20260526000000_beta_baseline.rb` covering every kept table (Channel, Video, Game, Footage, CalendarEntry, SavedView, AppSetting, Session, ApiToken, AppSetting, ChannelDaily, VideoDaily, GameGenre, GameDeveloper, GamePublisher, Genre, YoutubeConnection, etc.). Include pgvector + pg_trgm + tsvector extensions. model: [pro]
- [ ] T7.9 Verify schema by `bin/rails db:setup`. model: [manual]
- [ ] T7.10 Commit: `[skipci] schema baseline; drop obsolete models`. model: [manual]

## P8 — PostgreSQL search (FTS + trigram)

- [ ] T8.1 In baseline migration, enable extensions: `pg_trgm`, `unaccent`. (pgvector already enabled.) model: [haiku]
- [ ] T8.2 Add `tsvector` column `games.search_vector` populated from `title || ' ' || description`. model: [haiku]
- [ ] T8.3 Add GIN index on `games.search_vector`. model: [haiku]
- [ ] T8.4 Add `tsvector` column `videos.search_vector` populated from `title || ' ' || description`. model: [haiku]
- [ ] T8.5 Add GIN index on `videos.search_vector`. model: [haiku]
- [ ] T8.6 Add trigram GIN index on `games.title` (`gin_trgm_ops`). model: [haiku]
- [ ] T8.7 Add trigram GIN index on `videos.title` (`gin_trgm_ops`). model: [haiku]
- [ ] T8.8 Build `app/queries/pito/search/games_query.rb`: scope `by_text`, `by_genre`. model: [sonnet]
- [ ] T8.9 Build `app/queries/pito/search/videos_query.rb`: scope `by_text`, `by_genre_via_game_link`. model: [sonnet]
- [ ] T8.10 Helper `Pito::Search.tokenize(string)` to escape user input for `to_tsquery`. model: [haiku]
- [ ] T8.11 Smoke specs deferred to revisit later (per P3 wipe). model: [manual]
- [ ] T8.12 Commit: `[skipci] postgres fts + pg_trgm search`. model: [manual]

## P9 — Asset pipeline & Tailwind

- [ ] T9.1 Add `gem "tailwindcss-rails"` to Gemfile. model: [flash]
- [ ] T9.2 `bundle install`. model: [manual]
- [ ] T9.3 `bin/rails tailwindcss:install`. model: [manual]
- [ ] T9.4 Configure tailwind to scan `app/views/**/*` + `app/components/**/*`. model: [haiku]
- [ ] T9.5 Set Tokyo Night palette as CSS custom properties. model: [haiku]
- [ ] T9.6 Pick monospace stack: `ui-monospace, "Cascadia Code", "JetBrains Mono", Menlo, Consolas, monospace`. model: [manual]
- [ ] T9.7 Set `body { font-family: <stack>; font-size: 13px; line-height: 1; }`. model: [haiku]
- [ ] T9.8 Verify `bin/dev` runs Rails + Tailwind watcher. model: [haiku]
- [ ] T9.9 Commit: `[skipci] tailwind via tailwindcss-rails; tokyo night palette`. model: [manual]

## P10 — ViewComponent baseline

- [ ] T10.1 Add `gem "view_component"` to Gemfile. model: [flash]
- [ ] T10.2 `bundle install`. model: [manual]
- [ ] T10.3 Create `app/components/` directory; add `ApplicationComponent < ViewComponent::Base`. model: [haiku]
- [ ] T10.4 Wire `config.view_component.preview_paths << "test/components/previews"`. model: [haiku]
- [ ] T10.5 Create `app/components/pito/shell/header_component.{rb,html.erb}`. model: [haiku]
- [ ] T10.6 Create `app/components/pito/shell/footer_component.{rb,html.erb}`. model: [haiku]
- [ ] T10.7 Create `app/components/pito/shell/scrollback_component.{rb,html.erb}` (renders a stream of event partials). model: [sonnet]
- [ ] T10.8 Create `app/components/pito/shell/input_component.{rb,html.erb}` (slash-command input). model: [sonnet]
- [ ] T10.9 Create `app/components/pito/event/text_line_component.{rb,html.erb}`. model: [haiku]
- [ ] T10.10 Create `app/components/pito/event/table_component.{rb,html.erb}` (unicode borders). model: [sonnet]
- [ ] T10.11 Create `app/components/pito/event/error_component.{rb,html.erb}`. model: [haiku]
- [ ] T10.12 Create `app/components/pito/event/progress_component.{rb,html.erb}` (░▒▓█ fill). model: [haiku]
- [ ] T10.13 Commit: `[skipci] view_component baseline + shell + event primitives`. model: [manual]

## P11 — UI shell: web terminal layout

- [ ] T11.1 Reset `app/views/layouts/application.html.erb` to: header + scrollback + input, monospace, Tokyo Night bg. model: [sonnet]
- [ ] T11.2 Route `root "terminal#show"`. model: [haiku]
- [ ] T11.3 Generate `TerminalController` with `#show` rendering `Pito::Shell::ScrollbackComponent.new(events: [])`. model: [haiku]
- [ ] T11.4 Static "welcome" event on first load (one line: `pito v0.1.0 — type /help to begin`). model: [haiku]
- [ ] T11.5 Stimulus controller `terminal_input_controller.js` — ENTER submits, history via ↑/↓, no mouse handling. model: [sonnet]
- [ ] T11.6 Stimulus controller `terminal_scroll_controller.js` — autoscroll to bottom on append. model: [haiku]
- [ ] T11.7 Add Turbo Streams + Action Cable cable source for the terminal channel. model: [haiku]
- [ ] T11.8 CSS: no border-radius; 1px hairlines; Tokyo Night accent for action chrome. model: [haiku]
- [ ] T11.9 Manual smoke test: `bin/dev`, visit `/`, see prompt. model: [manual]
- [ ] T11.10 Commit: `[skipci] web terminal shell scaffold`. model: [manual]

## P12 — Command router + handler registry

- [ ] T12.1 `lib/pito/command/router.rb`: `Router.parse("/games genre rpg") => Pito::Command::Invocation`. model: [sonnet]
- [ ] T12.2 `lib/pito/command/invocation.rb`: value object with `verb`, `subject`, `args`, `kwargs`. model: [haiku]
- [ ] T12.3 `lib/pito/command/registry.rb`: maps `(verb, subject)` to handler class. model: [sonnet]
- [ ] T12.4 `lib/pito/command/handler.rb`: base class with `call(invocation, broadcaster:)`. model: [sonnet]
- [ ] T12.5 Handler `Pito::Command::Help`: `/help` -> table of registered commands. model: [haiku]
- [ ] T12.6 Handler `Pito::Command::Channels::Stats`: `/channels stats today` -> table. model: [sonnet]
- [ ] T12.7 Handler `Pito::Command::Videos::Show`: `/video <id>` -> details block. model: [haiku]
- [ ] T12.8 Handler `Pito::Command::Videos::Publish`: `/video <id> publish` -> enqueues SolidQueue job. model: [sonnet]
- [ ] T12.9 Handler `Pito::Command::Videos::Schedule`: `/video <id> schedule for <when>` -> parses via `Time.zone.parse`. model: [sonnet]
- [ ] T12.10 Handler `Pito::Command::Games::ByGenre`: `/games genre rpg` -> uses `Pito::Search::GamesQuery#by_genre`. model: [haiku]
- [ ] T12.11 Handler `Pito::Command::Videos::ByGenre`: `/videos genre rpg` -> joins via VideoGameLink. model: [sonnet]
- [ ] T12.12 Controller `CommandsController#create` POST /commands -> Router -> Registry -> Handler. model: [sonnet]
- [ ] T12.13 Error path: unknown verb -> `Pito::Command::Errors::Unknown` -> renders `ErrorComponent`. model: [haiku]
- [ ] T12.14 Form on terminal page POSTs to `/commands` with Turbo. model: [haiku]
- [ ] T12.15 Commit: `[skipci] command router + registry + first 7 handlers`. model: [manual]

## P13 — Action Cable streaming

- [ ] T13.1 Generate `Pito::TerminalChannel < ApplicationCable::Channel` streaming from `"pito:terminal:#{session_id}"`. model: [haiku]
- [ ] T13.2 `Pito::Stream::Broadcaster.new(session_id:).emit(event_component)` -> renders component, broadcasts as Turbo Stream append. model: [sonnet]
- [ ] T13.3 Wire each handler to receive a `broadcaster` and emit one event per output unit. model: [sonnet]
- [ ] T13.4 `Pito::Stream::Echo`: command itself echoed back as the first event. model: [haiku]
- [ ] T13.5 `Pito::Stream::Spinner`: optional in-progress indicator; cleared on finish. model: [sonnet]
- [ ] T13.6 Confirm `pin "@hotwired/turbo-rails"` in `config/importmap.rb`. model: [haiku]
- [ ] T13.7 Smoke test: type `/help`, see streamed table appear without page refresh. model: [manual]
- [ ] T13.8 Commit: `[skipci] action cable streaming pipeline`. model: [manual]

## P14 — Auth reset (TOTP + Google YouTube OAuth)

- [ ] T14.1 Delete `app/controllers/sessions_controller.rb` + `app/views/sessions/` (if any). model: [flash]
- [ ] T14.2 Delete `app/controllers/login/` namespace. model: [flash]
- [ ] T14.3 Delete `app/lib/sessions/` + `app/lib/session_throttle.rb` (rebuild minimal). model: [flash]
- [ ] T14.4 Delete `config/initializers/sessions_dummy_bcrypt.rb`. model: [flash]
- [ ] T14.5 Delete `config/initializers/auth_audit_logger.rb`. model: [flash]
- [ ] T14.6 Generate a fresh `SessionsController` with: `new` (TOTP form), `create` (verify TOTP), `destroy`. model: [sonnet]
- [ ] T14.7 Generate `Pito::Auth::Totp` service: holds the shared secret from credentials, verifies a 6-digit code. model: [sonnet]
- [ ] T14.8 Routes: `get/post "/login"`, `delete "/session"`. model: [haiku]
- [ ] T14.9 Add `before_action :require_login` to `ApplicationController`; skip on `SessionsController`. model: [haiku]
- [ ] T14.10 Persist login in `cookies.signed.permanent[:pito_session]` (single-user, no DB session row needed). model: [sonnet]
- [ ] T14.11 Keep `omniauth-google-oauth2` + `omniauth-rails_csrf_protection`; rebuild `config/initializers/omniauth.rb` minimally for YouTube scope. model: [sonnet]
- [ ] T14.12 Routes for YouTube connect: `match "/auth/google/callback" ...`. model: [haiku]
- [ ] T14.13 `YoutubeConnections::OauthCallbacksController` stores tokens on `YoutubeConnection`. model: [sonnet]
- [ ] T14.14 Slash command `/auth youtube connect` -> emits URL to the cable stream. model: [haiku]
- [ ] T14.15 Slash command `/auth status` -> shows TOTP status + YouTube connection state. model: [haiku]
- [ ] T14.16 Commit: `[skipci] auth: totp login + youtube oauth connect`. model: [manual]

## P15 — Locales reset

- [ ] T15.1 Delete every file under `config/locales/` except `en.yml`. model: [flash]
- [ ] T15.2 Reset `en.yml` to the Rails 8 generator stub. model: [haiku]
- [ ] T15.3 Create `config/locales/keybindings/en.yml` with at minimum: `enter`, `escape`, `up`, `down`. model: [haiku]
- [ ] T15.4 Create `config/locales/commands/en.yml` for command help text per verb. model: [haiku]
- [ ] T15.5 Create `config/locales/errors/en.yml` for unknown-verb + parse errors. model: [haiku]
- [ ] T15.6 Create `config/locales/games/en.yml` for game-domain copy. model: [haiku]
- [ ] T15.7 Create `config/locales/videos/en.yml` for video-domain copy. model: [haiku]
- [ ] T15.8 Create `config/locales/channels/en.yml` for channel-domain copy. model: [haiku]
- [ ] T15.9 Enforce: every ViewComponent + handler uses `I18n.t`, no inline strings. model: [manual]
- [ ] T15.10 Commit: `[skipci] locales reset; domain + commands + keybindings`. model: [manual]

## P16 — Dockerfile + docker-compose + Kamal

- [ ] T16.1 Re-generate Dockerfile to Rails 8 default: single-stage build, jemalloc, libvips, postgresql-client. model: [sonnet]
- [ ] T16.2 Drop `BUNDLE_WITHOUT` to also exclude `assets` group (post Tailwind precompile). model: [haiku]
- [ ] T16.3 Confirm `bin/thrust` lives at repo root and is executable. model: [manual]
- [ ] T16.4 `docker-compose.yml`: keep `postgres` (pgvector image) + `assets` volume. Drop redis + meilisearch services. model: [haiku]
- [ ] T16.5 Add `PITO_ASSETS_PATH` env var doc to `.env.example`. model: [haiku]
- [ ] T16.6 Verify SolidQueue runs in-process by default in production (puma `before_fork` hook or `solid_queue` setting). model: [pro]
- [ ] T16.7 `.kamal/secrets`: list `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `YOUTUBE_OAUTH_CLIENT_*`, `VOYAGE_API_KEY`, `TOTP_SHARED_SECRET`. model: [manual]
- [ ] T16.8 Update `config/deploy.yml` (Kamal): one service, no worker container, Postgres via `accessory`. model: [pro]
- [ ] T16.9 `docker build .` succeeds locally. model: [manual]
- [ ] T16.10 Commit: `[skipci] dockerfile + compose + kamal for solid-stack`. model: [manual]

## P17 — GitHub repo polish

- [ ] T17.1 Update GitHub description: `self-hosted YouTube channel management — web terminal, slash commands, Rails 8`. model: [manual]
- [ ] T17.2 Update GitHub topics: `rails`, `ruby`, `youtube`, `self-hosted`, `terminal-ui`, `hotwire`, `view-component`, `postgresql`, `pgvector`, `solid-queue`. model: [manual]
- [ ] T17.3 Delete obsolete tags (anything pre-`v0.0.2-pre-reboot`) if you want a clean tag list. model: [manual]
- [ ] T17.4 Rewrite `README.md`: stack, philosophy, quickstart, license, status. model: [sonnet]
- [ ] T17.5 Default branch protections: require status checks on green. model: [manual]
- [ ] T17.6 Confirm no stale `homepage` field pointing to old URLs. model: [flash]
- [ ] T17.7 Keep `LICENSE` as AGPL-3.0; update README reference. model: [manual]
- [ ] T17.8 Commit: `[skipci] readme + github metadata refresh`. model: [manual]

## P18 — AGENTS.md as the single skill source of truth

> AGENTS.md replaces `docs/skills/`. Every convention lives here. Each
> section is short, opinionated, and references file paths so agents
> don't drift.

- [ ] T18.1 Add section: `## Rails conventions` (controllers, routes, error handling, request specs deferred). model: [sonnet]
- [ ] T18.2 Add section: `## Ruby conventions` (Style: rubocop-rails-omakase, 2-space indent, `# frozen_string_literal: true`, prefer keyword args). model: [haiku]
- [ ] T18.3 Add section: `## PostgreSQL conventions` (snake_case columns, FK constraints required, every search column has GIN index). model: [pro]
- [ ] T18.4 Add section: `## UI (ViewComponents) conventions` (one component per visual unit, kwargs, slots over assigns, no inline ERB action chrome, all copy via i18n). model: [sonnet]
- [ ] T18.5 Add section: `## Cable publisher conventions` (every broadcast goes through `Pito::Stream::Broadcaster`, channel name pattern `pito:<resource>:<id>`). model: [sonnet]
- [ ] T18.6 Add section: `## Spec coverage` (RSpec model + request + service specs; component previews instead of view specs; one spec per public method). model: [sonnet]
- [ ] T18.7 Add section: `## Documentation` (docs/ holds architecture, plan, decisions; AGENTS.md holds conventions; chat captures decisions to docs). model: [haiku]
- [ ] T18.8 Add section: `## i18n` (no inline strings, key namespaces per domain, English baseline, future locales additive). model: [haiku]
- [ ] T18.9 Add section: `## Modularization` (`app/components/pito/...`, `lib/pito/command/...`, services under `app/services/<domain>/`, queries under `app/queries/<domain>/`). model: [sonnet]
- [ ] T18.10 Add section: `## Distribution` (single-tenant for now, deploy via Kamal to Hetzner, no gem packaging, no multi-tenant features). model: [haiku]
- [ ] T18.11 Add section: `## Slash command grammar` (`/<verb> <subject> [args...]`, all verbs in `lib/pito/command/registry.rb`, every verb has i18n help). model: [sonnet]
- [ ] T18.12 Delete `docs/skills/` directory (its contents now live in AGENTS.md sections above). model: [flash]
- [ ] T18.13 Commit: `[skipci] AGENTS.md: skill conventions consolidated`. model: [manual]

## P19 — docs/ prune & rewrite

- [ ] T19.1 Delete `docs/mcp.md`. model: [flash]
- [ ] T19.2 Delete `docs/tui.md` (already removed in P1; confirm). model: [flash]
- [ ] T19.3 Rewrite `docs/architecture.md`: topology = Rails + Postgres + Astro site; remove Rust + xterm + Sidekiq + Redis + Meilisearch references. model: [sonnet]
- [ ] T19.4 Rewrite `docs/design.md`: keep tokens + terminology; drop TUI-specific sections; describe web terminal UI contract. model: [sonnet]
- [ ] T19.5 Keep `docs/website.md` for Astro site notes. model: [manual]
- [ ] T19.6 Add `docs/decisions.md` for ADR-style notes; first entry: "drop redis", "drop meilisearch", "drop rust cli". model: [haiku]
- [ ] T19.7 Commit: `[skipci] docs: prune to reboot scope`. model: [manual]

---

## Open follow-ups (post-reboot, not in this plan)

- Markdown rendering of streamed output (defer; ASCII + ViewComponents
  suffice today). Add when AI tool integration arrives.
- Analytics screen (`google-apis-youtube_analytics_v2` re-add).
- Notifications + daily digest.
- Calendar + scheduling conflicts.
- Bundles / Footage workflows.
- Multi-locale i18n.
- Lookbook for ViewComponent previews.
- Public OAuth provider (Doorkeeper) if external clients are ever needed.
- Meilisearch revisit IF Postgres FTS turns out insufficient for fuzzy
  multi-field search at scale.

## How to use this plan

1. Pick the next unchecked task in phase order.
2. Read the `model:` hint; pick the cheapest model that fits.
3. Dispatch as a sub-agent OR do by hand.
4. Verify the task did what it says (read the diff, run boot).
5. Check the box. Move on.
6. Commit at the end of each phase using the suggested `[skipci]` title.
