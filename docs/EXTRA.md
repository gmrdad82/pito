# EXTRA.md (pito)

Project-specific conventions that override the generic guidance in `AGENTS.md`.

## What pito is

A self-hosted YouTube channel management tool for the owner. Runs locally on
plain localhost in development:

- `http://localhost:3027` — Rails app (dev; production host is deploy-time config)
- `pitomd.com` — marketing / landing site in the separate `gmrdad82/pitomd` repo

Production deployment: Hetzner via Kamal.

The app is chat-first: the owner types commands and natural-language queries into
a single chatbox. Slash commands (`/connect`, `/disconnect`, `/login`, `/logout`,
`/help`, `/new`, `/resume`, `/import`, `/edit`, `/connect`) are dispatched through
`Pito::Slash::*`. Plain text is dispatched through `Pito::Chat::*`. All output
arrives as Turbo Stream events on the scrollback.

Purpose: mirror YouTube channel data locally, stage and publish video edits
without leaving the terminal, and surface game/channel/scheduling recommendations.
YouTube Studio remains the upload tool (videos drafted there). pito provides
cross-channel analytics, scheduling, and recommendation systems.

## Canonical references (read these before starting non-trivial work)

- `docs/architecture.md` — system topology, models, dispatch pipeline, cable, job model, namespaces.
- `docs/design.md` — visual contract, keybindings, terminology, brand caps, accent groups, terminal-aesthetic rules.

## Canonical namespace policy

Cross-cutting concerns live under `Pito::*` unless a screen or domain claims
them. Data-source integrations are claimed by the domain they feed.

- **`Pito::*`** — cross-cutting infrastructure: `ActionRegistry`, `ActionDispatcher`,
  `CableBroadcaster`, `Theme`, `GitRevision`, `Auth::*`, `Formatter::*`,
  `Notifications::*`, `Search::*`, `Calendar::*`, `Analytics::*`,
  `Recommendation::*`, `ExternalApiTracker::*`, `Schedule::*`, plus
  single-purpose utilities (`SlugBuilder`, `TimeZone`, `PublicHosts`, `SafeEach`).
- **Home** has no `Home::*` namespace — its services live under `Pito::*`. Home
  panels are `Pito::*PanelComponent` (not `Screen::Home::*PanelComponent`).
- **Domain layer** (singular): `Channel::*`, `Video::*`, `Game::*`, `Footage::*`.
  Each owns its YouTube / IGDB / analytics / recommendation / Voyage indexer.
- **Screen layer** — Panel-as-ViewComponent. Screen-specific panels live under
  `Screen::Videos::*PanelComponent`, `Screen::Games::*PanelComponent`.
- **UI primitive layer** — `Pito::*` for chat/event components; `Tui::*` for
  legacy panel primitives.

`Settings::*` is gone. Don't reintroduce it.

## ViewComponent + Hotwire discipline

- All UI work uses a ViewComponent. Never raw `<button>` / `<div>` with inline
  classes in a view.
- Visual rules from `docs/design.md` are hard: border-radius 0, no hover effects,
  no inline CSS, terminology canonical, brand caps ("pito" lowercase, "PITO" only
  in logo art), accent group per screen.
- Hotwire: Turbo Frames for sub-page swaps; Turbo Streams for server-pushed
  updates; Stimulus controllers under `app/javascript/controllers/` (one per file).
- Action Cable: scrollback updates flow through `Pito::Stream::Broadcaster` on the
  `pito:conversation:<id>` stream. No polling.

## Action bus

- Ruby actions registered in `Pito::ActionRegistry`, dispatched via
  `Pito::ActionDispatcher`.
- JS parity: `window.Pito.dispatchAction` mirrors the Ruby dispatcher.
- Every interactive UI element either dispatches an action or navigates — no
  inline handlers.

## Per-agent overrides

- **rails** — Rails 8.1, Ruby pinned via `.ruby-version` + `mise.toml`.
  ViewComponent for all views (no plain ERB partials except component templates).
  Stimulus for interactivity. Service objects under `app/services/<domain>/<verb>.rb`.
  Read `docs/architecture.md` before touching domain code.

- **rspec** — Specs are active. Run `bundle exec rspec` before marking any task
  done. Full suite: 673 examples. New specs mirror `app/` structure.

- **postgres** — Postgres 17 with pgvector. Migrations always reversible. Phase
  migrations: `add_column NULL` → backfill in a job → `change_column_null NOT NULL`
  across separate deploys. Voyage embeddings stored as `vector(<dim>)` columns;
  index with HNSW.

- **action-cable** — `Pito::Stream::Broadcaster` is the only entry point for
  scrollback broadcasts. Don't broadcast directly from controllers or models.

- **turbo** — Turbo Frames for in-screen swaps. Turbo Streams from background jobs
  go through `Pito::Stream::Broadcaster`. 422 on form validation failure.

- **tailwind** — `tailwindcss-rails` gem. Utility-first; `@apply` only when a
  cluster recurs 3+ times and naming pays off. Theme tokens come from
  `[data-theme="tokyo-night"]` CSS custom properties.

- **docker / kamal** — Dockerfile + `docker-compose.yml` for local dev;
  `.kamal/` for deployment. Kamal target is Hetzner. Build by git SHA, deploy by
  SHA, rollback `kamal rollback <sha>`. Run migrations as
  `kamal app exec 'bin/rails db:migrate'` before the new release goes live.

- **ai / voyage** — Voyage embeddings (`Channel::VoyageIndexer`,
  `Game::VoyageIndexer`). `Pito::ExternalApiTracker::Voyage` enforces quota.
  Model versions pinned; re-embedding is a coordinated operation.

- **reviewer** — Review pipeline for this repo:
  - `bin/rubocop`
  - `bin/brakeman -q -w2`
  - `bin/bundler-audit check --update`
  - `bin/importmap audit`
  - `bin/rails db:migrate && bin/rails db:rollback` on migration-touching diffs
  - `bundle exec rspec`

- **simplifier** — Apply with caution. The canonical-namespace rules above are
  not redundancy; they're the architecture. Don't "simplify" by collapsing
  `Pito::Foo` into `Foo` or inlining a service object to "remove a layer".

- **git** — Direct commits to `main` for small fixes; feature branches for larger
  work. One-line meaningful subjects. Omit co-author trailers.

- **github** — Multiple workflows: `ci.yml` (Rails), `docs-ci.yml`. CI path
  filters are intentionally tight — only Rails-affecting paths trigger `ci.yml`.
  `AGENTS.md` / `EXTRA.md` edits do not trigger Rails CI by design.

## Hard rules

- **One font size: 16px. Everywhere. No exceptions but the start-screen logo.**
  The body sets the 16px base and `* { font-size: inherit }` propagates it. Never
  add a `font-size` declaration in CSS and never use a Tailwind text-size utility
  (`text-xs`/`text-sm`/`text-lg`/`text-xl`/… — `text-base` is redundant, omit it).
  No `em`/`rem`/`px` font sizes, no sub-em shrinking for "secondary" text — make
  it dim (`text-fg-dim`/`text-fg-faded`), not small. The sole exemption is
  `.pito-start-screen__logo` (18px wordmark). Use weight, color, and spacing for
  hierarchy — never size.
- **Read the canonical doc, don't paraphrase it.** When acting on architecture,
  read `docs/architecture.md`. When acting on visual / keybinding work, read
  `docs/design.md`. Never repeat their content in commit messages or PR bodies.
- **Don't reintroduce removed surfaces.** MCP, Ratatui CLI, Redis, Sidekiq,
  Meilisearch, Doorkeeper — all removed. Don't add new dependencies on them.
- **No co-author trailers.** No "Generated with Claude Code", no Anthropic /
  OpenCode attribution in commit messages.
