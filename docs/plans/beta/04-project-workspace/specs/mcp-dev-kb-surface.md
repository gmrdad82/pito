# Phase 4 — Step 0 — MCP Dev KB Surface

> Sibling spec to `project-workspace.md`. Lands BEFORE Phase A's nine
> sequential foundation steps. Date: 2026-05-04. Locked decisions are pinned
> exactly — do not reinvent.

---

## 1. Goal

Open a bidirectional dev-KB channel between Desktop Claude (file-system access
via Claude Code) and Claude Mobile (over the existing MCP server at
`mcp.pitomd.com`). Mobile reads the docs tree to recover session context and
curated reference material; Mobile captures on-the-road thoughts as timestamped
markdown notes. Desktop curates / refines / promotes those notes during the
next implementation session. The shared substrate is the `docs/` markdown tree
already living in this repo.

The point is conversational continuity across surfaces: the user can ask Mobile
"what was I working on last session?" and get the latest phase log read back,
or "save this thought" and have it land as a discoverable markdown file the
next Desktop session will pick up and curate.

## 2. Scope deviations

This is a scope addition to Phase 4, captured in
`04-project-workspace/additions.md` on the same date as this spec.

The master `project-workspace.md` spec §2 says "MCP (Lane 2b) paused. No
`project:*` MCP tools." That stands. Step 0 adds a `dev:*` surface — reading
docs and writing notes — which is distinct from the `project:*` resource tools
that remain paused. When the auth phase (Phase 12) lands and the scope catalog
is wired up, `dev:*` is the natural home for these tools.

No other §2 deviations are touched by Step 0.

## 3. Three MCP tools

Register alongside the existing channel / video / dashboard / saved-views tools
in the `mcp` gem server. Same registration shape, same error envelope.

### 3.1 `list_docs`

| Arg            | Type    | Default       | Notes                                |
| -------------- | ------- | ------------- | ------------------------------------ |
| `name_pattern` | string  | `"*.md"`      | Glob-style. e.g. `"log.md"`.         |
| `prefix`       | string  | `""`          | Relative to `docs/`. e.g. `"plans/"` |
| `sort`         | enum    | `"mtime_desc"`| `mtime_desc` / `mtime_asc` / `path`  |
| `limit`        | integer | `50`          | 1–500.                               |

Returns array of `{path, last_modified_at, size_bytes, first_heading}`.

- `path` is relative to repo root, e.g.
  `"docs/plans/beta/03-channel-revamp/log.md"`.
- `first_heading` is the first `# H1` line of the file (string, may be empty
  if the file has no H1) — handy preview without forcing a `read_doc` round
  trip.

`CLAUDE.md` is included in the listing when it matches `name_pattern` and
`prefix == ""` (or unset).

### 3.2 `read_doc`

| Arg    | Type   | Required | Notes                                   |
| ------ | ------ | -------- | --------------------------------------- |
| `path` | string | yes      | Relative to repo root; must end in `.md`|

Must resolve to either `CLAUDE.md` or a path inside `docs/`. Returns
`{path, content, last_modified_at}`.

### 3.3 `save_note`

| Arg       | Type   | Required | Notes                                     |
| --------- | ------ | -------- | ----------------------------------------- |
| `content` | string | yes      | Plain markdown body. Written verbatim.    |
| `slug`    | string | no       | Mobile-derived hint; sanitized server-side|

`content` is written verbatim — the server does not parse front-matter, render
markdown, or execute anything. Bytes in, bytes on disk.

`slug` is sanitized to `[a-z0-9-]`: lowercase, hyphens for spaces, drop
everything else. Max 50 chars. If sanitization yields empty (e.g. `"!!!"`),
the server falls back to `note`.

Server-generated filename:
`<YYYY-MM-DD-HH-MM-SS>-<slug>.md` using
`Time.current.strftime("%Y-%m-%d-%H-%M-%S")`.

**Locked decision — UTC.** The timestamp uses UTC for predictability across
surfaces (Mobile, Desktop, the user's own filesystem inspection from any
timezone). Whether that materializes as `Time.current` with the Rails app
configured to UTC, or `Time.now.utc.strftime(...)` directly, is mcp-impl's
call — the contract is "the filename's clock is UTC."

Fixed write location: `docs/notes/`. `mkdir -p` on first use. **No other path
is ever writable.** The slug never affects the directory; it is a filename
hint only.

Collisions on identical sub-second timestamps: append `-2`, `-3`, … before the
`.md` extension.

Returns `{path, saved_at}`.

## 4. Path safety (read side)

Single shared helper, reused across `list_docs` and `read_doc`. Reject:

- Absolute paths (start with `/`).
- Paths containing `..` segments (after `Pathname#cleanpath`).
- Non-`.md` extensions.
- Paths whose realpath escapes `Rails.root.join("docs")` AND aren't equal to
  `Rails.root.join("CLAUDE.md")`.

Validation runs BEFORE any filesystem access — no stat, no read, no glob until
the path is cleared. Failures return MCP errors with a clear message ("path
must be inside docs/ or be CLAUDE.md", "extension must be .md", etc.). The
helper has its own RSpec coverage; controllers / tools call into it.

## 5. Why no write tool besides `save_note`

The asymmetry is intentional. Mobile is **read + capture**; Desktop is
**curate + commit**. Edits, deletes, renames, file moves all happen via
Desktop (Claude Code or direct user action through the editor). This keeps
Mobile's blast radius small AND keeps the Desktop session as the single point
of curation — the place where notes get promoted into logs, ADRs, or specs.

A future `write_doc` / `patch_doc` would need optimistic concurrency (mtime or
etag check) to be safe; we don't pay that cost while the asymmetric model
holds.

## 6. Folder layout

`docs/notes/` is the only Mobile-writable folder. Curated locations remain
Desktop-only:

- `docs/notes/` — Mobile-writable; raw timestamped captures.
- `docs/conversations/` — long-form session summaries; Desktop appends after
  the user validates.
- `docs/decisions/` — ADRs.
- `docs/plans/beta/<NN-phase>/log.md` — per-phase implementation log; Desktop
  appends.
- `docs/plans/beta/<NN-phase>/plan.md` — per-phase plan; rare changes —
  scope shifts go through `additions.md` instead.
- `docs/{architecture,design,mcp,setup,auth}.md` — curated reference docs.

Mobile reads all of the above via `read_doc`; Mobile writes only to
`docs/notes/`.

## 7. Out of scope (v1)

Document explicitly so the boundary is clear:

- **Authentication.** The Cloudflared tunnel to `mcp.pitomd.com` is
  single-user; auth is deferred to Phase 12. The `dev:*` scope name is
  reserved for that phase.
- **Delete / rename / move tools.** Promote to Desktop concern. Mobile
  captures; Desktop curates.
- **True optimistic concurrency on writes** (mtime / etag check). Append-style
  semantics make this moot for `save_note` (each call writes a brand new
  file); for an arbitrary `write_doc` it would matter, but we don't have a
  `write_doc`.
- **MCP resources primitive** (in addition to tools). Tools are universally
  surfaced across MCP clients; resources support varies. Add later if
  warranted.
- **Patch / diff tool** (`patch_doc` instead of full overwrite). Not needed
  without `write_doc`.

## 8. Acceptance criteria

- [ ] `list_docs(name_pattern: "log.md", sort: "mtime_desc", limit: 5)`
      returns the 5 most-recent phase logs.
- [ ] `list_docs(prefix: "decisions/")` returns the ADRs.
- [ ] `read_doc(path: "docs/design.md")` returns the design doc body.
- [ ] `read_doc(path: "CLAUDE.md")` returns CLAUDE.md.
- [ ] `read_doc` rejects each of: `../../etc/passwd`, `Gemfile`,
      `app/models/user.rb`, `/etc/passwd`, `notes.txt`, `notes` (no
      extension).
- [ ] `save_note(content: "# Hello\nworld", slug: "hello-world")` creates
      `docs/notes/<timestamp>-hello-world.md` with exact bytes.
- [ ] `save_note` called twice with the same slug produces two distinct files
      (different timestamps).
- [ ] `save_note` with no `slug` produces a `<timestamp>-note.md` file.
- [ ] `save_note` with slug containing punctuation / spaces sanitizes
      correctly (e.g. `"My Note!"` → `my-note`).
- [ ] `save_note` with slug that sanitizes to empty (e.g. `"!!!"`) falls back
      to `note`.
- [ ] `docs/mcp.md` documents the three tools.
- [ ] RSpec coverage on the path-safety helper: positive + negative cases.

## 9. Manual test recipe

Five steps run from Claude Mobile after Step 0 lands. The reviewer playbook
will expand these into a full step-by-step.

1. "What was I working on last session?" → expect Mobile to call
   `list_docs(name_pattern: "log.md", sort: "mtime_desc", limit: 5)` then
   `read_doc` on the top result.
2. "Tell me about the design system." →
   `read_doc(path: "docs/design.md")`.
3. "Save this thought as a note: ..." → `save_note(content, slug)`. Verify
   the file lands in `docs/notes/` with a timestamped filename.
4. "Save it again with the same content." → second file appears with a
   distinct timestamp (or `-2` suffix if sub-second).
5. "Try to read `Gemfile`." → rejection with a clear message.

## 10. Lane / dispatch

Single `mcp-impl` agent. Files touched:

- MCP server: tool registrations + path-safety helper.
- RSpec coverage on the helper and the three tools.
- `docs/mcp.md` — documents the three tools alongside the existing surface.

CLAUDE.md and folder-cleanup edits (e.g. ensuring `docs/notes/` is recognized
in the layout overview) are owned by a parallel `docs-keeper` dispatch —
separate scope, no overlap.

## 11. Refinement backlog

Captured here so the next phase or dispatch picks them up cleanly:

- `dev:*` MCP scope wired up when Phase 12 (auth) lands.
- Richer `list_docs` filtering: `since:` mtime, `contains:` text grep.
- mtime / etag concurrency on a future `write_doc` if we ever add one.
- MCP resources primitive surface for clients that prefer it over tools.
