# pito — Beta Reboot Plan

> Status: draft. Captures the back-to-Rails-8-roots reboot. Tasks are
> atomic (≤5 min each). Check off as you go. Re-open scope only after
> a milestone lands.

## Sign-off

- [x] Drafted — 2026-05-27
- [x] Audited — 2026-05-27

## Status — 2026-05-27

Stopped after P10.4. Plan 1's U0 pre-flight forced us back here for the
gem-install prereqs: (Tailwind install + scan paths) — done as Plan 1 U0
  prereq.** Tailwind 4.x via `tailwindcss-rails` 4.4.0. Scan paths
  expressed as `@source "../../views"` + `@source "../../components"`
  in `app/assets/tailwind/application.css` (TW4 inline-CSS config,
  no `tailwind.config.js`). `bin/rails tailwindcss:install` couldn't
  patch the existing `application.html.erb` (pre-reboot xterm layout
  is still in place; the installer's anchor wasn't there). Plan 1 U2
  rewrites that layout from scratch, so the missed insert is moot.
- **P9.5–P9.7 (palette, font stack, body type rules) — superseded by
  `docs/plan-beta-reboot-01-ui.md`** (Plan 1 supplies the exhaustive
  token set + the 16px / 1.4 typography lock).
- **P10.1–P10.4 (ViewComponent install + `ApplicationComponent` +
  preview paths) — done as Plan 1 U0 prereq.** view_component 4.11.0.
  Preview path pointed at `spec/components/previews` (not Plan 0's
  `test/components/previews`) because the project is RSpec-only
  post-P3. Initializer uses `preview_paths = [...]` rather than
  `<<` because in view_component 4.x the array is nil at
  application.rb load time.
- **P10.5+ and P11 (component list + web-terminal shell layout) →
  superseded by `docs/plan-beta-reboot-01-ui.md`**.
- **P12–P19** (command router, Cable, auth, locales, Docker, GitHub
  polish, AGENTS.md, docs prune) → deferred to forthcoming
  `plan-beta-reboot-02-*.md` and later.

Unchecked boxes under P11 and P12–P19 are intentionally left as
`[ ]` — they are not abandoned, they have moved.

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

## Complexity hints

Each task carries a `complexity:` hint. The hint signals effort and reasoning depth — pick whichever model fits the tier.

| Hint | When |
|---|---|
| `[manual]` | You, by hand — GitHub UI, credentials, design choices, sketches, smoke tests |
| `[low]` | Renames, deletions, file audits, gemfile edits, locale YAML, single-file refactors, small ViewComponents, basic controllers |
| `[medium]` | Multi-file refactors, command router, ActionCable plumbing, FTS queries |
| `[high]` | Architecture, security, schema audit, command DSL design |

`[manual]` = no agent; you do it. `[low]` is the default workhorse.

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

- [x] T0.1 Create branch `reboot/beta` from `main`. complexity: [manual]
- [x] T0.2 Tag current main as `v0.0.2-pre-reboot`. complexity: [manual]
- [x] T0.3 Copy current Gemfile.lock to `docs/reboot/snapshots/Gemfile.lock.pre`. complexity: [manual]
- [x] T0.4 Copy current schema to `docs/reboot/snapshots/schema.rb.pre`. complexity: [manual]
- [x] T0.5 Dump current `app/` tree to `docs/reboot/snapshots/app-tree.txt`. complexity: [low]
- [x] T0.6 Dump current `config/locales/` tree to `docs/reboot/snapshots/locales-tree.txt`. complexity: [low]
- [x] T0.7 Stop dev services: kill `bin/dev`, `redis`, `meilisearch`, sidekiq workers. complexity: [manual]
- [x] T0.8 Drop dev DB: `bin/rails db:drop`. complexity: [manual]
- [x] T0.9 `docker compose down -v` to wipe Postgres/Redis/Meilisearch volumes. complexity: [manual]

## P1 — Rust CLI removal

- [x] T1.1 Delete `extras/cli/` directory. complexity: [low]
- [x] T1.2 Delete `Cargo.toml` at repo root. complexity: [low]
- [x] T1.3 Delete `Cargo.lock` at repo root. complexity: [low]
- [x] T1.4 Delete `target/` build dir. complexity: [low]
- [x] T1.5 Delete `.deepseek/` (Rust agent dir). complexity: [low]
- [x] T1.6 Delete `docs/tui.md`. complexity: [low]
- [x] T1.7 Remove `Cargo.*` + `extras/cli/**` lines from `.gitignore` + `.dockerignore`. complexity: [low]
- [x] T1.8 Remove `extras/cli` path filter from `.github/workflows/*.yml`. complexity: [low]
- [x] T1.9 Remove "Rust TUI" references from `docs/architecture.md`. complexity: [low]
- [x] T1.10 Remove "TUI" references from `docs/design.md`. complexity: [low]
- [x] T1.11 Remove `rust` row from AGENTS.md skill table. complexity: [low]
- [x] T1.12 Commit: "Rust CLI removal". complexity: [manual]

## P2 — xterm.js + esbuild + node tooling removal

- [x] T2.1 Delete `package.json` + `package-lock.json`. complexity: [low]
- [x] T2.2 Delete `node_modules/`. complexity: [low]
- [x] T2.3 Delete `app/javascript/application.js` (xterm boot). complexity: [low]
- [x] T2.4 Delete `app/assets/builds/`. complexity: [low]
- [x] T2.5 Delete `.prettierrc.json` + `.prettierignore`. complexity: [low]
- [x] T2.6 Delete `bin/build` if present; remove esbuild lines from `Procfile.dev`. complexity: [low]
- [x] T2.7 Update `.gitignore` to remove node_modules + esbuild lines (keep `.wrangler` for Astro). complexity: [low]
- [x] T2.8 Update `.dockerignore` to drop node_modules + builds. complexity: [low]
- [x] T2.9 Commit: "Remove xterm.js experiment". complexity: [manual]

## P3 — Spec body wipe

- [x] T3.1 Empty every file under `spec/models/` (keep file names). complexity: [low]
- [x] T3.2 Empty every file under `spec/services/`. complexity: [low]
- [x] T3.3 Empty every file under `spec/channels/`. complexity: [low]
- [x] T3.4 Empty every file under `spec/requests/`. complexity: [low]
- [x] T3.5 Empty every file under `spec/sidekiq/` (will be deleted in P4). complexity: [low]
- [x] T3.6 Empty every file under `spec/lib/`. complexity: [low]
- [x] T3.7 Reset `spec/rails_helper.rb` to the rspec-rails generator template. complexity: [low]
- [x] T3.8 Reset `spec/spec_helper.rb` to the rspec-rails generator template. complexity: [low]
- [x] T3.9 Empty `spec/support/` factories/helpers (keep dir). complexity: [low]
- [x] T3.10 `bundle exec rspec` should report 0 examples, 0 failures. complexity: [manual]
- [x] T3.11 Commit: "Wipe specs and reset Rspec". complexity: [manual]

## P4 — Sidekiq → SolidQueue

- [x] T4.1 Remove `sidekiq` + `sidekiq-cron` from Gemfile. complexity: [low]
- [x] T4.2 Add `gem "solid_queue"` to Gemfile. complexity: [low]
- [x] T4.3 `bundle install`. complexity: [manual]
- [x] T4.4 Run `bin/rails solid_queue:install`. complexity: [manual]
- [x] T4.5 Delete `config/sidekiq.yml` + `config/sidekiq_cron.yml` + `config/initializers/sidekiq.rb`. complexity: [low]
- [x] T4.6 Delete `app/sidekiq/` directory (middleware + folders). complexity: [low]
- [x] T4.7 In `config/application.rb`, set `config.active_job.queue_adapter = :solid_queue`. complexity: [low]
- [x] T4.8 Remove sidekiq mount + auth from `config/routes.rb`. complexity: [low]
- [x] T4.9 Strip `include Sidekiq::Job` / `sidekiq_options` from every file under `app/jobs/**`; ensure each inherits `ApplicationJob`. complexity: [medium]
- [x] T4.10 Audit `app/jobs/` and `app/services/**` for `.perform_async` / `Sidekiq::Stats` / `Sidekiq::Cron` references; replace `.perform_async` with `.perform_later`. complexity: [medium]
- [x] T4.11 Migrate cron entries from `sidekiq_cron.yml` into `config/recurring.yml` (SolidQueue syntax). complexity: [medium]
- [x] T4.12 Update `Procfile.dev`: drop `worker: sidekiq`, no replacement needed (SolidQueue runs in Puma in dev). complexity: [low]
- [x] T4.13 Re-create dev DB: `bin/rails db:create db:migrate` + load SolidQueue tables. complexity: [manual]
- [x] T4.14 Smoke test: enqueue one job, confirm SolidQueue picks it up. complexity: [manual]
- [x] T4.15 Commit: `[skipci] sidekiq → solid_queue migration` (combined with P3 wipe in commit). complexity: [manual]

## P5 — Redis → SolidCache + SolidCable

- [x] T5.1 Remove `gem "redis"` from Gemfile. complexity: [low]
- [x] T5.2 Add `gem "solid_cache"` + `gem "solid_cable"` to Gemfile. complexity: [low]
- [x] T5.3 `bundle install`. complexity: [manual]
- [x] T5.4 Run `bin/rails solid_cache:install` and `solid_cable:install`. complexity: [manual]
- [x] T5.5 Rewrite `config/cable.yml` to use the `solid_cable` adapter. complexity: [low]
- [x] T5.6 `config/cache.yml` already wired for solid_cache (cache.yml was generated earlier). complexity: [low]
- [x] T5.7 `config/environments/production.rb` already has `config.cache_store = :solid_cache_store`. complexity: [low]
- [x] T5.8 Remove any remaining `Redis.new` / `Redis.current` references in `app/`. complexity: [medium]
- [x] T5.9 Remove Redis service from `docker-compose.yml`. complexity: [low]
- [x] T5.10 Remove Redis volume + healthcheck blocks. complexity: [low]
- [x] T5.11 Remove `REDIS_*` env vars from `.env.example`, `.env.development`, `.env.test`. complexity: [low]
- [x] T5.12 `bin/rails db:migrate` + load cache/cable schemas. complexity: [manual]
- [x] T5.13 Smoke test: `Rails.cache.write/read`; broadcast on a test cable channel. complexity: [manual]
- [x] T5.14 Commit: drop redis; solid_cache + solid_cable. complexity: [manual]

## P6 — Gem cull

- [x] T6.1 Remove `meilisearch` from Gemfile. complexity: [low]
- [x] T6.2 Remove `doorkeeper` from Gemfile. complexity: [low]
- [x] T6.3 Remove `mcp` from Gemfile. complexity: [low]
- [x] T6.4 Remove `chartkick` from Gemfile. complexity: [low]
- [x] T6.5 Remove `groupdate` from Gemfile. complexity: [low]
- [x] T6.6 Remove `aasm` from Gemfile. complexity: [low]
- [x] T6.7 Remove `friendly_id` from Gemfile. complexity: [low]
- [x] T6.8 Remove `commonmarker` from Gemfile. complexity: [low]
- [x] T6.9 Remove `dotenv-rails` from Gemfile. complexity: [low]
- [x] T6.10 Remove `pry-rails` from Gemfile (keep `debug` only). complexity: [low]
- [x] T6.11 Remove `google-apis-youtube_analytics_v2` from Gemfile (analytics out of v1 scope). complexity: [low]
- [x] T6.12 Keep: `jbuilder`, `rack-attack`, `image_processing`, `ruby-vips`, `neighbor`, `rotp`, `rqrcode`, `omniauth-*`, `google-apis-youtube_v3`. complexity: [manual]
- [x] T6.13 Delete `config/initializers/doorkeeper*.rb`. complexity: [low]
- [x] T6.14 Delete `config/initializers/friendly_id.rb`. complexity: [low]
- [x] T6.15 Remove `use_doorkeeper` + OAuth registration routes from `config/routes.rb`. complexity: [low]
- [x] T6.16 Delete `app/controllers/oauth/` + `app/controllers/well_known_controller.rb`. complexity: [low]
- [x] T6.17 No Meilisearch imports in Voyage services (clean). complexity: [medium]
- [x] T6.18 Search `app/` for removed-gem symbols; remove or stub. complexity: [medium]
- [x] T6.19 `bundle install`; ensure `bin/rails runner "puts 1"` boots. complexity: [manual]
- [x] T6.20 Commit: gem cull. complexity: [manual]

## P7 — Model + schema audit & rebuild

> The dev DB is already dropped. We rebuild the schema from a single
> "beta" migration after the audit.

- [x] T7.1 Produce a model audit table at `docs/reboot/model-audit.md`: every model in `app/models/` + columns of intent {keep, drop, defer}. complexity: [high]
- [x] T7.2 Review the audit by hand; lock keep/drop per row. complexity: [manual]
- [x] T7.3 Delete every model file flagged "drop" (TotpBackupCode stays — backups are still useful). complexity: [low]
- [x] T7.4 Delete every concern under `app/models/concerns/` no longer referenced. complexity: [low]
- [x] T7.5 Delete every decorator under `app/decorators/` no longer referenced. complexity: [low]
- [x] T7.6 Delete every policy under `app/policies/` (single-user app, no policies for v1). complexity: [low]
- [x] T7.7 Wipe `db/migrate/` entirely. complexity: [low]
- [x] T7.8 Generate one fresh migration `20260526000000_beta_baseline.rb` covering every kept table (Channel, Video, Game, Footage, CalendarEntry, SavedView, AppSetting, Session, ApiToken, AppSetting, ChannelDaily, VideoDaily, GameGenre, GameDeveloper, GamePublisher, Genre, YoutubeConnection, etc.). Include pgvector + pg_trgm + tsvector extensions. complexity: [high]
- [x] T7.9 Verify schema by `bin/rails db:setup`. complexity: [manual]
- [x] T7.10 Commit: `[skipci] schema baseline; drop obsolete models`. complexity: [manual]

## P8 — PostgreSQL search (FTS + trigram)

- [x] T8.1 In baseline migration, enable extensions: `pg_trgm`, `unaccent`. (pgvector already enabled.) complexity: [low]
- [x] T8.2 Add `tsvector` column `games.search_vector` populated from `title || ' ' || summary`. complexity: [low]
- [x] T8.3 Add GIN index on `games.search_vector`. complexity: [low]
- [x] T8.4 Add `tsvector` column `videos.search_vector` populated from `title || ' ' || description`. complexity: [low]
- [x] T8.5 Add GIN index on `videos.search_vector`. complexity: [low]
- [x] T8.6 Add trigram GIN index on `games.title` (`gin_trgm_ops`). complexity: [low]
- [x] T8.7 Add trigram GIN index on `videos.title` (`gin_trgm_ops`). complexity: [low]
- [x] T8.8 Build `app/queries/pito/search/games_query.rb`: scope `by_text`, `by_genre`. complexity: [medium]
- [x] T8.9 Build `app/queries/pito/search/videos_query.rb`: scope `by_text`, `by_genre_via_game_link`. complexity: [medium]
- [x] T8.10 Helper `Pito::Search.matches(column, query)` to produce a safe `@@ plainto_tsquery` clause. complexity: [low]
- [ ] T8.11 Smoke specs deferred to revisit later (per P3 wipe). complexity: [manual]
- [x] T8.12 Commit: `[skipci] postgres fts + pg_trgm search`. complexity: [manual]

## P9 — Asset pipeline & Tailwind

> T9.1–T9.4 done as Plan 1 U0 prereq (see Status block at top).
> T9.5–T9.7 superseded by `plan-beta-reboot-01-ui.md` U1–U2.
> T9.8–T9.9 dropped — verification + commit folded into U0/U1 of Plan 1.

- [x] T9.1 Add `gem "tailwindcss-rails"` to Gemfile. complexity: [low]
- [x] T9.2 `bundle install`. complexity: [manual]
- [x] T9.3 `bin/rails tailwindcss:install`. complexity: [manual]
- [x] T9.4 Configure tailwind to scan `app/views/**/*` + `app/components/**/*`. complexity: [low]
- [ ] T9.5 Set Tokyo Night palette as CSS custom properties. complexity: [low]
- [ ] T9.6 Pick monospace stack: `ui-monospace, "Cascadia Code", "JetBrains Mono", Menlo, Consolas, monospace`. complexity: [manual]
- [ ] T9.7 Set `body { font-family: <stack>; font-size: 13px; line-height: 1; }`. complexity: [low]
- [ ] T9.8 Verify `bin/dev` runs Rails + Tailwind watcher. complexity: [low]
- [ ] T9.9 Commit: `[skipci] tailwind via tailwindcss-rails; tokyo night palette`. complexity: [manual]

## P10 — ViewComponent baseline

> T10.1–T10.4 done as Plan 1 U0 prereq (see Status block at top).
> Note: T10.4 wired `spec/components/previews` instead of
> `test/components/previews` (RSpec-only project), and used
> `preview_paths = [...]` instead of `<<` (vc 4.x array is nil at
> application.rb load time).
> T10.5–T10.13 superseded by `plan-beta-reboot-01-ui.md` U3–U5.

- [x] T10.1 Add `gem "view_component"` to Gemfile. complexity: [low]
- [x] T10.2 `bundle install`. complexity: [manual]
- [x] T10.3 Create `app/components/` directory; add `ApplicationComponent < ViewComponent::Base`. complexity: [low]
- [x] T10.4 Wire `config.view_component.preview_paths << "test/components/previews"`. complexity: [low]
- [ ] T10.5 Create `app/components/pito/shell/header_component.{rb,html.erb}`. complexity: [low]
- [ ] T10.6 Create `app/components/pito/shell/footer_component.{rb,html.erb}`. complexity: [low]
- [ ] T10.7 Create `app/components/pito/shell/scrollback_component.{rb,html.erb}` (renders a stream of event partials). complexity: [medium]
- [ ] T10.8 Create `app/components/pito/shell/input_component.{rb,html.erb}` (slash-command input). complexity: [medium]
- [ ] T10.9 Create `app/components/pito/event/text_line_component.{rb,html.erb}`. complexity: [low]
- [ ] T10.10 Create `app/components/pito/event/table_component.{rb,html.erb}` (unicode borders). complexity: [medium]
- [ ] T10.11 Create `app/components/pito/event/error_component.{rb,html.erb}`. complexity: [low]
- [ ] T10.12 Create `app/components/pito/event/progress_component.{rb,html.erb}` (░▒▓█ fill). complexity: [low]
- [ ] T10.13 Commit: `[skipci] view_component baseline + shell + event primitives`. complexity: [manual]

## P11 — UI shell: web terminal layout

> Superseded by `plan-beta-reboot-01-ui.md` U2 + U6. Do not execute tasks below.

- [ ] T11.1 Reset `app/views/layouts/application.html.erb` to: header + scrollback + input, monospace, Tokyo Night bg. complexity: [medium]
- [ ] T11.2 Route `root "terminal#show"`. complexity: [low]
- [ ] T11.3 Generate `TerminalController` with `#show` rendering `Pito::Shell::ScrollbackComponent.new(events: [])`. complexity: [low]
- [ ] T11.4 Static "welcome" event on first load (one line: `pito v0.1.0 — type /help to begin`). complexity: [low]
- [ ] T11.5 Stimulus controller `terminal_input_controller.js` — ENTER submits, history via ↑/↓, no mouse handling. complexity: [medium]
- [ ] T11.6 Stimulus controller `terminal_scroll_controller.js` — autoscroll to bottom on append. complexity: [low]
- [ ] T11.7 Add Turbo Streams + Action Cable cable source for the terminal channel. complexity: [low]
- [ ] T11.8 CSS: no border-radius; 1px hairlines; Tokyo Night accent for action chrome. complexity: [low]
- [ ] T11.9 Manual smoke test: `bin/dev`, visit `/`, see prompt. complexity: [manual]
- [ ] T11.10 Commit: `[skipci] web terminal shell scaffold`. complexity: [manual]

## P12 — Command router + handler registry

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T12.1 `lib/pito/command/router.rb`: `Router.parse("/games genre rpg") => Pito::Command::Invocation`. complexity: [medium]
- [ ] T12.2 `lib/pito/command/invocation.rb`: value object with `verb`, `subject`, `args`, `kwargs`. complexity: [low]
- [ ] T12.3 `lib/pito/command/registry.rb`: maps `(verb, subject)` to handler class. complexity: [medium]
- [ ] T12.4 `lib/pito/command/handler.rb`: base class with `call(invocation, broadcaster:)`. complexity: [medium]
- [ ] T12.5 Handler `Pito::Command::Help`: `/help` -> table of registered commands. complexity: [low]
- [ ] T12.6 Handler `Pito::Command::Channels::Stats`: `/channels stats today` -> table. complexity: [medium]
- [ ] T12.7 Handler `Pito::Command::Videos::Show`: `/video <id>` -> details block. complexity: [low]
- [ ] T12.8 Handler `Pito::Command::Videos::Publish`: `/video <id> publish` -> enqueues SolidQueue job. complexity: [medium]
- [ ] T12.9 Handler `Pito::Command::Videos::Schedule`: `/video <id> schedule for <when>` -> parses via `Time.zone.parse`. complexity: [medium]
- [ ] T12.10 Handler `Pito::Command::Games::ByGenre`: `/games genre rpg` -> uses `Pito::Search::GamesQuery#by_genre`. complexity: [low]
- [ ] T12.11 Handler `Pito::Command::Videos::ByGenre`: `/videos genre rpg` -> joins via VideoGameLink. complexity: [medium]
- [ ] T12.12 Controller `CommandsController#create` POST /commands -> Router -> Registry -> Handler. complexity: [medium]
- [ ] T12.13 Error path: unknown verb -> `Pito::Command::Errors::Unknown` -> renders `ErrorComponent`. complexity: [low]
- [ ] T12.14 Form on terminal page POSTs to `/commands` with Turbo. complexity: [low]
- [ ] T12.15 Commit: `[skipci] command router + registry + first 7 handlers`. complexity: [manual]

## P13 — Action Cable streaming

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T13.1 Generate `Pito::TerminalChannel < ApplicationCable::Channel` streaming from `"pito:terminal:#{session_id}"`. complexity: [low]
- [ ] T13.2 `Pito::Stream::Broadcaster.new(session_id:).emit(event_component)` -> renders component, broadcasts as Turbo Stream append. complexity: [medium]
- [ ] T13.3 Wire each handler to receive a `broadcaster` and emit one event per output unit. complexity: [medium]
- [ ] T13.4 `Pito::Stream::Echo`: command itself echoed back as the first event. complexity: [low]
- [ ] T13.5 `Pito::Stream::Spinner`: optional in-progress indicator; cleared on finish. complexity: [medium]
- [ ] T13.6 Confirm `pin "@hotwired/turbo-rails"` in `config/importmap.rb`. complexity: [low]
- [ ] T13.7 Smoke test: type `/help`, see streamed table appear without page refresh. complexity: [manual]
- [ ] T13.8 Commit: `[skipci] action cable streaming pipeline`. complexity: [manual]

## P14 — Auth reset (TOTP + Google YouTube OAuth)

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T14.1 Delete `app/controllers/sessions_controller.rb` + `app/views/sessions/` (if any). complexity: [low]
- [ ] T14.2 Delete `app/controllers/login/` namespace. complexity: [low]
- [ ] T14.3 Delete `app/lib/sessions/` + `app/lib/session_throttle.rb` (rebuild minimal). complexity: [low]
- [ ] T14.4 Delete `config/initializers/sessions_dummy_bcrypt.rb`. complexity: [low]
- [ ] T14.5 Delete `config/initializers/auth_audit_logger.rb`. complexity: [low]
- [ ] T14.6 Generate a fresh `SessionsController` with: `new` (TOTP form), `create` (verify TOTP), `destroy`. complexity: [medium]
- [ ] T14.7 Generate `Pito::Auth::Totp` service: holds the shared secret from credentials, verifies a 6-digit code. complexity: [medium]
- [ ] T14.8 Routes: `get/post "/login"`, `delete "/session"`. complexity: [low]
- [ ] T14.9 Add `before_action :require_login` to `ApplicationController`; skip on `SessionsController`. complexity: [low]
- [ ] T14.10 Persist login in `cookies.signed.permanent[:pito_session]` (single-user, no DB session row needed). complexity: [medium]
- [ ] T14.11 Keep `omniauth-google-oauth2` + `omniauth-rails_csrf_protection`; rebuild `config/initializers/omniauth.rb` minimally for YouTube scope. complexity: [medium]
- [ ] T14.12 Routes for YouTube connect: `match "/auth/google/callback" ...`. complexity: [low]
- [ ] T14.13 `YoutubeConnections::OauthCallbacksController` stores tokens on `YoutubeConnection`. complexity: [medium]
- [ ] T14.14 Slash command `/auth youtube connect` -> emits URL to the cable stream. complexity: [low]
- [ ] T14.15 Slash command `/auth status` -> shows TOTP status + YouTube connection state. complexity: [low]
- [ ] T14.16 Commit: `[skipci] auth: totp login + youtube oauth connect`. complexity: [manual]

## P15 — Locales reset

> Deferred to `plan-beta-reboot-02-*.md` (or later). UI-scoped i18n is handled by `plan-beta-reboot-01-ui.md` U10; broader locales reset (commands, errors, keybindings, domain copy) waits. Do not execute tasks below.

- [ ] T15.1 Delete every file under `config/locales/` except `en.yml`. complexity: [low]
- [ ] T15.2 Reset `en.yml` to the Rails 8 generator stub. complexity: [low]
- [ ] T15.3 Create `config/locales/keybindings/en.yml` with at minimum: `enter`, `escape`, `up`, `down`. complexity: [low]
- [ ] T15.4 Create `config/locales/commands/en.yml` for command help text per verb. complexity: [low]
- [ ] T15.5 Create `config/locales/errors/en.yml` for unknown-verb + parse errors. complexity: [low]
- [ ] T15.6 Create `config/locales/games/en.yml` for game-domain copy. complexity: [low]
- [ ] T15.7 Create `config/locales/videos/en.yml` for video-domain copy. complexity: [low]
- [ ] T15.8 Create `config/locales/channels/en.yml` for channel-domain copy. complexity: [low]
- [ ] T15.9 Enforce: every ViewComponent + handler uses `I18n.t`, no inline strings. complexity: [manual]
- [ ] T15.10 Commit: `[skipci] locales reset; domain + commands + keybindings`. complexity: [manual]

## P16 — Dockerfile + docker-compose + Kamal

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T16.1 Re-generate Dockerfile to Rails 8 default: single-stage build, jemalloc, libvips, postgresql-client. complexity: [medium]
- [ ] T16.2 Drop `BUNDLE_WITHOUT` to also exclude `assets` group (post Tailwind precompile). complexity: [low]
- [ ] T16.3 Confirm `bin/thrust` lives at repo root and is executable. complexity: [manual]
- [ ] T16.4 `docker-compose.yml`: keep `postgres` (pgvector image) + `assets` volume. Drop redis + meilisearch services. complexity: [low]
- [ ] T16.5 Add `PITO_ASSETS_PATH` env var doc to `.env.example`. complexity: [low]
- [ ] T16.6 Verify SolidQueue runs in-process by default in production (puma `before_fork` hook or `solid_queue` setting). complexity: [high]
- [ ] T16.7 `.kamal/secrets`: list `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `YOUTUBE_OAUTH_CLIENT_*`, `VOYAGE_API_KEY`, `TOTP_SHARED_SECRET`. complexity: [manual]
- [ ] T16.8 Update `config/deploy.yml` (Kamal): one service, no worker container, Postgres via `accessory`. complexity: [high]
- [ ] T16.9 `docker build .` succeeds locally. complexity: [manual]
- [ ] T16.10 Commit: `[skipci] dockerfile + compose + kamal for solid-stack`. complexity: [manual]

## P17 — GitHub repo polish

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T17.1 Update GitHub description: `self-hosted YouTube channel management — web terminal, slash commands, Rails 8`. complexity: [manual]
- [ ] T17.2 Update GitHub topics: `rails`, `ruby`, `youtube`, `self-hosted`, `terminal-ui`, `hotwire`, `view-component`, `postgresql`, `pgvector`, `solid-queue`. complexity: [manual]
- [ ] T17.3 Delete obsolete tags (anything pre-`v0.0.2-pre-reboot`) if you want a clean tag list. complexity: [manual]
- [ ] T17.4 Rewrite `README.md`: stack, philosophy, quickstart, license, status. complexity: [medium]
- [ ] T17.5 Default branch protections: require status checks on green. complexity: [manual]
- [ ] T17.6 Confirm no stale `homepage` field pointing to old URLs. complexity: [low]
- [ ] T17.7 Keep `LICENSE` as AGPL-3.0; update README reference. complexity: [manual]
- [ ] T17.8 Commit: `[skipci] readme + github metadata refresh`. complexity: [manual]

## P18 — AGENTS.md as the single skill source of truth

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

> AGENTS.md replaces `docs/skills/`. Every convention lives here. Each
> section is short, opinionated, and references file paths so agents
> don't drift.

- [ ] T18.1 Add section: `## Rails conventions` (controllers, routes, error handling, request specs deferred). complexity: [medium]
- [ ] T18.2 Add section: `## Ruby conventions` (Style: rubocop-rails-omakase, 2-space indent, `# frozen_string_literal: true`, prefer keyword args). complexity: [low]
- [ ] T18.3 Add section: `## PostgreSQL conventions` (snake_case columns, FK constraints required, every search column has GIN index). complexity: [high]
- [ ] T18.4 Add section: `## UI (ViewComponents) conventions` (one component per visual unit, kwargs, slots over assigns, no inline ERB action chrome, all copy via i18n). complexity: [medium]
- [ ] T18.5 Add section: `## Cable publisher conventions` (every broadcast goes through `Pito::Stream::Broadcaster`, channel name pattern `pito:<resource>:<id>`). complexity: [medium]
- [ ] T18.6 Add section: `## Spec coverage` (RSpec model + request + service specs; component previews instead of view specs; one spec per public method). complexity: [medium]
- [ ] T18.7 Add section: `## Documentation` (docs/ holds architecture, plan, decisions; AGENTS.md holds conventions; chat captures decisions to docs). complexity: [low]
- [ ] T18.8 Add section: `## i18n` (no inline strings, key namespaces per domain, English baseline, future locales additive). complexity: [low]
- [ ] T18.9 Add section: `## Modularization` (`app/components/pito/...`, `lib/pito/command/...`, services under `app/services/<domain>/`, queries under `app/queries/<domain>/`). complexity: [medium]
- [ ] T18.10 Add section: `## Distribution` (single-tenant for now, deploy via Kamal to Hetzner, no gem packaging, no multi-tenant features). complexity: [low]
- [ ] T18.11 Add section: `## Slash command grammar` (`/<verb> <subject> [args...]`, all verbs in `lib/pito/command/registry.rb`, every verb has i18n help). complexity: [medium]
- [ ] T18.12 Delete `docs/skills/` directory (its contents now live in AGENTS.md sections above). complexity: [low]
- [ ] T18.13 Commit: `[skipci] AGENTS.md: skill conventions consolidated`. complexity: [manual]

## P19 — docs/ prune & rewrite

> Deferred to `plan-beta-reboot-02-*.md` (or later). Do not execute tasks below.

- [ ] T19.1 Delete `docs/mcp.md`. complexity: [low]
- [ ] T19.2 Delete `docs/tui.md` (already removed in P1; confirm). complexity: [low]
- [ ] T19.3 Rewrite `docs/architecture.md`: topology = Rails + Postgres + Astro site; remove Rust + xterm + Sidekiq + Redis + Meilisearch references. complexity: [medium]
- [ ] T19.4 Rewrite `docs/design.md`: keep tokens + terminology; drop TUI-specific sections; describe web terminal UI contract. complexity: [medium]
- [ ] T19.5 Keep `docs/website.md` for Astro site notes. complexity: [manual]
- [ ] T19.6 Add `docs/decisions.md` for ADR-style notes; first entry: "drop redis", "drop meilisearch", "drop rust cli". complexity: [low]
- [ ] T19.7 Commit: `[skipci] docs: prune to reboot scope`. complexity: [manual]

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
2. Read the `complexity:` hint; pick the cheapest model that fits the tier.
3. Dispatch as a sub-agent OR do by hand.
4. Verify the task did what it says (read the diff, run boot).
5. Check the box. Move on.
6. Commit at the end of each phase using the suggested `[skipci]` title.
