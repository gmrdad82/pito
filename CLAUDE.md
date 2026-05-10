# Pito — Monolith

A unified Ruby on Rails application plus two companion clients (Rust `pito` CLI,
Cloudflare Pages landing page) plus development knowledge base.

## Tech stack

- **Rails 8.1** with Hotwire (Turbo + Stimulus), ERB views, Tailwind CSS
- **Postgres 17** + pgvector / pgcrypto / citext (Docker) — primary datastore
- **Redis 7** (Docker) — Sidekiq queue + Rails cache store
- **Sidekiq** + **sidekiq-cron** for background jobs
- **Chartkick + Groupdate + Chart.js** for charts
- **google-apis-youtube_v3** and **google-apis-youtube_analytics_v2** for
  YouTube APIs
- **RSpec** with FactoryBot, Faker, Shoulda Matchers, WebMock
- **MCP** (Model Context Protocol) server via `mcp` gem — see `docs/mcp.md`
- **Rust** (Ratatui) for the unified `pito` CLI binary (TUI default, subcommands
  for footage import and other surfaces)
- **Cloudflare Pages** for the marketing site under `extras/website/`

## Layout

- `app/`, `bin/`, `config/`, `db/`, `public/`, `spec/`, `vendor/` — Rails app at
  the repo root
- `lib/` — Rails-only library code
- `extras/`
  - `cli/` — Rust `pito` CLI binary. Default (no args) launches the TUI;
    subcommands include `pito footage` (Phase 4) for footage import. Style:
    `claude` binary — `pito help`, `pito version`, etc.
  - `website/` — Cloudflare Pages landing page
- `docs/`
  - `architecture.md`, `design.md`, `mcp.md`, `setup.md`, `auth.md` — product
    docs
  - `plans/{alpha,beta}/` — phase plans
  - `decisions/` — append-only architectural decision records (ADRs)
  - `orchestration/` — agents catalog, lanes, follow-ups, playbooks, sync
    scripts
  - `conversations/` — durable session summaries
- `.claude-config/` — Claude Code agent / command / skill definitions, synced
  with `~/.claude/`
- Root configs: `Gemfile`, `Cargo.toml` (workspace), `.editorconfig`,
  `.prettierrc.json`, `.gitignore`, `CLAUDE.md`

## Commands

```bash
bin/setup           # Install deps, start Docker, prepare DB
bin/dev             # Start Docker services + Puma + Sidekiq + Tailwind watcher
bin/mcp             # Start MCP server (stdio transport, separate process)
bin/mcp-web         # Start MCP HTTP server (dedicated Puma on port 3001)
bundle exec rspec   # Run test suite
bundle exec rubocop # Lint
```

## Workflow rules

- Commit directly to `main` with one-line meaningful messages.
- No branches, no PRs in the early stages.
- The architect commits and pushes after the user validates a manual playbook.
- Always pull with `--rebase`.
- Markdown files wrap at 80 chars (`prose-wrap: always`). Use
  `prettier --write '**/*.md'` to apply, or rely on editor integration via
  `.prettierrc.json`.
- No Co-Authored-By, no AI authorship mentions, no multi-line bodies in commits.
- Do NOT commit until the user has tested and validated the changes.
- Every Rails step must include RSpec specs. Provide manual testing instructions
  in conversation, not in files.
- Rust crates include tests for new functionality.

## Logging convention

Every implementation session ends with `docs/plans/beta/<NN-phase>/log.md`
updated. The log captures: what we discussed in the session, what was
implemented, which files changed, and links to the plan / spec / decisions it
referenced. Mobile Claude reads logs via the MCP `list_docs` tool to recover
session context — sorted by mtime, the newest log answers "what was I working on
last session"; the full set answers "what have we worked on from the start".
Desktop architect appends to logs after the user validates work.

Decisions live in `log.md` by default. An ADR under `docs/decisions/` is
reserved for moments when a decision produces a durable artifact (a new
top-level reference doc like `design.md`, `architecture.md`, `mcp.md`, or a
structural commitment that warrants its own page). Routine choices made in the
flow of a session — picking a library, naming a flag, deferring an edge case —
stay in the session log.

## MCP Dev KB surface (Mobile interop)

Three MCP tools expose the `docs/` tree to Claude Mobile:

- `list_docs` — list markdown files. Filter by `name_pattern` (e.g. `log.md`,
  `*.md`) and `prefix` (e.g. `plans/beta/`, `decisions/`); sort by mtime.
- `read_doc` — read a single `.md` file under `docs/` or `CLAUDE.md`.
- `save_note` — drop markdown into `docs/notes/`. Filename is server-generated
  as `YYYY-MM-DD-HH-MM-SS-<slug>.md`. No overwrite; multiple captures of the
  same thought are fine; Desktop curates and prunes later.

Mobile is read + capture; Desktop is curate + commit. Edits, deletes, renames,
file moves all happen via Desktop. The three tools require the `dev` MCP scope;
production builds strip `dev` from the catalog and the tool registry (per ADR
0004).

**Notes commit lifecycle.** Every Desktop commit runs `git add docs/notes/`
before staging the rest of the change so notes Mobile dropped since the last
commit land in history. Pruning stale notes also happens on Desktop, in flow
with the user, before staging.

Spec: `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md`.

## Agent orchestration

This monolith operates as a **master agent** coordinating specialized subagents.
The master agent (architect) plans, delegates, reviews, and commits — it does
NOT write code or project markdown directly. Subagents stay strictly within
their declared file scope under this repository.

The master agent's role:

1. **Plan** — understand the big picture, break work into parallelizable units
2. **Delegate** — spawn named subagents for isolated file sets (e.g., "cli:
   dashboard charts", "rails: channel sync job")
3. **Review** — after implementation agents finish, spawn a reviewer / QA agent
4. **Iterate** — fix issues with targeted agents (parallel if isolated, single
   if integration)
5. **Commit** — only after the user has tested and validated

When a task expects output outside an actor's role, the actor STOPs and reports.
The master agent dispatches the correct subagent. Silent scope expansion is
treated as a process failure, not a feature.

Subagents do NOT commit or push. They only write code and files. The master
commits after the user validates.

Maximize parallelism: spawn multiple agents when they touch distinct files.

Canonical reference: `docs/orchestration/agents.md` and
`.claude-config/agents/`.

## Role discipline

Every actor in this workspace operates strictly within its declared role. The
master agent plans, dispatches, reviews, and commits — it does NOT write code or
edit project markdown directly. Subagents stay in their declared file scope and
do not cross into other agents' work.

When a task expects output outside an actor's role, the actor STOPs and reports.

## Hard rules

- **No JavaScript `alert` / `confirm` / `prompt` / `data-turbo-confirm`**
  anywhere. All destructive or significant actions go through the action
  confirmation page framework (`shared/_action_screen.html.erb` +
  `DeletionsController` / `SyncsController` + `Confirmable` concern for the
  Rails app; in-TUI confirmation overlay for the `pito` CLI; two-step `confirm`
  flag for MCP).
  - **Exception — `beforeunload` is allowed for unsaved-changes navigation
    guards.** The browser-native "Leave site?" dialog triggered by setting
    `event.returnValue` is NOT the same as JS `confirm()`. The browser renders
    the dialog itself; the page does not interrupt user action mid- click. Use
    the `unsaved-form` Stimulus controller; never call `window.confirm` /
    `alert` / `prompt` directly.
- **Bulk-as-foundation** — single-record destructive or sync actions are bulk
  operations with a one-element ids list. URL pattern `/<action>s/:type/:ids`
  accepts 1 or N. Applies across web (`/deletions/:type/:ids`,
  `/syncs/:type/:ids`), MCP (`delete_records`, `sync_records` with
  `confirm: bool`), and the `pito` CLI (in-TUI confirmation).
- **Yes / no for external booleans** — boolean values at every external boundary
  (URL params, JSON, MCP I/O, Rust client wire format) use `"yes"` / `"no"`
  strings — never `true` / `false` / `0` / `1`. Internal storage stays Boolean.
  Convert at every boundary.
- **Secrets** (passwords, API keys, tokens) live exclusively in
  `Rails.application.credentials`. Never in `.env*` files. Per-environment
  nested structure (mirror the `:postgres` block).

## Configuration strategy

- `.env.development` / `.env.test` — per-environment infrastructure connection
  info ONLY (host / port for Postgres, Redis URL). No secrets. Gitignored.
- `.env.example` — template for the above. Committed.
- `rails credentials:edit` — Postgres database / username / password per
  environment (`:postgres` block), the seed-time owner email + password
  (`:owner` block — see `docs/setup.md`), Sidekiq web auth, Active Record
  Encryption keys.
- `config/master.key` — on disk, gitignored. Never in `.env`.
- CI uses its own env vars defined in `.github/workflows/ci.yml` (no master key
  needed).
- `AppSetting` table — `max_panes`, `pane_title_length`, theme. Managed via the
  web UI. (YouTube OAuth config returns once the OAuth phase ships.)

## Visual style

See `docs/design.md` for the full design system. Key rules:

- **Font:** monospace
  (`ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`),
  13px base
- **Colors:** white bg, text `#1a1a1a`, links `#0000cc`, muted `#555`, borders
  `#ddd`
- **Red (`#cc0000`) is ONLY for destructive / dangerous actions** — never in
  charts, indicators, or decorative elements
- **Bracketed link convention:** all clickable elements use `[ label ]` — links,
  buttons, chart legends
- **Cursor:** `cursor: pointer` on all clickable elements (links, buttons,
  submit, chart legends)
- **Charts:** no animation, no red, crosshair on line charts, bracketed colored
  legend labels
- **Sidekiq Web** at `/sidekiq` with HTTP basic auth, no link in nav or Settings

## Architecture notes

- pito is **single-install, multi-user** (ADR 0003). The whole database belongs
  to one install; there is no `Tenant` model and no `tenant_id` columns on
  domain tables. Anyone authenticated has full read/write access to everything
  in the install. Multi-user is auth-only ergonomics ("more than one person can
  log in"), not data isolation.
- `User` is the auth-only owner of sessions and tokens. Columns:
  `id, email (citext, unique, NOT NULL), password_digest, created_at, updated_at`.
  No `username`, no `tenant_id`, no `admin`. Login is **email + password**
  (Phase 8); `Current.user` carries the authenticated user for the duration of a
  request.
- `Channel` columns:
  `id, channel_url, star, last_synced_at, youtube_connection_id, timestamps`.
  `youtube_connection_id` (FK to `youtube_connections`, nullable) was added in
  Phase 7 as `oauth_identity_id` and renamed in Phase 9 per ADR 0006. The URL is
  **locked after create** (`before_update :prevent_url_change`); only `star` is
  mutable. There are no other per-channel OAuth columns in this phase.
- `ChannelSync` (`app/jobs/channel_sync.rb`, flat name) is a placeholder job: it
  flips `syncing` true, no-ops, then flips `syncing` false and stamps
  `last_synced_at` in an `ensure` block. Real YouTube API work lands when the
  OAuth phase ships.
- Workspace model: Channels and Videos pages are multi-pane workspaces (up to
  `max_panes` side-by-side).
- Picker pages (no panes) with bulk mode for multi-select operations.
- `SavedView` persists workspace URLs for quick restore. For `kind: channels`,
  labels currently use `Channel#id.to_s` (placeholder until channels regain a
  synced display field).
- See `docs/architecture.md` for the full topology, `docs/mcp.md` for the MCP
  tool surface, and `docs/setup.md` for first-run setup.

## Active follow-ups

Tracked in `docs/orchestration/follow-ups.md`. Highest-priority items right now:

1. Phase 13 F1 + F2 + F3 fix-forward (in flight)
2. Phase 14 F1 + F2 fix-forward (in flight)
3. Phase 16 Spec 02 / 03 reviewer findings (queued; land as they surface)
4. Rails JSON endpoints for CLI / MCP parity across Phases 14 / 15 / 16 (Games,
   Calendar, Notifications) — gated on Phase 20 friendly URLs landing in main
5. 2026-05-09 realignment top-level direction map — foundational reference for
   the next 12 work units (tenant drop, MCP scope simplification, Channel +
   Video edit surfaces, Analytics, Game model, Calendar, Notifications, CLI
   parity)
6. CLI feature-parity sweep — channels list / videos list / settings panes /
   search results (work unit 10 in the realignment)
7. Footage importer-side ffmpeg frame extraction + bulk PATCH upload (Phase 7.5
   spec 06 importer half)
8. Meilisearch indexing parity with Voyage per-target flags (pairs with the
   Voyage AppSetting revamp; gated on Channel + Video schema expansion)

See `docs/orchestration/follow-ups.md` for the full open list. Items above are
tracked alongside active phase work; the highest-priority ones track in flight
on each phase log.

## Glossary

- **Pito** — the application.
- **Alpha** — concluded multi-front exploratory phase.
- **Beta** — current build phase. Plans live in `docs/plans/beta/`.
- **Theta** — conditional future phase (distribution, marketing).
- **MCP** — Model Context Protocol.
- **Web Puma** — the Rails Puma process serving `app.pitomd.com`.
- **MCP Puma** — the separate Rails Puma process serving `mcp.pitomd.com`.
- **Voyage** — Voyage AI. Anthropic-recommended embedding provider.
- **pgvector** — Postgres extension for vector storage.
- **Meilisearch** — keyword + hybrid search engine.
- **`pito`** — unified Rust CLI binary at `extras/cli/`. Default mode is the TUI
  client; subcommands (`pito footage`, `pito help`, `pito version`, future ones)
  extend the surface.
- **pitomd.com** — production domain.
