# EXTRA.md (pito)

Project-specific conventions that override the generic guidance in `AGENTS.md`.
Edit freely — the agents `install.sh` never touches this file.

## What pito is

A self-hosted YouTube channel management tool for the owner. Hosted locally via
Cloudflare tunnels:

- `app.pitomd.com` — Rails app (primary surface)
- `pitomd.com` — Astro landing page (Cloudflare Pages)

Future deployment: Hetzner via Kamal.

Purpose: manage titles, descriptions, thumbnails, playlists, visibility for
videos across the owner's YouTube channels. YouTube Studio remains the upload
tool (videos uploaded as Drafts there). pito brings cross-channel analytics,
scheduling, and recommendation systems for game ↔ channel ↔ bundle pairings.

The app's mental shape: see how videos are doing, what games to play next,
server health, when to publish without competing across channels, is this game
good for this channel.

**Three screens, full stop.** Home (dashboard + system + calendar +
notifications), Videos (videos + channels), Games (games + bundles + footage).

## Surfaces being removed

These were in the codebase but are slated for removal — do NOT add new code on
top of them, do NOT bring them up in suggestions:

- **Rust TUI / Ratatui CLI** at `extras/cli/` — being deleted
- **MCP server** (`gem "mcp"`, `docs/mcp.md`, `mcp.pitomd.com`)
- **Meilisearch indexers** (`Channel::MeilisearchIndexer`,
  `Game::MeilisearchIndexer`, `Bundle::MeilisearchIndexer`)
- **Redis** (cache + Sidekiq) — migrating to Postgres-backed alternatives (Solid
  Cache / Solid Queue)

When working in a file that still references one of these, leave it alone unless
the task is the removal itself.

## Canonical references (don't restate, read them)

- `docs/architecture.md` — system topology, models, action bus, cable, Sidekiq
  job model, canonical namespaces. **Always read before starting non-trivial
  Rails work.**
- `docs/design.md` — visual contract, keybindings, terminology, brand caps,
  accent groups, terminal-aesthetic rules.
- `docs/website.md` — Astro landing page contract (`extras/website/`).

Note: `docs/mcp.md` and `docs/tui.md` cover surfaces being removed.

## Canonical namespace policy

**Cross-cutting concerns live under `Pito::*` unless a screen or domain claims
them.** Data-source integrations are claimed by the domain they feed.

- **`Pito::*`** — cross-cutting infrastructure: `ActionRegistry`,
  `ActionDispatcher`, `CableBroadcaster`, `Theme`, `GitRevision`, `Auth::*`,
  `Formatter::*`, `Notifications::*`, `Search::*`, `Calendar::*`,
  `Analytics::*`, `Recommendation::*`, `ExternalApiTracker::*`, `Schedule::*`,
  plus single-purpose utilities (`SlugBuilder`, `TimeZone`, `TokenDigest`,
  `PublicHosts`, `AssetsRoot`, `SafeEach`).
- **Home** has no `Home::*` namespace — its services live under `Pito::*` (Home
  IS the cross-cutting screen). Home panels are `Pito::*PanelComponent` (NOT
  `Screen::Home::*PanelComponent`).
- **Domain layer** (singular): `Channel::*`, `Video::*`, `Game::*`, `Bundle::*`,
  `Footage::*`. Each owns its YouTube / IGDB / analytics / recommendation /
  Voyage indexer.
- **Screen layer** — Panel-as-ViewComponent. Screen-specific panels live under
  `Screen::Videos::*PanelComponent`, `Screen::Games::*PanelComponent`.
- **UI primitive layer** — `Tui::*` (legacy name from the TUI-shared era; the
  primitives live in Rails ViewComponents now).

`Settings::*` is gone for good. Don't reintroduce it.

## ViewComponent + Hotwire discipline

- UI work uses a ViewComponent. **Never** raw `<button>` / `<div>` with inline
  classes in a view.
- Visual rules from `docs/design.md` are hard: border-radius 0, no hover
  effects, no inline CSS, terminology canonical, brand caps ("pito" lowercase,
  "PITO" only in logo art), accent group per screen.
- Hotwire: Turbo Frames for sub-page swaps; Turbo Streams for server-pushed
  updates; Stimulus controllers under `app/javascript/controllers/` (one per
  file).
- Action Cable: status-bar updates flow through `Pito::CableBroadcaster` on the
  `pito:status_bar` stream. No polling.

## Action bus

- Ruby actions registered in `Pito::ActionRegistry`, dispatched via
  `Pito::ActionDispatcher`.
- JS parity: `window.Pito.dispatchAction` mirrors the Ruby dispatcher.
- Every interactive UI element either dispatches an action or navigates — no
  inline handlers.

## Per-agent overrides

- **rails** — Rails 8.1, Ruby pinned via `.ruby-version` + `mise.toml`.
  ViewComponent for ALL views (no plain ERB partials except component
  templates). Stimulus for interactivity. Service objects under
  `app/services/<domain>/<verb>.rb`. Form objects under `app/forms/`. Read
  `docs/architecture.md` before touching domain code.

- **rspec** — **CURRENTLY DEFERRED.** The codebase is being rebuilt
  piece-by-piece; specs are paused. Agents do NOT write specs and do NOT run
  specs during this rebuild phase. Resumes once the user signals "rebuild
  settled — re-introduce specs".

- **postgres** — Postgres 17 with pgvector. Migrations always reversible. Phase
  migrations: `add_column NULL` → backfill in a job →
  `change_column_null NOT NULL` across separate deploys. Voyage embeddings
  stored as `vector(<dim>)` columns; index with HNSW.

- **action-cable** — `Pito::CableBroadcaster` is the only entry point. Channel
  grammar is enforced there. Don't broadcast directly from controllers or
  models.

- **turbo** — Turbo Frames for in-screen swaps. Turbo Streams from Sidekiq jobs
  go through `Pito::CableBroadcaster` (single envelope contract). 422 on form
  validation failure (Turbo re-renders the form).

- **tailwind** — `tailwindcss-rails` Gem. Utility-first; `@apply` only when a
  cluster recurs 3+ times AND naming pays off. Theme tokens come from
  `Pito::Theme` (Dracula L1–L4); don't introduce raw color utilities outside the
  token system.

- **docker / kamal** — Dockerfile + `docker-compose.yml` for local dev;
  `.kamal/` for deployment. Kamal target is Hetzner. Build by git SHA, deploy by
  SHA, rollback `kamal rollback <sha>`. Migrations run as
  `kamal app exec 'bin/rails db:migrate'` BEFORE the new release goes live.

- **ai / voyage** — Voyage embeddings (`Channel::VoyageIndexer`,
  `Game::VoyageIndexer`, `Bundle::VoyageIndexer`).
  `Pito::ExternalApiTracker::Voyage` enforces quota. Model versions pinned;
  re-embedding is a coordinated operation, not a casual change.

- **reviewer** — review pipeline for THIS repo:
  - `bin/rubocop`
  - `bin/brakeman -q -w2`
  - `bin/bundler-audit check --update`
  - `bin/importmap audit`
  - `bin/rails db:migrate && bin/rails db:rollback` (reversibility) on
    migration-touching diffs
  - **Specs are paused** (see `rspec` override). Reviewer notes spec-shaped
    tests in the playbook but does not run them.

- **simplifier** — apply with caution. The canonical-namespace rules above are
  NOT redundancy; they're the architecture. Don't "simplify" by collapsing
  `Pito::Foo` into `Foo` or by inlining a service object to "remove a layer".

- **git** — direct commits to `main`. One-line meaningful subjects. `[skipci]`
  (lowercase, no space) at the start of a commit subject OR PR title skips ALL
  CI workflows — used for WIP commits on feature branches. Omit `[skipci]` when
  the commit is ready to land green.

- **github** — Multiple workflows: `ci.yml` (Rails), `pito-cli-ci.yml` +
  `pito-cli-publish.yml` (Rust — being removed), `website-ci.yml` +
  `deploy-website.yml` (Astro), `docs-ci.yml`. CI path filters are intentionally
  tight — only Rails-affecting paths trigger `ci.yml`. AGENTS.md / EXTRA.md
  edits do NOT trigger Rails CI by design.

## Hard rules

- **Read the canonical doc, don't paraphrase it.** When acting on architecture,
  read `docs/architecture.md`. When acting on visual / keybinding work, read
  `docs/design.md`. Never repeat their content in commit messages or PR bodies.
- **`[skipci]` is intentional.** Use it during WIP, drop it when a commit should
  re-validate. Do NOT use the GitHub-built-in `[skip ci]` (with space) — it's a
  different token.
- **Don't reintroduce removed surfaces.** MCP, Ratatui CLI, Meilisearch, Redis —
  all flagged for deletion. Don't add new dependencies on them; help with their
  removal when asked.
- **No co-author trailers.** No "Generated with Claude Code", no Anthropic /
  OpenCode attribution.
