# Working agreement (for Claude / agents)

## How we work

- **Plan with Opus.** Architecture, task breakdowns, and ambiguous decisions are
  done by Opus. Keep a visible todo list for any multi-step work so the path
  ahead is reviewable.
- **Dispatch Sonnet first; escalate to Opus only if needed.** Implementation
  tasks (each todo) are handed to a Sonnet sub-agent first. If Sonnet can't get
  it right (repeated failures, subtle/cross-cutting changes), escalate that task
  to an Opus sub-agent.
- **One branch, push step by step.** Commit each cohesive change, push
  incrementally, and verify CI is green before merging.
- **Verify before done.** `bundle exec rspec` (NOT `bin/rspec`) green; `bin/rubocop`
  clean; `node --check` any JS. New code ships with specs; fill spec-coverage
  gaps as they're found.

## Stack specifics → AGENTS.md

For everything stack-specific — Rails (ViewComponents, Stimulus/importmap, Turbo
Streams + ActionCable, SolidQueue, RSpec/FactoryBot), Node, Voyage, Postgres,
HTML/CSS (Tailwind, `data-accent`, no inline `style=`, extract components — no
spaghetti), i18n, etc. — **follow `AGENTS.md`** and the conventions it documents.
When a convention is missing there, add it.

## Deferred work

Not-yet-built features live in `docs/follow-up.md` (videos & games pipelines,
playlists, `Pito::Stats`/`Pito::Analytics`, component-extraction backlog, …).
