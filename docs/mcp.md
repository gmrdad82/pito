# MCP Server

Pito exposes a Model Context Protocol (MCP) server for AI assistants to interact
with the app programmatically. Two transports are available: stdio for local
Claude Code usage, and HTTP for remote access (Claude Mobile, other MCP
clients).

## Architecture

- **Gem:** `mcp` (official Ruby MCP SDK, v0.14.0+)
- **Transports:** stdio (local) and Streamable HTTP (remote)
- **Auth:** none for stdio (local trust), bearer token for HTTP
- **Process isolation:** stdio runs as standalone process; HTTP runs on a
  dedicated Puma (port 3001), separate from the web app (port 3000)

The MCP server loads Rails models, decorators, and services directly
(in-process). It does not make HTTP requests to the web app.

## Stdio Transport (Local)

For Claude Code and local MCP clients. No authentication — inherits trust from
the local machine.

```bash
# Add to Claude Code (from project root)
claude mcp add pito -- /full/path/to/pito/bin/mcp

# Debug mode (shows Rails boot output on stderr)
MCP_DEBUG=1 bin/mcp
```

## HTTP Transport (Remote)

For Claude Mobile, remote MCP clients, and tunnel access. Runs on a dedicated
Puma process (port 3001) to avoid interfering with the web app.

### Starting the server

```bash
bin/mcp-web                    # Starts on port 3001
MCP_PORT=3002 bin/mcp-web      # Custom port
```

The endpoint is `POST /mcp`. All requests require a bearer token.

### Token management

```bash
# Generate a new token (plaintext shown once, copy immediately)
bin/rails mcp:generate_token[my-claude-mobile]

# List all tokens
bin/rails mcp:list_tokens

# Revoke a token by ID
bin/rails mcp:revoke_token[1]
```

### Testing with curl

```bash
curl -X POST http://localhost:3001/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
```

### Scaling

The MCP HTTP server is a standard Puma process. Scale it independently:

- **Threads:** `MCP_THREADS=10 bin/mcp-web`
- **Workers:** `MCP_WORKERS=2 bin/mcp-web`
- **Horizontal:** run multiple instances behind a load balancer (each needs DB +
  Redis access)

### Tunnel access (Cloudflare Tunnel)

To expose pito MCP over the internet (e.g., for Claude Mobile):

1. Install `cloudflared` and authenticate
2. Create a tunnel pointing `mcp.pitomd.com` → `http://localhost:3001`
3. Configure Claude Mobile with the MCP endpoint URL and bearer token

See the Cloudflare Tunnel docs for setup details.

## Tools

### Read Tools

| Tool               | Description                                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `list_channels`    | List channels by URL with optional filters (`star`, `connected`, `syncing`) and pagination (`limit`, `offset`). Returns summary JSON per channel.                               |
| `get_channel`      | Channel detail JSON by ID (id, channel_url, star, connected, syncing, last_synced_at, video_count, timestamps).                                                                 |
| `list_videos`      | All videos with stats, optional `channel_id` filter and limit                                                                                                                   |
| `get_video`        | Video detail + 30-day stat history (by ID)                                                                                                                                      |
| `get_dashboard`    | Analytics: daily views, views by channel, top videos, engagement. Supports ranges: 7d, 30d, 90d, 1y, all                                                                        |
| `search`           | Full-text search across videos via Meilisearch. Channels are not searchable in this phase (no `title`/`description`); their searchable surface returns once YouTube sync ships. |
| `list_saved_views` | All saved workspace views, optional kind filter                                                                                                                                 |
| `manage_settings`  | View current settings (no args) or update max_panes, pane_title_length, theme                                                                                                   |

### Write Tools

| Tool                | Description                                                                                                                                                                        |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `create_channel`    | Create a channel from a canonical YouTube channel URL (`https://www.youtube.com/channel/UC...`). Only `channel_url` is accepted. After save, an initial `ChannelSync` is enqueued. |
| `update_channel`    | Update a channel's `star` and/or `connected` flags. The `channel_url` is **locked** once set and cannot be changed (refused with a structured error).                              |
| `create_video`      | Create video (title + channel_id required, plus description/privacy/tags/category/language)                                                                                        |
| `update_video`      | Update video metadata (by ID)                                                                                                                                                      |
| `delete_records`    | Generic two-step bulk deleter for `channel` or `video`. See "Two-step confirmation pattern" below.                                                                                 |
| `sync_records`      | Generic two-step bulk syncer for `channel` (videos coming later). See "Two-step confirmation pattern" below.                                                                       |
| `create_saved_view` | Save a pane layout (kind + name + IDs array)                                                                                                                                       |
| `delete_saved_view` | Delete a saved view (by ID). Marked destructive.                                                                                                                                   |

The Channel-specific bulk tools (`bulk_delete_channels`, `bulk_sync_channels`)
were dropped in favour of the generic `delete_records` + `sync_records` shape.
The two-step confirm flow is the same; the dispatch is by `type` parameter.

## Two-step confirmation pattern

Destructive and sync MCP tools (`delete_records`, `sync_records`) require **two
calls**:

1. **Preview call** — invoke without `confirm: true` (or with `confirm: false`).
   The tool returns a structured preview and creates **no** state. No
   `BulkOperation` row, no Sidekiq job.
2. **Execute call** — invoke with `confirm: true`. The tool creates a
   `BulkOperation`, creates per-target `BulkOperationItem` rows, enqueues the
   job, and returns `{ operation_id, status_url, ... }`.

Both calls accept the same input shape:
`{ type: "channel" | "video", ids: [int, ...], confirm?: bool }`. Single-record
actions are a one-element `ids` array (bulk-as-foundation pattern).

### `delete_records` — preview response

```json
{
  "preview_url": "/deletions/channel/1,2,3",
  "type": "channel",
  "total": 3,
  "items": [
    { "id": 1, "label": "https://www.youtube.com/channel/UC..." },
    { "id": 2, "label": "https://www.youtube.com/channel/UC..." }
  ],
  "not_found_ids": [3],
  "message": "Preview only — call again with confirm: true to execute."
}
```

### `delete_records` — execute response

```json
{
  "operation_id": 42,
  "status_url": "/bulk_operations/42",
  "enqueued": true,
  "type": "channel",
  "total": 2,
  "not_found_ids": [3],
  "message": "Bulk delete queued. Poll status_url for progress."
}
```

### `sync_records` — preview response

The preview partitions ids into `syncable`, `skipped` (already syncing), and
`not_found_ids`:

```json
{
  "preview_url": "/syncs/channel/1,2,3",
  "type": "channel",
  "total": 3,
  "syncable": [
    { "id": 1, "label": "https://www.youtube.com/channel/UC..." }
  ],
  "skipped": [
    { "id": 2, "label": "https://www.youtube.com/channel/UC...", "reason": "already syncing" }
  ],
  "not_found_ids": [3],
  "message": "Preview only — call again with confirm: true to execute."
}
```

### `sync_records` — execute response

```json
{
  "operation_id": 43,
  "status_url": "/bulk_operations/43",
  "enqueued": true,
  "type": "channel",
  "total": 2,
  "syncable_count": 1,
  "skipped_count": 1,
  "not_found_ids": [3],
  "message": "Bulk sync queued. Poll status_url for progress."
}
```

## Action confirmation as a resource

The `preview_url` returned by `delete_records` and `sync_records` (e.g.
`/deletions/channel/1,2,3`, `/syncs/channel/1,2,3`) is also a fully-functional
web URL. The user (or Claude, via a browser handoff) can navigate to it and
submit the confirmation form there instead of calling the tool a second time.
The web flow and the MCP flow share the controller, the view, and the resulting
`BulkOperation` row.

## Resources

| URI             | Description                                     |
| --------------- | ----------------------------------------------- |
| `pito://design` | Design system document (docs/design.md)         |
| `pito://status` | Live app state: counts, search health, settings |
| `pito://mcp`    | This document                                   |

## Dev KB surface

Three tools open a bidirectional dev-KB channel between the desktop session
(Claude Code, file-system access) and remote sessions (Claude Mobile over
`mcp.pitomd.com`). The substrate is the `docs/` markdown tree already in this
repo. Mobile **reads** the docs tree to recover session context and curated
reference material; Mobile **captures** on-the-road thoughts as timestamped
markdown notes; the next desktop session **curates / promotes** those notes.

| Tool        | Description                                                                                                                                                                                                                               |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `list_docs` | List markdown files under `docs/` (and `CLAUDE.md` when matched). Args: `name_pattern` (glob, default `"*.md"`), `prefix` (relative to `docs/`, default `""`), `sort` (`mtime_desc` / `mtime_asc` / `path`), `limit` (1–500, default 50). |
| `read_doc`  | Read a single markdown file by repo-relative path. Path must end in `.md` and resolve to either `CLAUDE.md` or somewhere under `docs/`.                                                                                                   |
| `save_note` | Append a timestamped markdown note to `docs/notes/`. Server generates the filename `<YYYY-MM-DD-HH-MM-SS>-<slug>.md` (UTC). `content` is required and written verbatim. `slug` is optional and sanitized server-side.                     |

### `list_docs` — return shape

```json
[
  {
    "path": "docs/plans/beta/03-channel-revamp/log.md",
    "last_modified_at": "2026-05-01T12:00:00Z",
    "size_bytes": 4321,
    "first_heading": "Channel revamp — implementation log"
  }
]
```

`first_heading` is the first `# H1` line of the file (empty string if the file
has no H1) — handy preview without forcing a `read_doc` round trip.

`CLAUDE.md` is included in the listing when the caller passes `prefix == ""` (or
omits it) and `name_pattern` matches `CLAUDE.md`.

### `read_doc` — return shape

```json
{
  "path": "docs/design.md",
  "content": "# Design system\n…",
  "last_modified_at": "2026-05-01T12:00:00Z"
}
```

### `save_note` — return shape

```json
{
  "path": "docs/notes/2026-05-04-12-30-45-hello-world.md",
  "saved_at": "2026-05-04T12:30:45Z"
}
```

The `slug` is sanitized to `[a-z0-9-]`: lowercase, spaces collapse to single
hyphens, every other character is dropped, runs of hyphens collapse, leading /
trailing hyphens are stripped, and the result is capped at 50 characters. If
sanitization yields an empty string (e.g. `"!!!"`), the slug falls back to
`note`. The slug is a filename hint only — it never affects the write directory.

Sub-second collisions (two saves with the same slug in the same second) get a
`-2`, `-3`, … suffix appended before `.md`.

### Path safety (read side)

`list_docs` and `read_doc` share a single validator (`DevDocPath.resolve`). The
validator runs purely lexical / structural checks BEFORE any filesystem access —
no stat, no read, no glob until the path is cleared. Rejections:

- Absolute paths (start with `/`).
- Paths whose `Pathname#cleanpath` contains `..` segments.
- Non-`.md` extensions (e.g. `Gemfile`, `notes.txt`, `notes` with no extension).
- Paths that don't resolve to either `Rails.root.join("CLAUDE.md")` or a
  descendant of `Rails.root.join("docs")`.

### Write confinement

`save_note` is the only writer in the Dev KB surface. It writes exclusively to
`docs/notes/` (created on first use). The slug is sanitized but never
participates in the path computation — the write directory is hard-coded. There
is no `write_doc`, no `delete_doc`, no `rename_doc`. Curation, promotion, edits,
and moves stay desktop concerns. Mobile **captures**; desktop **curates**.

The asymmetry is intentional: it keeps the mobile blast radius small and keeps
the desktop session as the single point of curation — the place where notes get
promoted into logs, ADRs, or specs.

## Data Shapes

### Channel Summary

```json
{
  "id": 1,
  "channel_url": "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ",
  "star": false,
  "connected": true,
  "syncing": false,
  "last_synced_at": "2026-05-01T12:00:00Z",
  "created_at": "2026-04-15T09:00:00Z",
  "updated_at": "2026-05-01T12:00:00Z"
}
```

### Channel Detail (extends summary)

Adds: `video_count`.

### Video Summary

```json
{
  "id": 1,
  "youtube_video_id": "abc123",
  "title": "Video Title",
  "channel_id": 1,
  "channel_title": "Channel Name",
  "privacy_status": "public",
  "published_at": "2025-01-15T00:00:00Z",
  "duration_seconds": 600,
  "total_views": 5000,
  "total_likes": 200,
  "total_comments": 30,
  "total_watch_time": 1500
}
```

### Video Detail (extends summary)

Adds: `description`, `thumbnail_url`, `tags`, `category_id`, `default_language`,
`made_for_kids`, `last_synced_at`, `stats` (array of daily entries with
date/views/likes/comments/shares/watch_time_minutes).

## Token Model

`McpAccessToken` stores bearer tokens for HTTP transport authentication:

- Tokens are hashed with HMAC-SHA256 (using `secret_key_base` as pepper) —
  plaintext is never stored
- `last_token_preview` stores the last 4 characters for identification
- `last_used_at` is touched on each successful authentication
- Tokens can be revoked (sets `revoked_at`, excluded from auth)

## File Structure

```
app/mcp/
  pito_server.rb          # Server builder + stdio launcher
  rack_app.rb             # Rack app wrapping HTTP transport
  tools/
    list_channels.rb      # list_channels
    get_channel.rb        # get_channel
    create_channel.rb     # create_channel
    update_channel.rb     # update_channel
    list_videos.rb        # list_videos
    get_video.rb          # get_video
    create_video.rb       # create_video
    update_video.rb       # update_video
    get_dashboard.rb      # get_dashboard
    search_content.rb     # search
    delete_records.rb     # delete_records (two-step confirm)
    sync_records.rb       # sync_records  (two-step confirm)
    manage_settings.rb    # manage_settings
    list_saved_views.rb   # list_saved_views
    create_saved_view.rb  # create_saved_view
    delete_saved_view.rb  # delete_saved_view
    list_docs.rb          # list_docs (Dev KB)
    read_doc.rb           # read_doc  (Dev KB)
    save_note.rb          # save_note (Dev KB)
  resources/
    app_status.rb         # pito://status
    design_doc.rb         # pito://design
    mcp_doc.rb            # pito://mcp
app/lib/
  dev_doc_path.rb         # Read-side path safety for list_docs / read_doc
app/models/
  mcp_access_token.rb     # Bearer token model (SHA256 hashed)
bin/mcp                   # Stdio entry point
bin/mcp-web               # HTTP entry point (dedicated Puma on port 3001)
config/puma_mcp.rb        # Puma config for MCP HTTP server
lib/tasks/mcp.rake        # Token management rake tasks
```
