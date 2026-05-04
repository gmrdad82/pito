# Manual test playbook — MCP Dev KB surface (Phase 4 Step 0)

**Repo:** `pito` (monolith) at `/home/catalin/Dev/pito` **Spec:**
`docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md`
**Reviewer run:** 2026-05-04

This is the user's first chance to validate Step 0 — three new MCP tools
(`list_docs`, `read_doc`, `save_note`) plus a shared path-safety helper — before
the architect commits.

## Pipeline summary

| Gate                                       | Status   | Notes                                                                                   |
| ------------------------------------------ | -------- | --------------------------------------------------------------------------------------- |
| 1 `/code-review` on the diff               | PASS\*   | No blockers. Five non-blocking observations — see "Concerns / suggestions" below.       |
| 2 `/simplify` on the diff                  | PASS\*   | Two cosmetic redundancies — see below. Neither warrants a fix-up dispatch.              |
| 3 `bundle exec rspec` (full suite)         | **PASS** | 746 examples, 0 failures. Includes the 62 new specs.                                    |
| 4 `bin/brakeman -q -w2`                    | **PASS** | 0 security warnings. 10 controllers, 15 models, 42 templates scanned.                   |
| 5 `bundle exec bundler-audit check`        | **PASS** | Advisory DB updated; no vulnerable gems.                                                |
| 6 `bin/rubocop` on the eight changed files | **PASS** | 8 files inspected, 0 offenses.                                                          |
| 7 Static-deviation audit                   | NOTE     | Spec §4 says "realpath escapes"; implementation is purely lexical. See concern 1 below. |

`*` Code review and simplify produced findings but no blockers — see the next
two sections.

## Blockers

None. The architect can proceed to manual validation.

## Concerns / suggestions (non-blocking)

These do not stop the user from validating Step 0. They are surfaced so the
architect / docs-keeper can decide whether to backfill the spec or queue
follow-ups.

### 1. Spec deviation — read-side path safety is lexical, not realpath-based

Spec §4 lists the rejection criteria as:

> Paths whose realpath escapes `Rails.root.join("docs")` AND aren't equal to
> `Rails.root.join("CLAUDE.md")`.

The implementation in `app/lib/dev_doc_path.rb` is purely lexical / structural —
`Pathname#cleanpath`, then a path-parts comparison via `DevDocPath.inside?`. No
`Pathname#realpath` call is made. The header comment of `dev_doc_path.rb`
documents this as a deliberate choice ("Validation is purely lexical and
structural — failures never depend on what's on disk").

Practical impact: a symlink **inside** `docs/` whose target is **outside** the
docs tree would be followed by `read_doc` (and surface in `list_docs`). Mobile
cannot create symlinks via these tools (no `write_doc`, `save_note` writes a
hard-coded folder), so the only way an escape symlink lands in `docs/` is for
the desktop user to create one manually. Residual risk is therefore low, but it
is a real deviation from the spec text.

Two ways to resolve:

- (a) **Lock the spec to the implementation.** Dispatch `docs-keeper` to amend
  spec §4 to "lexically rejects via `cleanpath`; symlinks inside `docs/` are
  trusted." Lowest-effort path; matches the residual-risk reality.
- (b) **Tighten the implementation.** Add a `realpath` check after the lexical
  check (still rejecting before any read/stat-of-content), and update the spec
  to make it explicit. Belt-and-braces.

Recommend (a) for Step 0, with a refinement-backlog item for (b) if Phase 12
auth makes desktop-side symlinks a concern.

### 2. Six minor spec ambiguities resolved by the implementation

The implementation made sensible defaults where the spec did not pin behavior.
Capture them in a `docs-keeper` amendment so future readers see the contract
clearly:

1. **`first_heading` cap at 200 lines.** `list_docs` scans up to 200 lines per
   file looking for the first `# H1`; bails out and returns `""` past that.
   Spec didn't say.
2. **`first_heading` strict H1 match.** Implementation uses
   `line.start_with?("# ") && !line.start_with?("## ")`. The second clause is
   redundant (a `"## "` line cannot start with `"# "` since the third char
   differs), but the intent is clear: H1 only.
3. **`CLAUDE.md` inclusion rule.** Included only when `prefix == ""` (or unset)
   AND `File.fnmatch?(name_pattern, "CLAUDE.md")`. Spec said this; the
   `fnmatch?` mechanism is the implementation choice.
4. **Slug sanitization extras.** Beyond the spec's literal `[a-z0-9-]` rule,
   the implementation collapses runs of hyphens (`a---b` → `a-b`) and strips
   leading/trailing hyphens (`-trim-` → `trim`). These are filename-quality
   wins; should be locked in the spec.
5. **`size_bytes` is integer, `last_modified_at` is ISO8601 UTC string.** Spec
   didn't specify the wire types; the implementation chose JSON-friendly ones.
6. **`prefix` rejection.** `list_docs` rejects absolute prefixes (`/etc`) and
   `..`-traversal prefixes at the boundary, before any `Dir.glob`. Spec
   implied this for `read_doc` only.

### 3. Simplify candidates (cosmetic, not worth a dispatch)

- `app/mcp/tools/list_docs.rb:104` — the `&& !line.start_with?("## ")` clause
  in `first_h1` is dead because `"## "` doesn't satisfy `start_with?("# ")`
  (the third character differs: `'#'` vs the space the H1 needs). Drop the
  second clause.
- `app/mcp/tools/list_docs.rb:31-32` — the `limit = 50 if limit <= 0` line is
  shadowed by the next line's `[[limit, 1].max, 500].min` clamp. Effect: `nil`
  / negative / zero → `1`, not `50`. Either drop the redundant first line, or
  rewrite as `limit = limit.to_i.clamp(1, 500).then { |n| n <= 0 ? 50 : n }`.
  Minor; behavior is acceptable today (positional defaults still apply when
  the kwarg is omitted).
- `app/mcp/tools/save_note.rb:67-72` — `unique_path`'s `loop` has no upper
  bound. Practical risk is zero (Mobile cannot trigger > 1 collision/sec on
  its own), but a defensive `break if suffix > 1000` would close the
  theoretical hole.

### 4. Pre-existing follow-ups (not Step 0's problem)

- `CLAUDE.md:32` references `docs/auth.md` which does not exist on disk yet
  (Phase 12 territory). Already surfaced by the docs-keeper sibling-spec
  dispatch. Confirmed during this review; no action for Step 0.
- `docs/notes/` will accumulate as Mobile captures notes during use. Desktop
  curates and prunes — no automation. The user may want a `bin/notes prune`
  or `bin/notes promote` helper later. Refinement-backlog item.

## Manual test steps

The user runs these after `bin/dev` is up so the MCP HTTP server at
`mcp.pitomd.com` is reachable. All Mobile-side steps assume a Claude Mobile
session connected to `pito` MCP.

### Pre-flight

1. **Action:** `cd ~/Dev/pito && bin/dev`. Wait until Puma logs
   `Listening on http://0.0.0.0:3000` and Sidekiq is attached. **Expected:**
   No errors. The MCP HTTP Puma is serving on `:3001` (proxied by Cloudflare
   Tunnel to `mcp.pitomd.com`).
2. **Action:** Open `https://app.pitomd.com/dashboard` in a browser.
   **Expected:** Dashboard loads; charts render. (Confirms the Rails web Puma
   is healthy.)
3. **Action:** `curl -s -X POST https://mcp.pitomd.com -H 'Content-Type: application/json' -H "Authorization: Bearer $(rails runner 'puts McpAccessToken.first.plaintext_for_curl' 2>/dev/null || echo MISSING)" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | head -200`.
   **Expected:** A JSON envelope listing all MCP tools — confirm `list_docs`,
   `read_doc`, and `save_note` appear alongside the existing channel / video /
   dashboard tools. (If the bearer-token incantation is wrong locally, it's
   fine to skip and rely on the Mobile-side test below; the point is to see
   the three tool names.)
4. **Action:** `ls ~/Dev/pito/docs/notes/`. **Expected:** Only `.gitkeep`. No
   stale notes from previous runs.

### From Claude Mobile — happy paths

5. **`list_docs` recent logs.** Prompt Mobile: _"What was I working on last
   session?"_ **Expected:** Mobile invokes
   `list_docs(name_pattern: "log.md", sort: "mtime_desc", limit: 5)`. The
   result includes (in this order, most-recent first) the channel-revamp log
   and the postgres-migration log; `last_modified_at` is ISO8601 UTC;
   `size_bytes` is an integer; `first_heading` previews the H1 of each log.
   Mobile likely follows up with `read_doc` on the top result — that is fine,
   step 8 covers it.
6. **`list_docs` ADR prefix.** Prompt: _"Show me the ADRs."_ **Expected:**
   `list_docs(prefix: "decisions/")` is invoked. Result is exactly:
   `docs/decisions/0000-template.md`,
   `docs/decisions/0001-no-server-side-uploads.md`,
   `docs/decisions/0002-app-first-then-terminal-mcp-parallel.md`. CLAUDE.md is
   NOT included (prefix is non-empty).
7. **`list_docs` includes CLAUDE.md.** Prompt: _"List the markdown files at
   the repo root."_ or _"What's in CLAUDE.md?"_ **Expected:** `list_docs`
   without a `prefix` (or with `prefix: ""`) returns a result set that
   includes `CLAUDE.md` as one of the rows. (Mobile may or may not chain into
   `read_doc`; both behaviors are acceptable.)
8. **`read_doc` happy path.** Prompt: _"Tell me about the design system."_
   **Expected:** Mobile calls `read_doc(path: "docs/design.md")`. The returned
   `content` matches `cat docs/design.md` byte-for-byte. `path` is
   `"docs/design.md"`. `last_modified_at` is ISO8601 UTC.
9. **`read_doc` for CLAUDE.md.** Prompt: _"Read CLAUDE.md."_ **Expected:**
   `read_doc(path: "CLAUDE.md")` returns the file body. This confirms the
   sibling-prefix exception works.

### From Claude Mobile — read rejections

For each of these, the expected outcome is an MCP error envelope (`isError:
true`) with a clear message. **No file content** should be returned.

10. **Path traversal.** Prompt: _"Try to read `../../etc/passwd`."_
    **Expected:** Error referencing either the `..` segments rejection or the
    "must be inside docs/ or be CLAUDE.md" branch.
11. **Absolute path.** Prompt: _"Try to read `/etc/passwd`."_ **Expected:**
    Error: "path must be relative (no leading '/')".
12. **Wrong extension — Gemfile.** Prompt: _"Try to read the Gemfile."_
    **Expected:** Error: "extension must be .md".
13. **Wrong extension — source file.** Prompt: _"Read `app/models/user.rb`."_
    **Expected:** Error: "extension must be .md".
14. **No extension.** Prompt: _"Read `docs/notes`."_ **Expected:** Error:
    "extension must be .md".
15. **Outside docs/, .md but not CLAUDE.md.** Prompt: _"Read `README.md`."_
    **Expected:** Error: "path must be inside docs/ or be CLAUDE.md".

### From Claude Mobile — `save_note`

For each of these, after the MCP call succeeds, run the verification commands
from a desktop terminal in `~/Dev/pito`.

16. **Happy path with explicit slug.** Prompt: _"Save this thought as a note:
    'Remember to revisit the AAS variant cost during Phase 4 review.' Use slug
    'aas-variant-cost'."_ **Expected:** The MCP call returns
    `{path: "docs/notes/<YYYY-MM-DD-HH-MM-SS>-aas-variant-cost.md", saved_at: "..."}`
    where `<YYYY-MM-DD>` is today's UTC date and the time matches the moment
    of the call. **Verify:**
    - `ls docs/notes/` — exactly one new `.md` file plus `.gitkeep`.
    - `cat docs/notes/<that-file>.md` — content matches the prompt verbatim.
17. **No slug.** Prompt: _"Save this: 'Quick reminder — log this in the Phase
    4 plan tomorrow.'"_ (No slug hint.) **Expected:** File lands as
    `docs/notes/<timestamp>-note.md`. `cat` confirms the content.
18. **Repeat — distinct timestamps.** Prompt: _"Save it again with the same
    content."_ a few seconds later. **Expected:** A second file appears with
    a later timestamp; both notes from steps 16 and 18 are present in
    `docs/notes/`. Filenames differ.
19. **Slug with punctuation / spaces.** Prompt: _"Save 'Some idea.' with the
    title 'My Big Idea!!!'."_ **Expected:** Mobile sends
    `slug: "My Big Idea!!!"`. Server sanitizes to `my-big-idea`. File lands as
    `docs/notes/<timestamp>-my-big-idea.md`.
20. **Slug that sanitizes to empty.** Prompt: _"Save 'punctuation only test'
    with title '!!!'."_ **Expected:** `slug: "!!!"` sanitizes to empty,
    falls back to `note`. File lands as `docs/notes/<timestamp>-note.md`.
    (Distinguishable from step 17 by timestamp and content.)
21. **Long slug.** Prompt: _"Save this with title 'a very very very very very
    very very very very very long title that should get truncated by the
    server.'"_ **Expected:** Filename slug is at most 50 chars after the
    timestamp. Confirm with `ls docs/notes/ | tail -1` and a character count.
22. **Sub-second collision (optional, advanced).** Two `save_note` calls in
    rapid succession with the same slug should produce two distinct files,
    one ending `-<slug>.md` and the other ending `-<slug>-2.md`. Hard to
    trigger from Mobile UX; acceptable to leave untested manually since the
    spec covers it (`save_note_spec.rb` exercises this with a frozen `Time`).

### Cleanup

23. **Action:** Inspect `docs/notes/` and decide which captures are worth
    keeping. Mobile is the **capture** surface; Desktop is the **curate**
    surface. Two patterns:
    - **Discard everything.** `rm docs/notes/*.md` (NOT `.gitkeep`). Run from
      `~/Dev/pito`. Verify with `ls docs/notes/` → only `.gitkeep`.
    - **Promote a note into a log / ADR / spec.** Open the note in the
      editor, lift its content into the appropriate destination, then `rm`
      the source.
24. **Action:** `git status docs/notes/`. **Expected:** Either clean (if all
    notes were removed) or showing the notes as untracked (if any were kept
    intentionally). The architect commits `docs/notes/.gitkeep` only — the
    notes themselves stay out of git unless explicitly added.

## Sign-off checklist

Before the architect commits Step 0:

- [ ] Steps 1–4 (pre-flight) green: `bin/dev` healthy, `mcp.pitomd.com`
      reachable, three new tools visible in `tools/list`, `docs/notes/`
      empty.
- [ ] Steps 5–9 (read happy paths) green: `list_docs` returns the right
      shape and includes / excludes `CLAUDE.md` per the rules; `read_doc`
      returns full file bodies with ISO8601 UTC timestamps.
- [ ] Steps 10–15 (read rejections) green: each surfaces an MCP error with a
      clear message; no file bytes leak.
- [ ] Steps 16–22 (save_note) green: filenames match the
      `<YYYY-MM-DD-HH-MM-SS>-<slug>.md` pattern in UTC, slugs sanitize as
      documented, distinct calls produce distinct files, content is verbatim.
- [ ] Concern 1 (lexical-vs-realpath spec deviation) acknowledged. User
      decides: amend the spec (recommended) or queue a follow-up to add a
      realpath check.
- [ ] Concerns 2–4 reviewed. User decides which (if any) to dispatch
      `docs-keeper` to backfill into the spec.
- [ ] User has explicitly authorized the commit.

## Cleanup / rollback

If Step 0 is rejected and needs to be unwound on this clean working tree:

1. **Untracked files (the new code).** `git status` shows
   `app/lib/dev_doc_path.rb`, the three new tools under `app/mcp/tools/`, the
   four new specs, and `docs/plans/beta/04-project-workspace/specs/mcp-dev-kb-surface.md`
   plus `additions.md` as untracked. Removing them is `rm <each>` —
   destructive, no git history involved.
2. **Tracked files modified.** `docs/mcp.md` and `CLAUDE.md` (and
   `docs/plans/beta/beta.md`, `docs/orchestration/follow-ups.md`,
   `docs/plans/beta/04-project-workspace/specs/project-workspace.md`) are
   modified in the working tree but not yet committed. `git checkout --` on
   each restores the pre-Step-0 state. **Confirm with the user before
   running** — destructive.
3. **Captured notes.** Anything the user typed into `save_note` during
   manual testing lives in `docs/notes/`. Curate first, then `rm` the rest.
4. The renamed `docs/plans/beta/0*-*/plan.md` files (currently staged via
   `git mv`) are unrelated to Step 0 — leave them alone unless the architect
   instructs otherwise.
