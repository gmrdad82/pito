# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project

Pito — a single-tenant Rails 8 web app for tracking, analyzing, and managing
YouTube activity across multiple channels. Runs locally as a personal tool.
Architecture leaves room for future multi-tenancy but does not implement it now.

## Tech Stack

- **Rails 8.1** with Hotwire (Turbo + Stimulus), ERB views, Tailwind CSS
- **Postgres 17** + pgvector/pgcrypto/citext (Docker) — primary datastore
- **Redis 7** (Docker) — Sidekiq queue + Rails cache store
- **Sidekiq** + **sidekiq-cron** for background jobs
- **Chartkick + Groupdate + Chart.js** for charts
- **google-apis-youtube_v3** and **google-apis-youtube_analytics_v2** for
  YouTube APIs
- **RSpec** with FactoryBot, Faker, Shoulda Matchers, WebMock
- **MCP** (Model Context Protocol) server via `mcp` gem — see `docs/mcp.md`

## Commands

```bash
bin/setup          # Install deps, start Docker, prepare DB
bin/dev            # Start Docker services + Puma + Sidekiq + Tailwind watcher
bin/mcp            # Start MCP server (stdio transport, separate process)
bin/mcp-web        # Start MCP HTTP server (dedicated Puma on port 3001)
bundle exec rspec  # Run test suite
bundle exec rubocop # Lint
```

## Role discipline

Every actor working in this repo operates strictly within its declared role.
Subagents do not commit, do not edit files outside their declared scope, and do
not cross into other agents' work. When work falls outside an actor's role, STOP
and report — the architect dispatches the correct agent.

Canonical reference: `pito-dev-kb/orchestration/agents.md` and
`pito-dev-kb/.claude-config/agents/`.

## Rules

- Never modify files outside this repository folder.
- Commit directly to `main` with one-line meaningful messages.
- No branches, no PRs in early stages.
- The architect commits and pushes after the user validates a manual playbook.
- No Co-Authored-By, no multi-line bodies, no AI authoring mentions.
- Do NOT commit until user has tested and validated the changes.
- Every step must include RSpec specs. Provide manual testing instructions in
  conversation, not in files.
- **No JS `alert` / `confirm` / `prompt` / `data-turbo-confirm`** — anywhere.
  The action confirmation page framework (`shared/_action_screen.html.erb` +
  `DeletionsController` / `SyncsController` + `Confirmable` concern) is the
  canonical pattern.
- **Bulk-as-foundation** — single-record destructive or sync actions are bulk
  operations with a one-element ids list. Applies across web
  (`/deletions/:type/:ids`, `/syncs/:type/:ids`), MCP (`delete_records`,
  `sync_records` with `confirm: bool`), and the terminal app (in-TUI
  confirmation).
- Markdown files wrap at 80 chars (`prose-wrap: always`). Use
  `prettier --write '**/*.md'` to apply, or rely on editor integration via
  `.prettierrc.json`.

## Build Tracking

Planning lives in the sibling `pito-dev-kb` repo
(`pito-dev-kb/plans/<generation>/<phase>/`). This repo only contains its own
runtime docs under `docs/` (`architecture.md`, `setup.md`, `mcp.md`,
`design.md`).

## Configuration Strategy

- `.env.development` / `.env.test` — per-environment infrastructure connection
  info ONLY (host/port for Postgres, Redis URL). No secrets. Gitignored.
- `.env.example` — template for the above. Committed.
- `rails credentials:edit` — Postgres database/username/password per environment
  (`:postgres` block), the seed-time tenant/user (`:owner` block — see
  `docs/setup.md`), Sidekiq web auth, Active Record Encryption keys.
- `config/master.key` — on disk, gitignored. Never in .env.
- CI uses its own env vars defined in `.github/workflows/ci.yml` (no master key
  needed).
- `AppSetting` table — `max_panes`, `pane_title_length`, theme. Managed via web
  UI. (YouTube OAuth config returns once the OAuth phase ships.)

## Visual Style

See `docs/design.md` for the full design system. Key rules:

- **Font:** monospace
  (`ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`),
  13px base
- **Colors:** white bg, text #1a1a1a, links #0000cc, muted #555, borders #ddd
- **Red (#cc0000) is ONLY for destructive/dangerous actions** — never in charts,
  indicators, or decorative elements
- **Bracketed link convention:** all clickable elements use `[ label ]` — links,
  buttons, chart legends
- **Cursor:** `cursor: pointer` on all clickable elements (links, buttons,
  submit, chart legends)
- **Charts:** no animation, no red, crosshair on line charts, bracketed colored
  legend labels
- **Sidekiq Web** at /sidekiq with HTTP basic auth, no link in nav or Settings

## Architecture Notes

- `Tenant` and `User` exist as **seeded singletons** at the schema level only —
  no signup, no login, no session, no token, no UI. `Current.tenant` /
  `Current.user` are set in a `before_action` to `Tenant.first` / `User.first`.
  Auth Foundation is deferred to a later phase.
- `Channel` is tenant-scoped. Columns:
  `id, tenant_id, channel_url, star, connected, syncing, last_synced_at, timestamps`.
  The URL is **locked after create** (`before_update :prevent_url_change`); only
  `star` and `connected` are mutable. There are no per-channel OAuth columns in
  this phase.
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

## Project Docs (pre-Rails, in \_temp/)

Original planning docs moved to `_temp/` during Rails setup. Contains channel
profiles, style guides, workflow docs, and skills overview to be integrated into
the app later.
