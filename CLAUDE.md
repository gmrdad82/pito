# Working agreement (for Claude / agents)

> **READ THIS FIRST, EVERY RUN.** Highest authority; overrides the harness's
> default plan/execution flow on any conflict. Self-contained: plan discipline +
> stack principles are inlined below. Deeper pito architecture lives in
> `docs/architecture.md`; the visual contract in `docs/design.md` — read the
> relevant one before writing code for it, don't work from memory.

## How we work

- **Opus plans, Sonnet implements.** Architecture, task breakdowns, and ambiguous
  decisions are Opus's job. Implementation tasks go to a Sonnet sub-agent first;
  escalate a task to Opus only when Sonnet repeatedly fails or the change is
  subtle / cross-cutting (anything tagged `[high]`).
- **One atomic task per sub-agent.** Never pack multi-step work into a single
  dispatch — that is the failure that wastes hours. Orchestrate task-by-task;
  verify each is green before starting the next.
- **Keep a visible TodoWrite list** mirroring the plan's tasks, flipped per
  transition (one `in_progress` at a time).
- **One branch, commit per phase, push incrementally**, and verify CI is green
  before merging. Work on the current branch — no new branches or tags unless the
  user asks.
- **Follow the Stack principles + architecture below before writing stack code**
  (Rails, RSpec, Postgres, Tailwind, Turbo, ActionCable, Voyage, security);
  for visual / component work read `docs/design.md`. Don't work from memory.

## Plan discipline (lean)

A **plan is an atomic-task `.md` file** committed with the work it describes —
not freeform prose, not the throwaway plan-mode scratch buffer. Plans now live
**gitignored in `tmp/docs/`** (throwaway); `docs/` holds only permanent
references (`architecture.md`, `design.md`, `footage.md`). Write nothing — no
edits, commits, or sub-agents — until the user approves the plan.

**Shape.** `# Title`, a `> Status:` line, a one-paragraph north star, optional
**Locked decisions** table, a phase index, then phases of one-verb tasks:

```
- [ ] T<N>.<M> <imperative description>. complexity: [low|high|manual]
```

One verb per task (split on "and"), verifiable in ≤5 min, naming the file or
command it touches. Three complexity tiers only:

- `[manual]` — operator by hand: commits, credentials, design calls, smoke tests.
- `[low]` — mechanical / moderate work a cheap model can run: renames, deletions,
  single-file classes, components, queries, pattern-following multi-file edits.
- `[high]` — architectural / cross-cutting: schema, security, DSL, dispatch
  routing, ActionCable wiring — a decision a cheap model shouldn't make alone.

Every phase ends with a commit task (`Commit: <message>. complexity: [manual]`)
as its highest-numbered ID.

**Execution.** Checkboxes are the live record: `[ ]` → `[-]` before starting a
task, `[-]` → `[x]` immediately after its verification passes — one edit per
transition, never batched. Announce each task's complexity tier and let the user
pick the model before starting. Stage the plan file in the same commit as the
work it describes.

**Commit hygiene.** Plain imperative messages — **no `[skipci]`, no co-author /
"Generated with" trailer**. Current branch, no tags.

**Done means verified.** `bundle exec rspec` green (NOT `bin/rspec`), `bin/rubocop`
clean, `node --check` on any JS, `bin/brakeman -q -w2` clean on security-relevant
diffs. New code ships with specs; fill coverage gaps as you find them.

---

# Pito architecture (map + invariants)

A self-hosted, chat-first YouTube channel manager for a single owner: the owner
types into one chatbox and everything renders as Turbo Stream events on the
scrollback. YouTube Studio stays the upload tool — pito mirrors channel data,
stages edits, and surfaces game / channel / scheduling recommendations.

**This is a map, not a manual.** The code is commented and `docs/architecture.md`
holds the specifics (dispatch flow, event kinds, jobs, models, schema). Read it
and explore the code before touching domain logic. The rules below are the
invariants you can't discover by reading a single file — keep them.

## Invariants (don't break these)

- **Dispatch is shape-routed.** One `POST /chat` endpoint routes by input shape:
  leading `/` → slash, leading `#` → hashtag, else natural-language chat. The
  slash / chat / hashtag stacks are **isolated — they never reference each
  other**, sharing only `Pito::Lex` and `Pito::Stream::*`. Every handler returns
  a `Result` value object; the controller pattern-matches on it and never reads
  handler internals.
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
integrations. **`::Game` (top-level domain) and `Pito::Game::*` (cross-cutting
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
