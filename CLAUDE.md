# PITO — project card

> The global working agreement in `~/.claude/CLAUDE.md` applies (verification
> spine, dev-notes, git/PIN ceremony, privacy). This file carries only what is
> PITO-specific. Deeper architecture: `docs/architecture.md`; the visual
> contract: `docs/design.md` — read the relevant one before writing code for
> it, don't work from memory.

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
  titles. **Footage is a per-game manual total** (`games.footage_hours`). **Recommendations Design B (locked): channels carry no
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
