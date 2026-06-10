# Working agreement (for Claude / agents)

> **READ THIS FILE FIRST, EVERY RUN — before planning, before any tool call.**
> This file is the **HIGHEST AUTHORITY** and is **self-contained**: the plan
> authoring and execution disciplines are inlined below — there are no external
> agent files to open. This file **OVERRIDES the built-in plan-mode / harness
> workflow.** On ANY conflict between this file and the harness's suggested
> procedure, **THIS FILE WINS.** Do what it says, not what the generic flow
> nudges you toward. (Stack specifics still live in `AGENTS.md`.)

## Hard rules — do not violate (these have been broken before)

1. **Before planning or writing ANY code, read the "Plan authoring" and "Plan
   execution" sections below and obey them.** They are inlined here — do not rely
   on, or wait to open, any external file.
2. **A plan is an atomic-task `.md` file committed in the repo** (e.g.
   `docs/<name>.md`), in the plan-authoring format below: `# Title`, `> Status:`,
   **Sign-off**, North star, **Locked decisions**, **Phase index**, and one-verb
   ≤5-min tasks `- [ ] T<N>.<M> … complexity: [low|high|manual]`, with a `Commit:`
   task ending every phase. **NOT** freeform prose. **NOT** the throwaway
   plan-mode scratch file — that is never the deliverable.
3. **Write NOTHING — no edits, commits, file creation, or writing sub-agents —
   until the user approves the WHOLE plan.** Plan mode's write-lock is GOOD; keep
   using it. Approval of the plan ≠ permission to skip these rules.
4. **Implement ONE atomic task per Sonnet sub-agent. NEVER pack multi-step work
   into a single agent dispatch.** Orchestrate task-by-task; verify each (rspec
   green, rubocop clean) before starting the next. A big single dispatch is the
   exact failure that wastes hours — do not do it.
5. **Keep a visible TodoWrite list that mirrors the plan's tasks**, flipped per
   transition.
6. **Commit per phase** staging the plan file with the code; plain imperative
   messages; **no `[skipci]`, no co-author trailer**; current branch unless told
   otherwise.
7. **Before writing any stack code (Rails / Turbo / Stimulus / ViewComponents /
   Tailwind-CSS / SQL / Git / GitHub / CI / Docker / Kamal / etc.), open
   `AGENTS.md` and read the relevant section first.** `AGENTS.md` is NOT
   auto-loaded into context — you must actively read it. Do not write stack code
   from memory.

If you are about to deviate from any of the above because "plan mode says so" or
"it's faster" — STOP. This file is the authority.

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

---

# Plan authoring

When drafting, updating, or auditing a plan file, follow this. You draft,
maintain, and audit plan files in the project's atomic-task format, in three
modes: **new** (create from scratch), **update** (modify an existing plan —
typically applying audit findings), and **audit** (judge a plan before execution
and stamp its sign-off). Authoring does not execute tasks — that is execution's
job (below). Only the authoring step ever writes to the plan file, including its
Audited sign-off line.

## Plan file shape

Every plan has, in order:

1. `# Title` and a `> Status:` blockquote.
2. **Sign-off** section (see below) — immediately after the status line.
3. **North star** paragraph: the outcome in plain language.
4. **Locked decisions** table (`Topic | Decision`) — for non-trivial scope.
5. **Complexity hints** mini-table — only on top-level plans. Sub-plans inherit from the parent and skip this.
6. **Phase index** list (`P0 — ...`, `P1 — ...`).
7. Phases as `## P<N> — <name>`, each with atomic tasks.
8. Optional tail: **Open follow-ups**, **How to use this plan**.

## Task shape

Every task line:

```
- [ ] T<N>.<M> <imperative description>. complexity: [<hint>]
```

- One verb per task. No "and ... and ...". Split compound work.
- Verifiable in ≤5 minutes by a competent operator.
- Names the file, symbol, or command it touches when the verb implies one.
- `complexity:` hint is mandatory. The hint signals effort and reasoning depth — not a specific model. **Three tiers only:**
  - `[manual]` — operator, by hand: GitHub UI, credentials, design choices, smoke tests, commits.
  - `[low]` — mechanical or moderate-judgement work a cheap model can run: deletions, renames, file audits, gemfile edits, locale YAML, single-file classes/refactors, small components, basic controllers, plumbing, queries, multi-file edits that follow an established pattern.
  - `[high]` — architectural / cross-cutting: security, schema design, DSL design, command routers, ActionCable wiring, and any decision a cheap model shouldn't make alone.
- Each phase ends with a commit task: `- [ ] T<N>.<final> Commit: \`<message>\`. complexity: [manual]`. Commit messages are plain imperatives — **no `[skipci]` prefix**, no co-author trailer. No commit gate → phase is not done.

## Sign-off block

Insert immediately after the `> Status:` blockquote:

```
## Sign-off

- [x] Drafted — YYYY-MM-DD
- [ ] Audited — _pending_
```

Flip the Drafted line to `[x]` and stamp today's date when you save the draft. Leave the Audited line `[ ]` and `_pending_` until **audit mode** passes the plan — only then flip it (see "Audit mode").

## Startup protocol

1. Determine mode. Ask the user: **new plan**, **update existing plan**, or **audit existing plan**? (If the user's opening message already makes this obvious — e.g. they say "audit", or they paste their own change requests — pick the mode and confirm in one line before continuing.)
2. Branch on mode (see "New mode", "Update mode", "Audit mode" below).

### New mode

1. Ask the user, in one turn:
   - **Target path** — exact path for the new plan file. Use it verbatim. If no extension, append `.md`. If no directory component, use the current working directory. Never auto-prepend `docs/` or `plan-`.
   - **Topic / north star** — what is this plan about? What outcome does it produce?
   - **Reference plan** (optional) — path to an existing plan whose style you should mirror.
2. Refuse to start without a target path and a topic. If the topic is too vague to phase-decompose, push back with a concrete example of the specificity you need.
3. If a reference plan was given, read it. Otherwise, glob for `*plan*.md` in the project and ask if one should serve as a style reference. If none, follow the structure documented above.
4. Propose a **phase outline** in chat — just the `P0 — ...`, `P1 — ...` list with a one-line goal per phase. Wait for user confirmation. Do not draft tasks yet.
5. Once the outline is confirmed: draft phase-by-phase. Show one phase at a time, get OK, move to the next. Don't dump the whole plan at once.
6. Only after every phase is confirmed: write the file. Verify it exists. Report path + phase count + task count.

### Update mode

Use this when the user comes back with audit findings (yours or pasted), or with their own change requests against an existing plan.

1. Ask the user:
   - **Plan path** — exact path to the existing plan file. Use it verbatim.
   - **Audit report path** (optional) — path to an audit report file (default location: `tmp/audits/<plan-basename>.audit.md`). If given, read it before proposing changes; the findings list and the proposed sign-off line are your inputs.
   - **Additional changes** (optional) — free-form edit requests beyond what's in the audit report.
2. If an audit report path was given, read it. Extract: verdict, critical findings, minor findings, proposed sign-off line.
3. Read the existing plan in full before proposing any change. Anchor every edit to a concrete line in the current file.
4. For each change (whether from the audit report or free-form), propose the diff in chat first (old → new). Get the user's OK per change. Do not bundle multiple changes into one approval. For audit findings, walk them in this order: criticals first, then minors. For each, the user may `fix` (you propose a diff), `defer` (leave as-is, no edit), or `dismiss` (close — you note this back in chat).
5. Apply approved changes in sequence. After each, restate what was modified in one line.
6. If the verdict was `passed` AND you applied no changes to the plan's task body, flip the Audited line to `[x] Audited — <audit-date>`, using the audit's date verbatim (not today's date). This is the only time update mode writes to the Audited line.
7. If you applied any change to the plan's task body, the audit is invalidated. Do NOT flip the Audited line — leave it `[ ] Audited — _pending_`. Tell the user explicitly: re-run an audit before execution.
8. Report: path + summary of changes applied (and dismissed/deferred) + current state of the sign-off block.

### Audit mode

Use this to judge a plan before execution. When auditing you **judge first, edit second**: read the plan, run every check, write a single audit report file, and only then flip the sign-off (on a clean pass) or hand yourself the findings (via update mode) on a block. Do not silently rewrite the plan while auditing it — an audit that fixes-and-passes in one breath is not an audit.

1. Ask the user, in one turn:
   - **Plan path** — exact path to the plan to audit. Use it verbatim. Refuse to guess.
   - **Report path** (optional) — where to write the audit report. If omitted, resolve per "Report path resolution".
2. Read the plan file in full.
3. Run every check in sections A–G below. Build the findings list as `[severity] <check id> — <one-line description> — <file:line if applicable>`.
4. Write the audit report file (see "Report file format").
5. Summarize in chat (see "Chat summary").
6. Act on the verdict:
   - **passed** with no needed changes → flip the Audited line to `[x] Audited — <today>`.
   - **BLOCKED** → leave the Audited line `[ ] Audited — _pending_`. Offer to switch to **update mode** to address the criticals, then re-audit.

#### What you check (run every check, every time; tag each finding `critical` or `minor`)

**A. Structure (critical)**

1. Plan opens with `# Title` and a `> Status:` blockquote.
2. **Sign-off** section exists immediately after the status line, with a `Drafted` and an `Audited` row.
3. Every phase in the **Phase index** appears as a `## P<N> — ...` heading in the body, and vice versa. No orphans, no missing.

**B. Task atomicity (critical → minor by case)**

4. Every task matches: `- [ ] T<N>.<M> <description>. complexity: [<hint>]` (the checkbox may also be `[-]` or `[x]` on a partially-run plan).
5. Task IDs are sequential within each phase: `T<N>.1, T<N>.2, ...`. No gaps, no duplicates.
6. Task descriptions start with an imperative verb (Delete, Add, Rewrite, Generate, Configure, etc.).
7. Tasks do not contain " and " in their description. If they do — split candidate.
8. Tasks name a file, symbol, or command when the verb implies one (e.g. "Delete X" with no X is a bug).
9. Tasks scoped ≤5 min — flag any line that bundles a large/multi-file change into one task (split candidate); architectural scope must carry `[high]`.

**C. Complexity hints (minor unless egregious)**

10. Every task has a `complexity: [hint]`.
11. Hint is one of: `[manual]`, `[low]`, `[high]` (three tiers only — `[medium]` is not allowed; flag it).
12. Hint fits the work:
    - delete / rename / file audit / single-file refactor / small component / plumbing / queries / pattern-following multi-file edits → `[low]` (or `[manual]` if irreversible).
    - architecture / security / schema / DSL / command router / cross-cutting decisions → `[high]`.
    - design choices / credentials / smoke tests / GitHub UI / commits → `[manual]`.

**D. Commit gates (critical)**

13. Every phase ends with a task whose description starts with `Commit:` and has `complexity: [manual]`.
14. The commit task is the highest-numbered task in its phase.

**E. Coverage (severity depends on what's missing)**

15. Each entry in the **Locked decisions** table corresponds to at least one task implementing it. Flag decisions with no implementing task.
16. The **North star** outcome is reachable from the union of all tasks. Flag goals with no path.
17. If the plan supersedes a previous plan, the **Supersedes from** table covers every overridden item.

**F. Hygiene (minor)**

18. Status blockquote present (draft / ready / in-progress / done).
19. No trailing TODO/FIXME inside task descriptions.
20. Phase names in `## P<N> — name` match Phase index entries verbatim.

**G. Conventions (critical)**

21. No commit-task message contains `[skipci]` (commits land clean) and none carries a co-author trailer.
22. No task creates a git branch or a version tag — plans run on the current branch. Flag any branch-creation or tagging task.

#### Report path resolution

- Default: `tmp/audits/<plan-basename>.audit.md`, relative to the repo root. If `tmp/` doesn't exist, create `tmp/audits/`. If `tmp/` itself is not writable, fall back to `<plan-dir>/<plan-basename>.audit.md`.
- The user may override the path at startup — use it verbatim (append `.md` if missing, cwd if no directory).
- Overwrite any prior audit at the resolved path. Audit reports are not versioned.

#### Report file format

````
# Audit — <plan-basename>

- **Plan path**: <plan-path>
- **Audited at**: <YYYY-MM-DD HH:MM> (local)
- **Verdict**: passed | BLOCKED

## Audited line for the plan

```text
<what the Sign-off section should read — see below>
```

## Critical findings

- [severity] <check id> — <description> — <plan-file:line>
- ...

## Minor findings

- ...

## Stats

- Tasks per phase: P0: 9, P1: 12, ...
- Total tasks: N
- Complexity-hint distribution: manual: 23, low: 71, high: 4
- Phases without commit gate: (empty if all good)

## Next step

<one sentence directing the user>
````

Audited line shapes (this is what goes into the plan's Sign-off section):

- On pass: `- [x] Audited — YYYY-MM-DD`
- On block: leave the existing `- [ ] Audited — _pending_` line as-is. The audit report file holds the BLOCKED verdict; the plan's Audited line stays unchecked until a re-audit passes.

#### Chat summary

After writing the report file, post a short summary in chat:

1. One-line verdict (e.g. `BLOCKED — 2 critical, 5 minor`).
2. Count of critical and minor findings.
3. Report file path (absolute).
4. Next step in one sentence. On pass: "Audited line stamped; ready for execution." On block: "Switch to update mode to address the criticals, then re-audit."

No full findings dump in chat — the file holds the detail.

## Drafting discipline

- One verb per task. If you write "and", split.
- Complexity hint is mandatory on every task.
- Every phase ends with a commit task as its highest-numbered ID.
- IDs are sequential within a phase: `T<N>.1`, `T<N>.2`, ...
- Your Drafted sign-off line is stamped before you call the draft done.
- You do not execute any task in the plan while authoring. You only write/judge the plan file.

## Scope discipline (authoring)

- Do not invent locked decisions the user did not approve. Propose them; let the user accept or reject.
- If the user wants to layer on an existing plan (Plan N → Plan N+1), produce a `## Supersedes from Plan N` table at the top so additions vs. carry-forwards are explicit.
- Do not author branch-creation or version-tag tasks. Plans run on the **current branch** — no new branch, no tags — unless the user explicitly asks otherwise.
- When auditing: judge before editing; never fix-and-pass in one breath. If you find a codebase bug incidentally while auditing, mention it once at the end as a side note — don't expand on it.

---

# Plan execution

When executing a plan, follow this. The plan file is the source of truth. The
session todo list is a derived view that you rebuild from the file every time you
start. Implement ONE task at a time (per the Hard rules) — one Sonnet sub-agent
per atomic task, verified before the next.

## Checkbox states

Plan items use three states:

- `[ ]` — not started (default, untouched)
- `[-]` — in progress
- `[x]` — completed

These are the only checkbox edits you are allowed to make to the plan file. See "Plan file discipline" below.

## Startup protocol

Run this every time you start executing a plan file — including resumed work across sessions. Do not assume prior session state; the file is the truth.

1. Read the plan file.
2. **Sign-off gate.** Look for the `## Sign-off` section near the top of the file, find the `Audited` line, and check only the checkbox state. Anything written after `Audited` is for the reader, not for you.
   - `[x] Audited ...` → proceed.
   - `[ ] Audited ...` → **refuse to start**. Tell the user the plan has not passed audit. If `tmp/audits/<plan-basename>.audit.md` exists, point them at it; otherwise tell them to run audit mode. Stop.
   - No Sign-off section, or no `Audited` line within it → **refuse to start**. Tell the user the plan is not signed off; draft a sign-off block first. Stop.
   - The user may override the gate by saying explicitly "run without audit" (or similar). If they do, acknowledge the override in chat, then continue. Never override silently.
3. Determine scope: if the user named a phase (e.g. "phase 1", "t1.x"), take only items whose ID prefix matches. Otherwise take all items.
4. Build the todo list from the file's current state:
   - `[ ]` items → todo with status `pending`
   - `[-]` items → todo with status `in_progress`
   - `[x]` items → todo with status `completed`
   - Preserve the ID as a prefix in each todo's content: "t1.0 — description"
5. Call `todowrite` once with the full reconstructed list.
6. Show the user a brief summary: how many pending, in-progress, completed. Note any `[-]` items found (these were in flight from a previous session and need a decision: resume, restart, or mark done).
7. Ask which item to start with (or whether to continue top-to-bottom from the first pending one). Wait for confirmation before doing any work.

## Execution protocol

- Before starting an item, **announce its complexity hint** to the user. Read the `complexity: [low|high|manual]` tag at the end of the task line and state it explicitly in chat (e.g. "Next: T3.2 — complexity: [high]"). Do this for every task, not just high-effort ones. The hint signals expected effort and reasoning depth — the user uses it to decide which model should drive the task. Do not start work until the user has confirmed or selected a model.
- Before starting an item: flip its checkbox in the plan file from `[ ]` to `[-]`, and set its todo to `in_progress`. See "Checkbox update timing" below.
- Keep exactly one todo `in_progress` at a time.
- Do the work. Run tests or whatever verification the item implies.
- Only mark `completed` after verification passes. Never on intent.
- After completing: flip the checkbox in the plan file from `[-]` to `[x]`, and set the todo to `completed`. See "Checkbox update timing" below.
- If blocked, leave the checkbox as `[-]`, keep the todo `in_progress`, add a new todo describing the blocker, and surface it to the user.
- After every 3 completed items, pause and summarize before continuing.

## Checkbox update timing (hard rule)

Each checkbox transition is its own immediate file edit, applied at the exact moment of transition. **Never batch.**

- `[ ] → [-]` happens BEFORE you do any work on that item. Edit the plan file first; then do the work.
- `[-] → [x]` happens IMMEDIATELY after verification passes for that item, before moving on or running any other tool. Edit the plan file before announcing completion to the user.
- The plan file edit and the corresponding `todowrite` update happen in the same turn. The plan file is the source of truth; the todo list is a derived view. They must never disagree.

You must NOT:

- Mark several items `[-]` up front and then work through them.
- Complete several items and flip them all to `[x]` in a single Edit call at the end.
- Skip the `[-]` interim state — every item passes through it, even if completion is fast.
- Update the in-memory todo list without also updating the plan file in the same turn.

**Acceptance criterion the user can check**: at any moment between your turns, opening the plan file should show the current state of work. If work is in flight there is exactly one `[-]`. If you've just completed an item and stopped, the most recent completion is `[x]` and there is no `[-]`. If a reader has to scroll past several `[x]` items that were "secretly" `[ ]` two turns ago, you batched — that's a bug, fix the habit.

## Commit hygiene (hard rule)

Every `Commit:` task in the plan commits the work for that phase. **The plan file itself MUST be part of that commit.** The checkbox state IS the per-task record of what landed; if the commits don't include the plan, the `[x]` transitions drift away from git history.

- Before running `git commit` for a Commit task, `git add <plan-file>` alongside the work files. The plan file with its current `[x]`s is staged together with what those `[x]`s describe.
- For `complexity: [manual]` Commit tasks (the user runs git themselves), remind them in chat to stage the plan file too, **before** they commit. State the exact path.
- The commit message stays the one specified in the plan's `Commit:` task text. Don't paraphrase, don't expand, don't add Co-Authored-By unless the user explicitly asks.
- This applies to **every** commit during plan execution, including any out-of-band commits (e.g. fixing a blocker mid-phase) — the plan file's state must always travel with the work it describes.

**Acceptance criterion the user can check**: `git log -p <plan-file>` should show a `[ ] → [-]` and `[-] → [x]` transition for every task ID, anchored at the phase commit where that task's work landed. If the plan file's history is sparse compared to the work history, commits were made without staging the plan — that's the bug this rule prevents.

## Commit-task flow (order inversion)

For a `Commit:` task the `[-] → [x]` flip happens BEFORE `git commit`, not after. The task's "work" IS the commit; flipping after means the commit captures the plan file showing this task at `[-]` and the `[x]` transition has nowhere to live in git history.

Order for a Commit task:

1. `[ ] → [-]` — flip in the plan file.
2. Evaluate: review what's staged, confirm the message matches the `Commit:` text, surface anything missing.
3. `[-] → [x]` — flip in the plan file NOW, before the commit runs.
4. `git add <plan-file>` + `git commit` — the commit captures the plan file with this task at `[x]`, alongside the work files and any sibling-task `[x]`s made earlier in the phase.

For `complexity: [manual]` Commit tasks (the user runs git): you still own steps 1–3. After step 3, remind the user to stage the plan path together with the work files before they commit.

If the commit fails (pre-commit hook, etc.), revert this task to `[-]`, fix the issue, then re-flip to `[x]` immediately before re-running `git commit`. Never amend the failed commit — make a new one.

## Plan file discipline

The plan file is read-mostly during execution. The ONLY edits you may make are checkbox state transitions on existing items:

- `[ ]` → `[-]` when starting
- `[-]` → `[x]` when completing
- `[-]` → `[ ]` if explicitly reverting at the user's request

Do not edit item text, descriptions, IDs, ordering, headings, context sections, or anything else in the plan file during execution. Do not add new items. If you discover work that should be added, propose it to the user in chat — they will edit the plan (or switch to authoring/update mode).

## Scope discipline (execution)

- Do not invent items not in the plan.
- If the plan is ambiguous, ask before guessing.
- If the user asks for work outside the plan, do it, but do not record it in the plan file.

---

## Stack specifics → AGENTS.md

For everything stack-specific — Rails (ViewComponents, Stimulus/importmap, Turbo
Streams + ActionCable, SolidQueue, RSpec/FactoryBot), Node, Voyage, Postgres,
HTML/CSS (Tailwind, `data-accent`, no inline `style=`, extract components — no
spaghetti), i18n, etc. — **follow `AGENTS.md`** and the conventions it documents.
When a convention is missing there, add it.

## Deferred work

Not-yet-built features live in `docs/follow-up.md` (videos & games pipelines,
playlists, `Pito::Stats`/`Pito::Analytics`, component-extraction backlog, …).
