# Working agreement (for Claude / agents)

> **READ THIS FIRST, EVERY RUN.** Highest authority; overrides the harness's
> default plan/execution flow on any conflict. Self-contained: plan discipline +
> stack principles are inlined below. Deeper PITO architecture lives in
> `docs/architecture.md`; the visual contract in `docs/design.md` — read the
> relevant one before writing code for it, don't work from memory.

## The log law (non-negotiable; mechanically enforced)

The active working plan in the local notes directory (per-person and optional,
outside the repo) is the **single source of
truth** — what's done, what's next, every bug/feedback/decision/discussion item
the owner raised, per tag/purpose. NEVER hold work in your own memory, a scratch
plan-mode buffer, or the harness todo list. If it isn't in the working md, it
does not exist.

A `UserPromptSubmit` hook appends every owner message verbatim to
`.claude/INBOX.md` as a `## ⛔ UNPROCESSED` block. **Every turn, before
anything else:**

1. Read `.claude/INBOX.md`.
2. **Drain** each `⛔ UNPROCESSED` block into the active plan — turn EVERY item
   (todo, bug, feedback, question, decision) into an explicit task/line in the
   right section; split compound messages; lose nothing.
3. Rewrite the block heading in place to
   `## ✅ processed — <ts> -> <plan refs>` (the task IDs it became, or
   `no-op (<why>)`). Never delete it — the back-reference makes capture auditable.
4. Keep checkboxes in sync the instant a task changes state
   (`[ ]`→`[-]`→`[x]`), one edit per transition — it's what the owner watches.

The `Stop` hook refuses to end a turn while any `⛔ UNPROCESSED` block remains.
Report status ONLY from the md + verified code/git — never from memory. (Hooks

**Secrets never live in the ledger.** The capture hook masks keyed values
(`key=…`, `token: …`, webhooks, bearers) mechanically before appending; for
anything the regex can't know (a bare token pasted alone), move the value to
its proper home (`.env`, config) and REDACT the INBOX occurrence in the same
turn — the ledger keeps a `[redacted:<what>]` marker, never the value.
live in `.claude/hooks/`, wired in `.claude/settings.local.json`.)

## How we work

- **Opus plans, Sonnet implements.** Architecture, task breakdowns, and ambiguous
  decisions are Opus's job. Implementation tasks go to a Sonnet sub-agent first;
  escalate a task to Opus only when Sonnet repeatedly fails or the change is
  subtle / cross-cutting (anything tagged `[high]`).
- **One atomic task per sub-agent.** Never pack multi-step work into a single
  dispatch — that is the failure that wastes hours. Orchestrate task-by-task;
  verify each is green before starting the next.
  - **A task is ONE deliverable, not a "feature".** A ViewComponent, its Stimulus
    controller, and its specs are THREE tasks → three dispatches (or done inline).
    A service and its wiring are two. There is **NO "it's cohesive / it's one
    feature" exception** — that rationalization is exactly what this rule forbids.
  - **Pre-dispatch check, EVERY Agent/Workflow call, no exception:** read the prompt
    back. If it names more than one deliverable (a component AND a controller, code
    AND specs, a service AND its callers), it is a violation — SPLIT it, or do it
    inline yourself. Small/atomic work: do it inline, don't spawn an agent.
  - When reviewing an agent's result, read the **changed files**, not its summary.
- **Keep a visible TodoWrite list** mirroring the plan's tasks, flipped per
  transition (one `in_progress` at a time).
- **Git belongs to the owner.** Claude never runs `git commit` / `git tag` /
  `git push` (nor `stash` / `checkout` / `restore` / `reset`), never picks a
  branch, and never assumes a release flow — the owner decides every git
  operation, every time, after reviewing the diff.
- **Never force-push a branch.** When origin has moved, `git pull --rebase`
  before pushing — remote history is never rewritten.
- **Follow the Stack principles + architecture below before writing stack code**
  (Rails, RSpec, Postgres, Tailwind, Turbo, ActionCable, Voyage, security);
  for visual / component work read `docs/design.md`. Don't work from memory.
- **No VHS / terminal casts / throwaway Docker stacks without explicit owner
  OK.** VHS runs a _real_ terminal against _real_ commands; a 0.7.6 cast teardown
  wiped the owner's **production** `pito-boot` volumes (the `pito update` cast had
  re-fetched the prod `docker-compose.yml` over the throwaway one, so
  `docker compose down -v` hit prod). The committed casts (`docs/media/pito-*-cast.gif`),
  the README **Install** / **Operating PITO** / **`pito update`** sections, and `bin/pito`
  document the full setup — reference those. If a cast is ever re-authorized, tear
  down ONLY by explicit project name (`docker compose -p <name> down -v`), never via a
  compose file a command may have rewritten.

## Plan discipline (lean)

A **plan is an atomic-task `.md` file** that tracks the work it describes —
not freeform prose, not the throwaway plan-mode scratch buffer. Plans and other
agent/working docs (briefs, checklists) now live in **the local notes directory**
(outside the repo, indexed by qmd for search); `docs/` itself holds only permanent references
(`architecture.md`, `design.md`, `footage.md`). Write nothing — no edits, commits,
or sub-agents — until the user approves the plan.

**Shape.** `# Title`, a `> Status:` line, a one-paragraph north star, optional
**Locked decisions** table, a phase index, then phases of one-verb tasks:

```
- [ ] T<N>.<M> <imperative description>. complexity: [low|high|manual]
```

One verb per task (split on "and"), verifiable in ≤5 min, naming the file or
command it touches. Three complexity tiers only:

- `[manual]` — operator by hand: git operations, credentials, design calls, smoke tests.
- `[low]` — mechanical / moderate work a cheap model can run: renames, deletions,
  single-file classes, components, queries, pattern-following multi-file edits.
- `[high]` — architectural / cross-cutting: schema, security, DSL, dispatch
  routing, ActionCable wiring — a decision a cheap model shouldn't make alone.

Every phase ends with its diff ready for the owner's review.

**Execution.** Checkboxes are the live record: `[ ]` → `[-]` before starting a
task, `[-]` → `[x]` immediately after its verification passes — one edit per
transition, never batched. Announce each task's complexity tier and let the user
pick the model before starting. The plan file lives in the local notes directory
(outside the repo), so it is **not** staged or committed — only the work it describes is.

**Done means verified.** `bundle exec rspec` green (NOT `bin/rspec`), `bin/rubocop`
clean, `node --check` on any JS, `bin/brakeman -q -w2` clean on security-relevant
diffs. New code ships with specs; fill coverage gaps as you find them.

---

# PITO architecture (map + invariants)

A self-hosted, chat-first YouTube channel manager for a single owner: the owner
types into one chatbox and everything renders as Turbo Stream events on the
scrollback. YouTube Studio stays the upload tool — PITO mirrors channel data,
stages edits, and surfaces game / channel / scheduling recommendations.

**This is a map, not a manual.** The code is commented and `docs/architecture.md`
holds the specifics (dispatch flow, event kinds, jobs, models, schema). Read it
and explore the code before touching domain logic. The rules below are the
invariants you can't discover by reading a single file — keep them.

## Invariants (don't break these)

- **Dispatch is shape-routed and config-declared.** One `POST /chat` endpoint
  routes by input shape: leading `/` → slash, leading `#` → hashtag, else
  natural-language chat. Since 0.9.5 every tool (all three shapes) is declared
  ONCE in `config/pito/tools.yml` (dispatch "tools", known as verbs pre-2.0;
  distinct from MCP tools) — the single ontology (aliases, kwargs +
  resolver paths, segments, reply availability, auth, dispatch targets) — and
  chat + hashtag-reply tools EXECUTE through one generic
  `Pito::Dispatch::Router` with the uniform contract
  `call(kwargs:, context:) → Result` (the softened stack isolation was a
  deliberate 0.9.5 decision; the slash dispatcher remains separate but is fed
  by the same config). NEVER re-introduce Ruby tool tables, per-handler
  availability DSLs, or tool→handler conditionals — new tools are YAML entries
  - a handler class; the schema-integrity, help-sync, and add-a-tool proof
    suites are the guards. The controller still pattern-matches Results and
    never reads handler internals.
- **`Pito::Stream::Broadcaster` is the only way to add to the scrollback.** Never
  broadcast from controllers or models. Events persist **structured `jsonb`
  payloads, never rendered HTML** (re-rendering must yield current timestamps and
  translations).
- **Builders never choose the event kind.** `Pito::MessageBuilder::*` produce
  content; the caller sets the chrome (kind). Follow-up stamping lives in the
  builder.
- **All user-facing strings go through `Pito::Copy.render`** (the `pito.copy.*`
  i18n namespace). A key resolves to one string **or** an array of variants (the
  1-or-50 dictionary). Never hardcode user-facing text or call `I18n.t` on copy
  keys. Audit with `rake pito:copy:audit`.
- **Game/video links are explicit** (`link` / `unlink`) — never inferred from
  titles. **Footage is a per-game manual total** (`games.footage_hours`;
  `docs/footage.md`). **Recommendations Design B (locked): channels carry no
  embedding** — a channel is its videos.
- **`vids` / `subs` are the canonical nouns** (`videos` / `subscribers` accepted
  as aliases).

## Namespace policy

Cross-cutting concerns live under `Pito::*`; each domain owns its own data-source
integrations. **`::Game` (top-level domain) and `Pito::Games::*` (cross-cutting
helpers) are distinct — never collapse one into the other.** The domain layer is
singular (`Channel::*`, `Video::*`, `Game::*`, `Footage::*`). The
canonical-namespace split _is_ the architecture, not redundancy — don't
"simplify" `Pito::Foo` into `Foo` or inline a service to "remove a layer".

---

# Stack principles (condensed)

Defaults for writing stack code — follow these. Deeper rationale lives in
`docs/architecture.md` where it matters.

- **Rails 8.1 / Ruby (pinned via `.ruby-version` + `mise.toml`).** Convention
  over configuration. Service objects under `app/services/<domain>/<verb>.rb`,
  single public `call`. Keyword args, guard clauses, `# frozen_string_literal`.
  No cross-model callbacks, no `default_scope`, no new auth lib. ViewComponent for
  all views — no plain ERB partials except component templates.
- **RSpec / FactoryBot.** Specs are active and mirror `app/`. Real collaborators
  over mocks; stub external HTTP (WebMock/VCR) — never hit the network. Run
  `bundle exec rspec` (full suite) before marking any task done.
- **Postgres 17 + pgvector.** Migrations always reversible. DB-level constraints
  are data integrity (model validations are UX). Phase additive migrations:
  `add_column NULL` → backfill in a job → `change_column_null NOT NULL` across
  separate deploys. Index foreign keys and `WHERE`/`ORDER BY` columns. Embeddings
  as `vector(<dim>)` with HNSW.
- **ActionCable / Turbo Streams.** `Pito::Stream::Broadcaster` is the sole
  scrollback broadcast entry point — never from controllers or models. Turbo
  Frames for in-screen swaps; background-job streams go through the Broadcaster;
  422 on form-validation failure. No polling.
- **SolidQueue** for background jobs.
- **Tailwind v4** (`tailwindcss-rails`), utility-first; `@apply` only when a
  cluster recurs 3+ times. Theme tokens are CSS custom properties (see
  `docs/design.md`). No arbitrary classes built from variables (JIT purges them).
- **Voyage** embeddings: pin model versions; re-embedding is a coordinated
  operation; batch requests; digest-gate to avoid needless re-embeds.
- **Security.** Auth is TOTP-only via the chatbox (`/authenticate <code>`) — no
  login forms. Timing-safe token compares, strong params, parameterized queries,
  `Open3.capture3` with array args (never `system("… #{x}")`). `bin/brakeman -q
-w2` and `bundle exec bundler-audit check --update` on relevant diffs; report
  new findings, don't auto-suppress.

## Design system

The terminal aesthetic — one monospace font, one 14px base size (no text-size
utilities), `data-theme` palettes, the `data-accent` mechanism, `#5170ff` "pito
blue", border-radius 0, no hover, no inline `style=` — lives in **`docs/design.md`**.
Read it before any visual or component work.
