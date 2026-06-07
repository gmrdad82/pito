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

## Plan files: author in plan mode, runner when coding

We work from atomic-task plan files (e.g. `docs/themes.md`). Two disciplines,
canonical docs in `~/.config/opencode/agent/` (source: `~/Dev/agents`):

- **In plan mode → follow `plan-author.md`.** When drafting, updating, or auditing
  a plan, produce its format: `# Title` + `> Status:` + a **Sign-off** block
  (`[x] Drafted`/`[ ] Audited`), North star, Locked decisions, a Phase index, and
  phases of one-verb tasks `- [ ] T<N>.<M> … complexity: [manual|low|high]` (≤5 min
  each, no "and"). Every phase ends with a `Commit:` task (`[manual]`). Audit mode
  runs the A–G checks and only stamps the `Audited` line on a clean pass.
- **When coding → follow `plan-runner.md`.** Execute against the plan with
  three-state checkboxes flipped per transition, each its own edit:
  `[ ] → [-]` when starting a task, `[-] → [x]` when done. The phase's `Commit:`
  task flips to `[x]` **before** `git commit`, and that commit **stages the plan
  file alongside the code**. Commit messages are plain imperatives — **no
  `[skipci]`, no co-author trailer**. Plans run on the **current branch** (no new
  branch, no tags) unless asked otherwise. Don't start a phase whose plan isn't
  signed off.

## Stack specifics → AGENTS.md

For everything stack-specific — Rails (ViewComponents, Stimulus/importmap, Turbo
Streams + ActionCable, SolidQueue, RSpec/FactoryBot), Node, Voyage, Postgres,
HTML/CSS (Tailwind, `data-accent`, no inline `style=`, extract components — no
spaghetti), i18n, etc. — **follow `AGENTS.md`** and the conventions it documents.
When a convention is missing there, add it.

## Deferred work

Not-yet-built features live in `docs/follow-up.md` (videos & games pipelines,
playlists, `Pito::Stats`/`Pito::Analytics`, component-extraction backlog, …).
