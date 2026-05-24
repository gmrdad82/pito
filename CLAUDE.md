# pito — Claude collaboration rules

## Project at a glance

pito is a self-hosted YouTube channel management tool, used solely by the
owner. Hosted locally via cloudflared tunnels:

- `app.pitomd.com` — Rails app (primary surface)
- `mcp.pitomd.com` — MCP server (parked; future revisit)
- `pitomd.com` — Astro landing page (Cloudflare Pages)

Future deployment: Hetzner via Kamal.

Companion clients:

- **`pito` CLI** at `extras/cli/` — Rust + Ratatui. Default mode is the
  TUI. **CLI implements 100% of what the web app does.**
- **Astro landing** at `extras/website/`.

Purpose: manage titles, descriptions, thumbnails, playlists, visibility
for videos across the owner's YouTube channels. YouTube Studio remains
the upload tool (videos uploaded as Drafts there). pito brings
cross-channel analytics, scheduling, and recommendation systems for
game ↔ channel ↔ bundle pairings.

The app's mental shape: see how videos are doing, what games to play
next, server health, when to publish without competing across channels,
is this game good for this channel.

**Three screens, full stop.** Settings is dropped — its panels (security,
notifications, stack, logging, time zone) redistribute into Home.
Calendar + Notifications also live on Home. Channels fold into Videos.
Bundles + Footage fold into Games. Projects + Notes are dropped entirely.

For system, model, action-bus, cable details → `docs/architecture.md`.
For visual, keybinding, terminology contract → `docs/design.md`.

## How we work

**Plan mode is the default for non-trivial work.** Before I dispatch
agents or edit code, I read what's needed, propose a plan via
`ExitPlanMode`, you approve, then I execute. Quick lookups and explicit
single-edit corrections ("drop X from Y") skip the plan ceremony.

**Master + subagents.** I'm the master. I plan, dispatch, audit, and
commit. Subagents stay within declared file scope. I do NOT normally
read project source files directly — I dispatch the `Explore` agent for
recon. **Exception:** when you tell me to stop spending tokens on agent
layers, I read directly.

**Dispatch sizing — hard discipline:**

- **≤ 5 min is the target, not a soft preference.** If I estimate >5 min,
  I slice before dispatching, not after. The earlier slice happens, the
  fewer tokens get burned on context the agent doesn't need.
- 5–10 min = tolerated but logged as a smell. Two in a row = stop and
  re-slice the queue.
- ≥ 20 min = hard kill, redispatch.
- **One concern per dispatch.** Bundling concerns is the most common
  source of agent slippage (the agent picks the easy ones and drops the
  rest silently). If a dispatch prompt contains "AND" between concerns,
  it's two dispatches.
- **Parallel by default, sequential by exception.** If two dispatches
  touch disjoint files, they run in parallel in a single message with
  multiple Agent tool calls. Sequential only when the same surface is
  touched (race condition prevention). When in doubt about overlap,
  err on parallel — agents see their declared file scope; conflicts
  surface at audit time.
- **Maximize parallel fan-out.** A batch of 5 independent renames =
  one message with 5 Agent calls, not 5 sequential turns. The wall-clock
  saving compounds across Phase C.
- **Pre-dispatch sanity check:** before sending the prompt, ask: can the
  agent finish this with the context provided in ≤5 min? If no, slice.

**Model selection per dispatch:**

Agent definitions default to Opus (`.claude-config/agents/*.md`
frontmatter). The Agent tool also supports per-call `model` override.

- **Default = Opus** for any dispatch involving: new code, refactors that
  span multiple files, pattern conformance (ViewComponent / canonical
  namespace / cable channel grammar), spec-writing, debugging, audit
  work, security-sensitive changes.
- **Sonnet override** for **truly mechanical** dispatches: a literal
  find/replace rename pass with no naming judgment required, a
  one-attribute migration, a single CSS variable swap. Pass
  `model: "sonnet"` on the Agent call. Flag in the dispatch prompt
  that the work is mechanical so the agent doesn't over-reason.
- **Never Haiku** for agent work — even mechanical work involves spec
  assertions and gate conformance; Haiku slips on those.
- When in doubt, default to Opus. The cost difference of one Opus
  dispatch is dwarfed by the cost of an unnoticed regression that
  requires re-dispatch.

**6-gate audit before surfacing any agent delivery to you:**

1. **Success** — agent reported success + smoke check green?
2. **Specs** — **DEFERRED during rebuild phase.** The codebase is being
   rebuilt piece-by-piece on the locked architecture; specs will be
   re-introduced fresh once the structural rebuild settles. During
   rebuild, agents do NOT write specs and do NOT run specs. This gate
   resumes its hard form (every module has a passing spec) when the
   user signals "rebuild settled — re-introduce specs".
3. **Docs** — every new module / class / job / component has a class-level
   docblock header (purpose, kwargs, variants, focusables, mode behavior,
   cable subscriptions, related dependencies)? No docs → re-dispatch.
4. **ViewComponent discipline** — UI work uses a ViewComponent (never raw
   `<button>` / `<div>` with inline classes) AND conforms to the visual
   rules in `docs/design.md` (border-radius 0, no hover, no inline CSS,
   terminology, brand caps, accent group)?
5. **Job discipline** — Sidekiq jobs conform to the rules in
   `docs/architecture.md` (locking for non-idempotent work, panel cable
   broadcasts via `Pito::CableBroadcaster`, payload envelope, schedule in
   `sidekiq-cron.yml` if periodic, idempotent retries where applicable)?
6. **Module discipline** — Every Ruby module / class has ONE clear purpose
   and lives in the right namespace per the canonical taxonomy below.
   No helper-magic spaghetti. Helpers reserved for single-purpose pure
   logic.

If any gate fails: I re-dispatch with the specific failure, or self-fix.
Spaghetti never reaches you.

**Look up, never pick.** I never invent values. Subagents never default
to "sensible". Every dispatch names the canonical source for every value.
If the canonical doesn't have the answer, I stop and ask.

**Iteration vs consolidation.** Iteration agents write code only (no
specs, no test runs). Consolidation passes add the deferred specs, run
the suite, reconcile drift. Default = iteration. Consolidation triggered
by your "consolidate" / "validate" / "lock this in".

**One-by-one when you signal "stop".** If you say "do 1 thing at a time"
or "stop the queue", I stop dispatching and go single-track until you
reopen the queue.

## Canonical namespace policy

The rule: **cross-cutting concerns live under `Pito::*` unless a screen
or a domain claims them.** Data-source integrations are claimed by the
domain they feed.

### Cross-cutting infrastructure (`Pito::*`)

- `Pito::ActionRegistry` — action bus registry
- `Pito::ActionDispatcher` — Ruby-side action dispatcher (parity with
  JS `window.Pito.dispatchAction`)
- `Pito::CableBroadcaster` — cable envelope + channel grammar enforcement
- `Pito::Theme` — Dracula L1–L4 token system + Rust theme.rs export
  - `Pito::Theme::Sections` — screen→accent mapping
- `Pito::GitRevision` — build metadata
- `Pito::Auth::*` — auth flows
- `Pito::Formatter::*` — data→string transformations
- `Pito::Notifications::*` — notification system
- `Pito::Search::*` — `Engine`, `Omnisearch`, `Everywhere`
- `Pito::Calendar::*` — calendar derivation + milestone evaluator
- `Pito::Analytics::*` — cross-cutting analytics primitives
- `Pito::Recommendation::*` — shared recommendation primitives
  (VectorSimilarity, TopK, HmsScorer, WeightedBlend)
- `Pito::ExternalApiTracker::*` — per-client quota tracking
  (Youtube, Igdb, Voyage)
- `Pito::Schedule::*` — cross-channel scheduling (Conflict)
- `Pito::SlugBuilder`, `Pito::TimeZone`, `Pito::TokenDigest`,
  `Pito::PublicHosts`, `Pito::AssetsRoot`, `Pito::SafeEach` — utilities

### Home screen — under `Pito::*`

Home is not a "domain" — it's the dashboard + system-monitoring surface.
It has no `Home::*` namespace. Home's services live under `Pito::*` (the
cross-cutting namespace IS home's namespace). The ex-settings panel
services (e.g., `Pito::Stack::HealthState` — formerly
`Settings::Stack::HealthState`) live here.

Home's panel ViewComponents live directly under `Pito::*PanelComponent`
(NOT `Screen::Home::*PanelComponent`). Examples:
`Pito::SecurityPanelComponent`, `Pito::StackPanelComponent`,
`Pito::NotificationsPanelComponent`, `Pito::CalendarPanelComponent`,
`Pito::AggregatorPanelComponent`, `Pito::PersonalStatsPanelComponent`,
`Pito::ApiQuotaPanelComponent`.

Settings as a namespace is gone for good.

### Domain layer (singular)

- `Channel::*` — `Channel::Youtube::*` (OAuth, clients, diff),
  `Channel::Analytics::*`, `Channel::GameRecommendation`,
  `Channel::BundleRecommendation`, `Channel::VoyageIndexer`,
  `Channel::MeilisearchIndexer`
- `Video::*` — `Video::Analytics::*`, `Video::ThumbnailPreview`,
  `Video::DiffComputer`, `Video::PublishWorkflow`
- `Game::*` — `Game::Igdb::*`, `Game::ChannelRecommendation`,
  `Game::BundleRecommendation`, `Game::SimilarGames`,
  `Game::VoyageIndexer`, `Game::MeilisearchIndexer`
- `Bundle::*` — `Bundle::Composite::*` (cover composite),
  `Bundle::ChannelRecommendation`, `Bundle::SuggestedFor`,
  `Bundle::VoyageIndexer`, `Bundle::MeilisearchIndexer`
- `Footage::*` — `Footage::FrameExtractor`, `Footage::Cache`. Attached
  directly to Game (no Project intermediary).

### Screen layer (Panel-as-ViewComponent)

Three screens, three ViewComponent namespaces:

- **Home (`/`) → `Pito::*PanelComponent`** (no `Screen::Home::` wrapper).
  Panels include: Security, Notifications (delivery channels), Stack
  (+ sub-panels), Logging, TimeZone (ex-settings), plus Aggregator,
  Calendar, NotificationsFeed (in-app), PersonalStats, ApiQuota
  (home-native).
- **Videos (`/videos`) → `Screen::Videos::*PanelComponent`** — List,
  Edit, Analytics, ThumbnailPreview, ScheduleConflict.
- **Games (`/games`) → `Screen::Games::*PanelComponent`** — Catalog,
  Detail, Bundles, BundleDetail, Footage.

Each Panel VC owns:
- `focusables` method (ordered Ruby array)
- `CABLE_CHANNEL` constant (e.g., `"pito:settings:security"`)
- `keybinds` method (i18n-resolved for TUI sharing)
- Sub-panel VC composition (explicit `render` in template)
- Data fetched in `initialize` / `before_render` via domain / screen
  services

### UI primitive layer (`Tui::*`)

Reused by every panel. Checkbox, dialog, palette, sortable header,
charts, indicators, table primitives, etc.

## Hard rules

**ViewComponents are kings.** Every visible HTML structure is a
`ViewComponent` — even one-off. No raw `<button>` / `<div>` with inline
classes. Modifying something means modifying the canonical component or
expanding its kwargs / variants — never forking.

**Every module / class / job / component has a docblock header.** A
class-level comment that documents: purpose, kwargs, variants,
focusables, mode behavior, cable subscriptions, related dependencies.
A Claude agent building the TUI equivalent reads the docblock and
re-derives the contract.

**Every module / class / job / component has a passing spec.** Mandatory
**after** the rebuild phase settles. **Currently suspended:** the
codebase is being rebuilt on the locked architecture; the `spec/`
directory will be purged as part of the rebuild. Agents do not write or
run specs during this phase. This rule resumes when the user signals
"rebuild settled — re-introduce specs".

**One module = one purpose.** `Pito::Formatter::*` formats. Jobs do
Sidekiq work. ViewComponents render HTML. Services orchestrate. Helpers
are pure single-purpose logic only.

**Action bus is canonical.** Every user-triggerable action flows through
`Pito::ActionRegistry` + `window.Pito.dispatchAction` (JS) /
`Pito::ActionDispatcher` (Ruby). No inline-POST from Stimulus.

**Cable channel grammar.**

- `pito:status_bar` — global TST stream
- `pito:<screen>:<panel>` — panel-scoped
- `pito:<screen>:<panel>:<sub_panel>` — sub-panel-scoped

Every panel subscribes to its own stream when painted. Sidekiq middleware
broadcasts START + END. Jobs broadcast panel-scoped via
`Pito::CableBroadcaster`.

**Turbo everywhere.** Every form Turbo-default; no `data-turbo="false"`.
Panel actions return `head :no_content` / `render turbo_stream:` /
`turbo_frame`. Never `redirect_to` from a panel-scoped action.

**Sidekiq job locking.** Long-running or non-idempotent jobs acquire a
Sidekiq lock so two instances cannot run in parallel. Locked-out callers
see the running state via cable.

**No Capybara.** No system specs. No feature specs. No browser-driven
tests, now or ever. Specs stay in request / model / service / component /
Sidekiq layers. Stimulus contracts documented in JS file header docblocks.

**No `alert()` / `confirm()` / `prompt()` / `data-turbo-confirm`.** Every
destructive or significant action goes through
`Tui::ConfirmationDialogComponent` (web) + `confirm: bool` (MCP) +
in-TUI overlay (Rust). Exception: browser-native `beforeunload` for
unsaved-changes navigation guards.

**Secrets in `Rails.application.credentials`.** Never in `.env*` files.

**Yes / no for external booleans.** Every URL param / JSON / MCP I/O /
Rust wire boolean is `"yes"` / `"no"`. Convert at boundaries.

**Mouse guard.** Keyboard-only. Real mouse activity (click, select,
movement, viewport-enter) triggers `Tui::AlertDialogComponent`. Every
action and feature must be operable via keyboard in NORMAL or INSERT
mode (or both). Keyboard-fired clicks and programmatic Stimulus
`.click()` pass through.

**All copy via i18n.** All user-visible strings in
`config/locales/**.yml`. The same YAML feeds the TUI.

**Keybindings shared between web + TUI** with one exception: `q` quits
the TUI; no web equivalent.

**Actions are always section accent color.** Every bracketed action —
`[reindex]`, `[resync]`, `[schedule]`, `[month]`, `[update]`, `[help]`,
`[ ] sync` / `[x] sync` / `[-] sync` / `[!] sync`, the progress slot
during reindex — paints in `var(--section-accent)`. Idle, active,
hovered, or otherwise — actions speak the section's accent voice.
Non-action chrome (titles, hints, delimiters, muted labels) stays in
its own token. The `[!] sync` disconnected state is the one exception
(red `var(--color-danger)`). Locked 2026-05-24.

**Text-color taxonomy (the only 3 colors UI text ever takes).** Locked
2026-05-24. Apply globally; never per-screen patch.

| Role | Color | Examples |
|---|---|---|
| **Data values** | `var(--color-text)` (white/light) | table cell numbers, names, content — the stuff the user came to see |
| **Labels / hints / captions / headers** | `var(--color-muted)` | column headers ("docs", "size"), kv-table label column ("model", "last indexed"), section labels ("Discord", "webhook URL:"), help hints ("type 'clear' to remove"), placeholders |
| **Titles + actions** | `var(--section-accent)` | panel + sub-panel titles, bracketed actions (`[reindex]`, `[ ] sync`, `[update]`, etc. — see the actions-accent rule above) |

The `[ ] label` checkbox-with-label is treated as ONE action — both
the bracket AND the label paint in accent. Independent "label" text
NOT attached to an action stays muted.

Disconnected `[!] sync` red is the one exception (red danger). All
other text in the UI MUST map to one of the three above. Inventing a
new role-color pair is a code smell — extend the taxonomy in design.md
before adding a fourth.

**Stack sub-panels are a 2×2 50/50 grid.** Meilisearch / Voyage AI /
Postgres / Assets each occupy exactly one quadrant of the Stack panel,
both horizontally AND vertically. Each sub-panel stretches to fill its
grid cell — no whitespace gap below the bottom row, no column drift.
Sub-panels with shorter content still own their full cell height; tall
content scrolls inside the sub-panel. Locked 2026-05-24.

**Bracket-to-space rule on TST chrome.** Where a non-action label sits
in an actions slot adjacent to a bracketed action (e.g. `month` next to
`[schedule]`), use a literal space pair around the label instead of
brackets — `month [schedule]` not `[month] [schedule]`. Keeps the
accent-color rule readable as "brackets = action" without painting a
color rainbow across multiple bracketed items. Locked 2026-05-24.

**Brand capitalization.** Always capitalize: Slack, Discord, YouTube,
Voyage AI, Meilisearch, PostgreSQL, Redis, Chrome, Firefox, Safari,
Linux, macOS, Windows, Android, iOS. Non-brand words lowercase.

**Terminology — locked.**

| Use this | Not this |
|---|---|
| screen | page |
| panel | pane |
| sub-panel | section |
| dialog | modal |
| action | button, link |
| hint | caption, text |

"Page" remains permitted only for paginated result navigation ("page 2
of 5").

**Source of truth hierarchy.** Higher wins on conflict; lower gets fixed.

1. User decision in chat (capture to docs immediately)
2. `docs/architecture.md` / `docs/design.md` / `docs/mcp.md` /
   `docs/tui.md` / `docs/website.md`
3. Code

Memory is for ephemeral / user-preference only. Rules live in docs.

## Task flow

1. **You ask.** Free-form request, image, or bug report.
2. **Plan.** Plan mode for non-trivial work. I read what's needed (via
   `Explore` agent or direct read on your signal), propose a plan, you
   approve.
3. **Dispatch.** Small focused agents (≤ 5 min, one concern, parallel
   where safe). Iteration mode = code only.
4. **Audit.** I run the 6-gate checklist on each delivery. Re-dispatch
   or self-fix if any gate fails.
5. **Surface.** Concise validation list (chat or
   `tmp/<scope>-validation-<date>.md` for bigger batches).
6. **Validate.** You walk the list per-item. ✅ / ❌ / 🔁 / 🆕 / ?.
7. **Loop.** I dispatch fixes for ❌ / 🔁 / 🆕 items.
8. **Commit.** When you signal "commit", I commit. `[skipci]` default
   unless you say "unblocked" (CI uses one of your 2000 monthly credits).

**Commit message format:**

```
[skipci] concise title (≤ 72 chars, looks good in GitHub)

- major thing 1
- major thing 2
- major thing 3
```

No Co-Authored-By. No Claude Code authorship mention. Commit fast and
often. Commit directly to `main`; no branches, no PRs.

## Agent roster

The project ships custom agents under `.claude-config/agents/`. Each
has a declared file scope and a single responsibility. Master dispatches
the right one for the job; never the generic `general-purpose` when a
named agent fits.

### Read-only / planning

| Agent | Purpose | When to dispatch |
|---|---|---|
| `Explore` | Read-only codebase search across multiple files. Returns structured findings. | Open-ended recon: "where does X live", "what patterns are used here", "audit Y across the tree". Default in plan mode Phase 1. |
| `Plan` | Software architect — designs implementation plans. Read-only. | Complex implementation strategy needed. Returns step-by-step plan + critical files + trade-offs. |
| `pito-auditor` | Read-only gap report comparing repo reality to phase plans. | Ground-truth checks: "where are we really", suspected drift between docs and code. |

### Implementation

| Agent | Surface | When to dispatch |
|---|---|---|
| `pito-architect` | Writes feature specs under `tmp/specs/<slug>.md` (gitignored). | A new feature needs a self-contained spec before any code is written. |
| `pito-rails` | Implements Rails / web features. ERB, Stimulus, controllers, models, services, ActionCable, RSpec. Writes directly to `main`. | Any backend / web work for the Rails app. The workhorse. |
| `pito-rust` | Implements Rust crate / CLI work in `extras/cli/`. | Future TUI work or any CLI-side change. |
| `pito-astro` | Astro landing page in `extras/website/`. Targets Cloudflare Pages. | Landing page changes + Cloudflare deploys. Owns the deploy flow (reads creds via Rails credentials). |
| `pito-mcp` | MCP tool surfaces on the MCP Puma. | MCP tool additions after backend has landed. |

### Review + safety

| Agent | Purpose | When to dispatch |
|---|---|---|
| `pito-reviewer` | Runs the standard review pipeline (code review + simplify + test suite + security static + dep audit). Writes manual test playbook to `tmp/playbooks/<date>-<slug>.md` (gitignored). | After an implementation agent reports done, before user validates. |
| `pito-security` | `/security-review` against the current diff. Writes findings to `tmp/security-<date>-<slug>.md` (gitignored). | After reviewer reports clean, before user merges sensitive features (auth, scoped tokens, OAuth, MCP scope changes, rate limiting, CSP). |
| `code-simplifier` | Simplifies code while preserving functionality. | When recently modified code feels dense or duplicated. |

### Communication + maintenance

| Agent | Purpose | When to dispatch |
|---|---|---|
| `pito-slack` | Sends Slack messages to `#pito-app`. Reads `docs/agents/slack.md` for style + channel. | Any user-facing ping (task completed, blocker). Never call MCP Slack tools directly. |
| `pito-docs` | Keeps docs in sync with reality after a feature lands. Writes only under `docs/`. | After an implementation agent reports done, before user merges, if docs need updates. |

### Built-in (Anthropic-provided)

| Agent | Purpose |
|---|---|
| `general-purpose` | Catch-all for tasks that don't fit a named agent. Use sparingly — prefer named agents. |
| `claude` | Default when no agent name is typed. |
| `claude-code-guide` | Answers questions about Claude Code itself, the Agent SDK, the Claude API. |
| `statusline-setup` | Configures the user's Claude Code status line. |

### Dispatch rules

- **Plan mode** allows `Explore`, `Plan`, and any read-only agent. Other
  agents inherit the read-only constraint while plan mode is active.
- **One named agent per dispatch** when a fit exists. Bundling concerns
  into `general-purpose` is a smell.
- **Slack** always goes through `pito-slack`; never via direct MCP tool.
- **Cloudflare deploys** always go through `pito-astro`; never via
  direct `wrangler`.
- Per-agent stubs in `docs/agents/<name>.md` carry the full scope + file
  boundaries + style contract for each.

## CLI + MCP scope

- **CLI** (`extras/cli/`, Rust + Ratatui) — **100% web parity**. The 3
  screens (home / videos / games) all render in the TUI. Screen export
  rake task derives Ratatui spec from each Panel VC.
- **MCP** (`mcp.pitomd.com`, parked) — **narrower scope, analytics-first**.
  Initial surface: `Pito::Analytics::*` + `Channel::Analytics::*` +
  `Video::Analytics::*`. Other tools added as needs surface.

## Communication

- Emojis liberal in chat (✅ done · ⏳ in flight · 🚫 blocked · ⚠️ conflict
  · 🎯 milestone · 🔍 inspecting · 🧪 specs · 🚀 next · ✨ delivered ·
  🎉 phase closes). Never in code / commits / docs / specs / locales.
- Chat is the detail surface. Slack is signal-only.
- Slack pings always go through the `pito-slack` agent to `#pito-app`
  (channel ID `C0B18G4E25B`). One ping per task event:
  completed-awaiting-validation OR blocker needing your input.
- Concise responses. Short sentences. No padding.

## Pointers

- `docs/architecture.md` — system topology, auth, datastore, models,
  action bus, cable, background jobs, namespace taxonomy detail
- `docs/design.md` — visual contract, terminology, mode model,
  keybindings, brand caps, demo references in `tmp/*.html`
- `docs/mcp.md` — MCP tool surface, scopes, wire format
- `docs/tui.md` — Rust client contract, screen export, parity tests
- `docs/website.md` — Astro / pitomd.com build + deploy
- `docs/agents/` — per-agent stubs (slack, astro, architect, rails, rust,
  mcp, security, reviewer, auditor, docs, testing)
