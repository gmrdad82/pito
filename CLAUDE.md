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
bin/test            # Fast local spec run (system specs excluded, cached prep)
bin/test failed     # Re-run only failures from the last run (serial)
bin/test all        # Full local suite including system specs (slow)
bin/test path/...   # Pass-through to `bundle exec rspec` for a specific path
bundle exec rubocop # Lint
```

## Spec workflow

**Local default — fast loop.** `bin/test` is the canonical local command.
`.rspec` carries `--tag ~type:system` so every local invocation skips
Capybara/Chrome system specs by default — they run ~5-10× slower than
request/model specs. `bin/test-prepare` is a shim that only runs
`bin/rails db:test:prepare` when `db/schema.rb` mtime has changed since the last
successful prep, saving ~10-15 s per invocation.

**Local fix loop.** After a failed run, `bin/test failed` re-runs only the
recorded failures via `--only-failures`. **When fix agents add new spec files,
those new specs must be picked up by `bin/test failed` in addition to the
recorded failures** — otherwise a green-after-fail signal won't actually
exercise the new test code. Verify by listing the spec files RSpec is about to
run, or fall back to a focused `bin/test path/to/new_spec.rb` after the `failed`
pass.

**CI is the gate — full suite always.** The GitHub Actions workflow at
`.github/workflows/ci.yml` overrides `.rspec` with
`-- --options /dev/null --require spec_helper` so CI runs the FULL suite, system
specs included, no tag exclusion. Local speedups never reach CI. The master
agent commits when local + manual validation are green; CI then confirms the
full picture on every push.

**Adding new tests in a feature dispatch.** Every Rails dispatch must include
RSpec specs for new behavior. The agent's own dispatch verifies via
`bin/test <files>` for targeted coverage; the architect's pre-commit pass runs
`bin/test` (fast loop) before committing. CI catches anything the local fast
loop skipped.

## Communication style

Use emojis liberally in master-agent and subagent communication — status
updates, report-back text, dispatch announcements, end-of-turn summaries. Map
emoji to actual signal: ✅ done, ⏳ in flight, 🚫 blocked, ⚠️ conflict, 🎯
milestone, 🔍 inspecting, 🧪 specs, 🚀 next, ✨ delivered, 🎉 phase closes.
Don't shoehorn — emojis are accents, not decoration. Stay OUT of code, commit
messages, plan / log markdown, and spec files — those are durable artifacts that
age into reference material.

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

### Dispatch sizing (universal — rails, rust, website, mcp, docs, any

agent)

Agents are speed multipliers for **code changes**. Keep every dispatch small,
focused, and fast.

**Wall-clock ladder per dispatch:**

- **≤ 5 minutes — target.** Default size of every dispatch. Think smallest
  meaningful unit of code change.
- **5 – 10 minutes — bad but tolerated.** Treat as a smell.
- **10 – 20 minutes — needs justification.** Only acceptable for atomic
  refactors that break the build mid-split.
- **≥ 20 minutes — hard kill.** No exceptions. Stop, slice, redispatch.

**One concern per dispatch.** Never bundle "do A and B and verify" into one
agent. Split into A, B, verify — run independently, in parallel where the files
don't overlap.

### Iteration vs consolidation (universal)

The workflow has two modes that apply across every stack:

- **Iteration mode (default).** Agents write **code only**. No test runs of any
  kind (no `rspec`, no `cargo test`, no `npm test`/`vitest`/`playwright`). No
  new test files. The point is **velocity of code change**, not green-ness. If a
  dispatch prompt says "run tests", strip it.
- **Consolidation mode (opt-in, on user signal).** A dedicated pass that adds
  the deferred tests, runs the full suite, and reconciles drift. Triggered by
  the user saying "consolidate" / "lock this in" / "run specs" / "validate".

Default mode is iteration. Consolidation is explicit. The architect- spec
mandate and any per-stack "tests must accompany every change" rules are
SUSPENDED during iteration — they apply only inside the consolidation pass.

## Role discipline

Every actor in this workspace operates strictly within its declared role. The
master agent plans, dispatches, reviews, and commits — it does NOT write code or
edit project markdown directly. Subagents stay in their declared file scope and
do not cross into other agents' work.

When a task expects output outside an actor's role, the actor STOPs and reports.

### Master recon discipline — dispatch Explore, never grep/Read directly

When the master agent needs to look up canonical values, file paths, component
shapes, CSS tokens, schema columns, or any project-tree fact before dispatching,
the master DISPATCHES the Explore agent. The master does NOT run
bash/grep/Read/Edit against the project's `app/`, `lib/`, `config/` (except
`CLAUDE.md`), `db/`, `spec/`, `extras/` trees directly — even for "quick recon"
before a dispatch. Even one-line greps count. Direct project-tree reading by the
master leaks responsibility, expands the master's context window, and bypasses
the role discipline that the rest of the workspace enforces.

**Allowed direct reads for the master:**

- `docs/orchestration/*` (handoffs, follow-ups, playbooks)
- `docs/plans/*` (phase plans, logs, additions, dropped)
- `docs/decisions/*` (ADRs)
- `docs/design.md`, `docs/architecture.md`, `docs/mcp.md`, `docs/setup.md`
- `CLAUDE.md`
- Subagent reports returned by Agent tool

**Disallowed (always dispatch Explore):**

- `grep`/`find`/`bash` against the project tree
- `Read` on any `app/`, `lib/`, `db/`, `spec/`, `extras/`, `config/*` (except
  `CLAUDE.md`) file
- "Let me check"/"let me verify"/"quick recon" workflows that involve opening
  project source files

## Surface boundaries (locked vs open)

Closed milestones that agents may NOT modify without explicit user confirmation
(locked 2026-05-19):

- **/games** — closed beta-3 milestone. Includes `app/views/games/**`,
  `app/controllers/games_controller.rb`, `app/components/games/**` (except where
  Omnisearch needs to read them as reference; see below). Read-only for
  inspection. No visual changes, no controller changes, no spec changes. Bug
  fixes user-confirmed first.
- **/settings** — closed beta-3 milestone. Includes `app/views/settings/**`,
  `app/controllers/settings_controller.rb`, `app/components/settings/**`. Same
  read-only rule.

Open surfaces under active development:

- **/channels** — current beta-3 iteration. Free to modify
  `app/views/channels/**`, `app/controllers/channels_controller.rb`,
  `app/components/channels/**`, `app/services/channels/**`.
- **Omnisearch** — independent surface. The search modal that searches games +
  bundles + channels evolves freely even though individual indexers and the
  search controller sit in files alongside game-related code. Components under
  `app/components/search/everywhere_*` are owned by Omnisearch;
  `app/components/search/omnisearch_*` (the /games modal modes) are LOCKED with
  /games unless user explicitly authorizes a touch.
- **Astro website** (`extras/website/**`) — open for marketing page iteration.
- **Layout chrome** — `app/views/layouts/application.html.erb`, footer/header
  partials, sticky-header CSS, About modal, Everywhere modal mount — open.
  Changes here implicitly affect every page (including locked /games and
  /settings), but the user has authorized chrome-level work.
- **Other surfaces** (`/projects`, `/calendar`, `/notifications`, `/videos`,
  etc.) — paused but not formally locked. Incidental bug fixes acceptable.

**Dispatch boundary rule:** every implementation dispatch prompt that the master
sends MUST include an explicit "DO NOT touch" list that names the locked
surfaces (/games + /settings) plus any other files the dispatch shouldn't reach.
Subagents that report touching a locked surface trigger a master-level rollback.

**Exceptions** — bug fixes inside a locked surface require:

1. User explicit confirmation in chat for the specific fix
2. Master dispatch prompt cites the user's confirmation
3. Subagent applies ONLY the agreed scope, nothing else

## Slack notifications

The master agent (and any subagent) sends Slack pings to the user via the
`pito-slack` agent. **Never call `mcp__claude_ai_Slack__*` MCP tools directly**
— every Slack notification flows through the agent dispatch so the project's
message-style governance (in `docs/agents/slack.md`) stays in one place.

Message style: **git-commit-subject concise**. Status verb + minimal context,
fits a single short line (`dotfiles green`, `specs running`, `/games ready`,
`commit pushed`). The chat conversation remains the detailed surface; Slack is
the heads-up only. See `docs/agents/slack.md` for the channel + style contract
the agent enforces.

Use Slack pings sparingly — for long-running processes (full spec sweeps,
sustained refactors), commit-and-push milestones, or when the user has walked
away and needs a "ready for next step" signal. Not for routine in-chat status
(that's the conversation itself).

The pito app's own Slack webhook (configured in `NotificationDeliveryChannel`
and sent by Sidekiq workers) is a SEPARATE production surface for end-user
digests — never conflate the two.

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
- **Mandatory-2FA gate.** After session creation, a post-session `before_action`
  in `Sessions::AuthConcern` redirects any authenticated user who has not
  configured TOTP to `/settings/security/totp`, blocking every other route until
  enrollment is confirmed. The gate is browser-only — API tokens and MCP bearer
  surfaces are exempt by design (a bearer credential cannot complete a TOTP
  enrollment). Allowlist is minimal: TOTP-setup routes plus logout.

## Source of truth

When any numeric / token / sizing / color / behavioral value is needed across
docs / specs / code, the canonical source hierarchy is:

1. **User decision in chat** — most authoritative; capture immediately to the
   right doc surface per the "save clarifications to docs" discipline.
2. **`docs/decisions/*.md` (ADRs)** — durable architectural truth.
3. **`docs/design.md`** — canonical visual rules + tokens + sizes.
4. **`docs/plans/beta/<NN>/plan.md`** — phase-locked decisions; must agree with
   design.md or trigger a propagating update.
5. **`docs/plans/beta/<NN>/specs-v2/*.md`** — spec text must cite design.md /
   plan.md for any visual claim. Bare numbers in specs without a citation are a
   smell.
6. **Code** (components / CSS / models / configs) — follows the above. Drift
   between code and the higher surfaces = bug; fix code (not docs, unless the
   doc is the one wrong, in which case fix the doc + propagate down).

When any two surfaces disagree, the higher-authority surface wins. Lower
surfaces get updated — never the inverse.

### Look up, never pick

The master agent NEVER invents values into canonical docs. Subagents NEVER pick
defaults / smallest available / sensible guesses for missing values. Every
dispatch prompt MUST name the canonical source for every value the agent needs
(file:section citation). If the canonical source doesn't yet have the answer,
the master STOPs and asks the user — does not dispatch with an open "use the
smallest" instruction.

When master adds a new section to design.md / decisions / CLAUDE.md, the same
dispatch reads the matching code + plan.md + specs FIRST and captures truth. If
no canonical decision exists yet, the entry reads `(needs user decision — TBD)`
rather than a fabricated value.

## Configuration strategy

- `.env.development` / `.env.test` — per-environment infrastructure connection
  info ONLY (host / port for Postgres, Redis URL). No secrets. Gitignored.
- `.env.example` — template for the above. Committed.
- Secrets live in a **single global `config/credentials.yml.enc`** decrypted by
  `config/master.key` — there is **no per-environment credentials split** in
  this repo. The structure inside the file can still be nested per env, but the
  file itself is global. Top-level blocks: `active_record_encryption`, `github`,
  `google_oauth`, `igdb`, `owner`, `postgres`, `secret_key_base`, `sidekiq`,
  `tokens`, `voyage`. The `:owner` block is `username` + `password` (no email —
  see `docs/setup.md`).
- `config/master.key` — on disk, gitignored. Never in `.env`.
- CI uses its own env vars defined in `.github/workflows/ci.yml` (no master key
  needed).
- `AppSetting` table — `max_panes`, `pane_title_length`, `theme`,
  `monetization_enabled`, plus runtime non-secret flags
  (`voyage_index_project_notes`, `keyboard_navigation_enabled`, `timezone`).
  Managed via the web UI. YouTube OAuth, Voyage, and Google-console credentials
  no longer live here — those are in `Rails.application.credentials`.

## Visual style

See `docs/design.md` for the full design system. Key rules:

- **Font:** monospace
  (`ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace`),
  13px base
- **Colors:** white bg, text `#1a1a1a`, links `#0000cc`, muted `#555`, borders
  `#ddd`
- **Red (`#cc0000`) is ONLY for destructive / dangerous actions** — never in
  charts, indicators, or decorative elements
- **Exception — rating quality spectrum.** The `RatingHeatBarComponent` may use
  red (`var(--color-rating-bad)`, `#cc0000` light / `#ff5555` dark) as the low
  end of the quality gradient. This is the ONE allowed non-destructive use of
  red — restricted to the heat bar's bad-zone color stop and the
  `--color-rating-bad` token's surface area. No other chart, indicator, or
  decorative element may use red.
- **Bracketed link convention:** all clickable elements use `[ label ]` — links,
  buttons, chart legends
- **Cursor:** `cursor: pointer` on all clickable elements (links, buttons,
  submit, chart legends)
- **Charts:** no animation, no red, crosshair on line charts, bracketed colored
  legend labels
- **Sidekiq Web** at `/sidekiq` with HTTP basic auth, no link in nav or Settings

## Code organization — ViewComponents, Formatting services, helpers, partials

**HTML structure = ViewComponent.** Every HTML structure that's more than a
literal one-line fragment is a `ViewComponent` under `app/components/`. No
partials calling partials with helper-magic spaghetti. Each component owns its
own ERB template + class + spec. Modes/variants become constructor arguments,
not template branches. ViewComponents nest cleanly; partials nesting partials
creates tight coupling and untestable surfaces.

**Data transformation = `Formatting::*` service/module.** Any function that
takes data and returns formatted-data (numbers, dates, durations, slugs,
trimming, dasherizing, humanizing, byte-formatting, truncation, em-dash
fallbacks, etc.) lives in a `Formatting::` namespaced module under
`app/services/formatting/` (or wherever the project's service convention puts
it). Single-purpose `.call(input)` pure functions. Stateless. No I/O. Easy to
test (input → output table).

Examples of `Formatting::*`:

- `Formatting::Filesize.call(bytes)` — KB/MB/GB walk with em-dash for nil
- `Formatting::Duration.call(seconds)` — humanize seconds to "2h 13m"
- `Formatting::ShortReleaseDate.call(date)` — "Jan 2024" or em-dash
- `Formatting::SlugDasherize.call(query)` — "Spider-Man" → "spider-man"
- `Formatting::WebhookUrlMask.call(url, brand:)` — Discord/Slack URL mask
- `Formatting::TimeAgoCompact.call(time)` — "5m ago" / "—"

**Helpers = single-purpose pure logic only.** If a helper survives this rule, it
does ONE thing AND that one thing is pure logic (not formatting). Acceptable:
`keyboard_navigation_enabled?`, `current_user_admin?`,
`body_classes_for(controller)`. If a helper file has > 3 methods, it's a smell —
likely there's a `Formatting::*` service hiding inside.

**Partials = ultra-trivial standalone fragments only.** A partial is acceptable
ONLY if BOTH: ≤ 5 lines of ERB AND standalone (no `local:` parameter that
branches behavior, no per-call configuration). Examples of legitimate partials:
`shared/_version.html.erb` (VERSION + last SHA),
`shared/_csrf_meta_tags.html.erb`. If a partial takes a parameter that changes
its render, it's a ViewComponent in disguise — convert.

### Component reuse — refactor the shared primitive, never fork

When a new use case needs a component the project already has (chip, shelf,
badge, bracketed link, modal, table, form field), the new use case REUSES the
canonical component. If the canonical component doesn't yet support the new use
case (a missing kwarg, a required arg that should be optional, a missing render
mode), the dispatch FIRST refactors the canonical (add a default, extract a
headless variant, support a new mode) THEN uses it. **Never fork into a parallel
`<Domain>::FooComponent` that reimplements the shared shape.** Forking is a
process failure and the master rejects agent reports that ship a parallel
component.

**Examples of canonical primitives (do not fork):**

- `FilterChipComponent` — every chip in the app
- `ShelfComponent` (top-level) — every horizontal-scroll tile row
- `BracketedLinkComponent` — every bracketed link / action
- `StatusBadgeComponent`, `RatingBadgeComponent` — every badge
- `Formatting::*` services — every data-to-string transformation; if a new
  formatter is needed (e.g., truncation, number shorthand, compact hours),
  DISPATCH an agent to add a new `Formatting::*` service rather than inlining
  the logic in a view or component

If a value or transform needs to live somewhere, the priority is:
`Formatting::*` service > ViewComponent constructor arg > inline literal.
Inlining is the last resort and a smell.

## Architecture notes

- pito is **single-install, multi-user** (ADR 0003). The whole database belongs
  to one install; there is no `Tenant` model and no `tenant_id` columns on
  domain tables. Anyone authenticated has full read/write access to everything
  in the install. Multi-user is auth-only ergonomics ("more than one person can
  log in"), not data isolation.
- `User` is the auth-only owner of sessions and tokens. Columns:
  `id, username (citext, unique, NOT NULL), password_digest, created_at, updated_at`.
  No `email`, no `tenant_id`, no `admin`. Login is **username + password +
  mandatory TOTP** (Phase 8 + Phase 29 Unit A2); `Current.user` carries the
  authenticated user for the duration of a request. The mandatory-2FA gate is
  **browser-only** — API tokens and MCP bearer credentials are exempt by design.
- `Channel` columns:
  `id, channel_url, star, last_synced_at, youtube_connection_id, timestamps`.
  `youtube_connection_id` (FK to `youtube_connections`, nullable) was added in
  Phase 7 as `oauth_identity_id` and renamed in Phase 9 per ADR 0006. The URL is
  **locked after create** (`before_update :prevent_url_change`); only `star` is
  mutable. There are no other per-channel OAuth columns in this phase. Channel
  is a **one-way read-only mirror from YouTube** (Phase 29 Unit A0). The only
  mutable surface is `star`, toggled via `Channels::StarsController` at
  `PATCH /channels/:channel_id/star`. `/channels/:id/history` (the change log)
  survives as the mirror's audit trail. The edit form, preview component, diff
  reconciliation surface, and the `ChannelDiff` model + table are all removed.
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

1. Phase 11 sub-specs 01b–01f — pre-publish checklist expansion, post-publish
   workflow, series/sequel tracking, video-links section polish, MCP/CLI parity.
   Architect specs locked; 01a (video edit page polish) shipped. 01b–01f queued
   for `pito-rails-impl` dispatch in sequence.
2. Phase 28 sub-spec 01b — CLI multi-version game grouping (primaries-only
   render + drill-down + flat-mode toggle + wire-format parity). Rails + MCP
   halves shipped in 01a; the `pito-rust` half is the deferred remainder.
3. Rails JSON endpoints for CLI / MCP parity across Phases 14 / 15 / 16 (Games,
   Calendar, Notifications) — gated on Phase 20 friendly URLs landing in main.
4. 2026-05-09 realignment top-level direction map — foundational reference for
   the remaining work units (tenant drop, MCP scope simplification, Channel +
   Video edit surfaces, Analytics, Game model, Calendar, Notifications, CLI
   parity).
5. CLI feature-parity sweep — channels list / videos list / settings panes /
   search results (work unit 10 in the realignment). Paused alongside the
   broader MCP / TUI work pending the realignment dispatches.
6. Analytics window-summary click-rate ratios via dedicated impressions +
   card-performance reports — `DAILY_BASIC_METRICS` and the slimmed
   `WINDOW_RATIO_METRICS` (see ADR 0011) leave three click-rate ratio columns
   `NULL` on `channel_window_summaries` / `video_window_summaries`; merging them
   in needs a separate architect spec.
7. Footage importer-side ffmpeg frame extraction + bulk PATCH upload (Phase 7.5
   spec 06 importer half).

See `docs/orchestration/follow-ups.md` for the full open list. Items above are
tracked alongside active phase work; the highest-priority ones track in flight
on each phase log.

## Glossary

- **Pito** — the application.
- **Alpha** — concluded multi-front exploratory phase.
- **Beta** — current build phase. Plans live in `docs/plans/beta/`. **Beta 3**
  is the page-by-page revamp cycle (subtraction over addition); `/settings` is
  the first page completed.
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
