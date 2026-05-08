# Phase 7.5 — Step 09 — MCP Sync (pre-spec)

> **PRE-SPEC.** The phrase "MCP sync" is ambiguous from prior conversation
> context. This doc enumerates the plausible interpretations, surfaces the open
> questions, and parks the work until the user resolves the meaning. No code
> dispatches off this doc as-is.

---

## What we have (rooted in code)

The MCP server already exists and ships in two modes:

- **stdio transport** — `bin/mcp` boots a long-lived MCP server on stdin/stdout.
  Used for Claude Desktop's local MCP-server integration. Single user, single
  process.
- **HTTP transport** — `bin/mcp-web` boots a dedicated Puma on port 3001
  (`mcp.pitomd.com` via the Cloudflare tunnel). Used for Claude Mobile's remote
  MCP integration. Bearer-token auth via `ApiToken`.

The MCP tool surface (post-Path-A2):

- Channels: `list_channels`, `get_channel`, `update_channel`, `delete_records`,
  `sync_records`.
- Videos: `list_videos`, `get_video`, `update_video`, `delete_records`,
  `sync_records`. (`create_video` was deleted in Path A2.)
- Search: `search_content` (Video has no searchable fields post-A2 — currently
  returns zero matches by design).
- Dashboard: `get_dashboard` (returns the five counts).
- Dev KB (Mobile interop): `list_docs`, `read_doc`, `save_note`.

The MCP Puma and the Web Puma share `Current` shape. There is no state mirroring
between them today beyond the shared database.

## Plausible interpretations of "MCP sync"

### Interpretation A — State mirroring between MCP-driven sessions and the Web app

A user has the Pito web app open in the browser AND a Claude session making MCP
tool calls in parallel. They want: changes made via MCP to surface in the web
app immediately (and vice versa), without a full page reload.

Today's state: changes ARE visible after refresh (shared DB), but not via
real-time push. A web pane editing a channel does not auto-update if Claude
calls `update_channel` mid-edit, and Claude's view doesn't auto-update if the
user clicks `[ disconnect ]` in the browser.

What "MCP sync" would mean here:

- Turbo Streams broadcasting from MCP-tool-side mutations to any open web
  subscribers (`broadcast_replace_to`).
- Possibly the inverse: web mutations broadcast something the next MCP `list_*`
  call sees. (The DB already gives the next call the latest, so this half is
  trivial.)
- `get_dashboard` and other read tools would benefit from a cache-invalidation
  hook tied to web mutations.

Probable cost: low-medium. The Turbo Streams broadcast wiring already exists for
bulk operations (`Turbo::StreamsChannel.broadcast_replace_to` is used by
`BulkSyncJob` per `architecture.md`). Extending it to single-record MCP-side
mutations is a familiar shape.

### Interpretation B — Mobile-via-MCP `save_note` capture flow tightening

The user's day-to-day Mobile workflow drops notes via the `save_note` MCP tool
into `docs/notes/`. Desktop curates, prunes, and commits the notes during the
next Desktop session.

Today's state: the loop is loose. Notes accumulate; Desktop's "prune + commit"
step is manual. The `## Notes commit lifecycle` section in `CLAUDE.md` codifies
the rule, but there is no tooling that surfaces "what's new since the last
commit" or that helps the Desktop curator triage.

What "MCP sync" might mean here:

- A `mcp:notes-status` rake task or web surface that lists notes added since the
  last commit, sorted by mtime, with quick-action links (open / preview /
  delete).
- The `save_note` tool gets a `category:` arg or a tagging convention so the
  Desktop curator can sort triage by intent.
- An auto-prune helper that drops notes older than N days (with a manual
  confirm, because MCP capture is precious).

Probable cost: low. Mostly tooling around existing files.

### Interpretation C — MCP tools that perform / trigger DB sync

A specific class of MCP tool — a `sync_*` tool — that initiates the kind of work
`Youtube::Client` does (fetch channel metadata, fetch video stats). Today:
`sync_records` exists, but the underlying `ChannelSync` job is a no-op stamper
post-Path-A2; real sync is Phase 8 work.

What "MCP sync" might mean here:

- `sync_channel(channel_id, kind: "metadata"|"videos"|"all")` triggering the
  relevant Phase 8 job from MCP.
- `get_sync_status(channel_id)` returning queue + history.
- A new tool to expose YouTube quota state to Claude.

Probable cost: medium-high. Depends on Phase 8 landing first.

### Interpretation D — Something else entirely

The user may have a specific use-case in mind that doesn't match A/B/C. Captured
as a sub-question.

## Open questions

**Q12.a — Which interpretation is the user's "MCP sync"?**

- (A) State mirroring (web ↔ MCP turbo broadcasts).
- (B) Notes capture-loop tightening.
- (C) MCP tools that drive DB sync work.
- (D) Other — describe.

**Q12.b — Phase ordering.** A and B are independent of Phase 8. C depends on
Phase 8 landing. If Q12.a = C, this work defers to post-Phase-8.

**Q12.c — Cross-stack surface.** Does the chosen direction touch the `pito` CLI?
See spec 10 (`terminal-sync-prespec`) — that's the symmetric question for the
CLI. If the user's intent for "MCP sync" and "terminal sync" are the SAME
concept under different labels, the two pre-specs collapse into one.

## Master agent's lean

**No lean.** The phrase has multiple plausible meanings; the master needs the
user's intent before guessing.

## What happens next

After the user answers Q12.a–c:

- (A) — `09b-mcp-state-mirroring.md` (or `mcp-turbo-broadcast.md`) becomes a
  real spec.
- (B) — `09b-notes-capture-loop.md` becomes a real spec.
- (C) — defer to a Phase 8 follow-up; the corresponding Phase 8 spec absorbs the
  MCP-tool surface.
- (D) — depends on the description.

## Files touched

None in this pre-spec.

## Acceptance

- [ ] User answers Q12.a, Q12.b, Q12.c.
- [ ] Master decides: real spec, defer, or merge with terminal-sync.
- [ ] Follow-up architect dispatch (if applicable) produces the implementation
      spec; this file closes with a pointer.

## Manual test recipe

Not applicable.

## Cross-stack scope

Decided once Q12.c is answered.

## Follow-ups created

None until answered.

## Decisions (locked)

- **No spec implementation off this doc.** Pre-spec only.
- **The MCP tool registry's auto-discovery (cold-require under `app/mcp/tools/`)
  stays as-is.** Whatever direction "MCP sync" takes, it does not require
  restructuring the existing tool surface.
