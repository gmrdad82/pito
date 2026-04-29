# MCP Server

Pito exposes a Model Context Protocol (MCP) server for AI assistants to interact with the app programmatically. Two transports are available: stdio for local Claude Code usage, and HTTP for remote access (Claude Mobile, other MCP clients).

## Architecture

- **Gem:** `mcp` (official Ruby MCP SDK, v0.14.0+)
- **Transports:** stdio (local) and Streamable HTTP (remote)
- **Auth:** none for stdio (local trust), bearer token for HTTP
- **Process isolation:** stdio runs as standalone process; HTTP runs on a dedicated Puma (port 3001), separate from the web app (port 3000)

The MCP server loads Rails models, decorators, and services directly (in-process). It does not make HTTP requests to the web app.

## Stdio Transport (Local)

For Claude Code and local MCP clients. No authentication — inherits trust from the local machine.

```bash
# Add to Claude Code (from project root)
claude mcp add pito -- /full/path/to/pito/bin/mcp

# Debug mode (shows Rails boot output on stderr)
MCP_DEBUG=1 bin/mcp
```

## HTTP Transport (Remote)

For Claude Mobile, remote MCP clients, and tunnel access. Runs on a dedicated Puma process (port 3001) to avoid interfering with the web app.

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
- **Horizontal:** run multiple instances behind a load balancer (each needs DB + Redis access)

### Tunnel access (Cloudflare Tunnel)

To expose pito MCP over the internet (e.g., for Claude Mobile):

1. Install `cloudflared` and authenticate
2. Create a tunnel pointing `mcp.pitomd.com` → `http://localhost:3001`
3. Configure Claude Mobile with the MCP endpoint URL and bearer token

See the Cloudflare Tunnel docs for setup details.

## Tools

### Read Tools

| Tool | Description |
|------|-------------|
| `list_channels` | All channels with subscriber/video/view counts |
| `get_channel` | Channel detail + video list (by ID) |
| `list_videos` | All videos with stats, optional channel_id filter and limit |
| `get_video` | Video detail + 30-day stat history (by ID) |
| `get_dashboard` | Analytics: daily views, views by channel, top videos, engagement. Supports ranges: 7d, 30d, 90d, 1y, all |
| `search` | Full-text search across channels and videos via Meilisearch |
| `list_saved_views` | All saved workspace views, optional kind filter |
| `manage_settings` | View current settings (no args) or update max_panes, pane_title_length, theme |

### Write Tools

| Tool | Description |
|------|-------------|
| `create_channel` | Create channel (title required, description optional) |
| `update_channel` | Update channel title/description (by ID) |
| `create_video` | Create video (title + channel_id required, plus description/privacy/tags/category/language) |
| `update_video` | Update video metadata (by ID) |
| `delete_records` | Delete channels or videos by type + IDs array. Channels cascade-delete videos. Marked destructive. |
| `create_saved_view` | Save a pane layout (kind + name + IDs array) |
| `delete_saved_view` | Delete a saved view (by ID). Marked destructive. |

## Resources

| URI | Description |
|-----|-------------|
| `pito://design` | Design system document (docs/design.md) |
| `pito://status` | Live app state: counts, search health, settings |
| `pito://mcp` | This document |

## Data Shapes

### Channel Summary
```json
{
  "id": 1,
  "youtube_channel_id": "UC...",
  "title": "Channel Name",
  "connected": true,
  "subscriber_count": 50000,
  "video_count": 120,
  "view_count": 1000000
}
```

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
Adds: `description`, `thumbnail_url`, `tags`, `category_id`, `default_language`, `made_for_kids`, `last_synced_at`, `stats` (array of daily entries with date/views/likes/comments/shares/watch_time_minutes).

### Channel Detail (extends summary)
Adds: `description`, `thumbnail_url`, `last_synced_at`, `videos` (array of video summaries).

## Token Model

`McpAccessToken` stores bearer tokens for HTTP transport authentication:

- Tokens are hashed with HMAC-SHA256 (using `secret_key_base` as pepper) — plaintext is never stored
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
    list_videos.rb        # list_videos
    get_video.rb          # get_video
    get_dashboard.rb      # get_dashboard
    search_content.rb     # search
    create_channel.rb     # create_channel
    update_channel.rb     # update_channel
    create_video.rb       # create_video
    update_video.rb       # update_video
    delete_records.rb     # delete_records
    manage_settings.rb    # manage_settings
    list_saved_views.rb   # list_saved_views
    create_saved_view.rb  # create_saved_view
    delete_saved_view.rb  # delete_saved_view
  resources/
    app_status.rb         # pito://status
    design_doc.rb         # pito://design
    mcp_doc.rb            # pito://mcp
app/models/
  mcp_access_token.rb     # Bearer token model (SHA256 hashed)
bin/mcp                   # Stdio entry point
bin/mcp-web               # HTTP entry point (dedicated Puma on port 3001)
config/puma_mcp.rb        # Puma config for MCP HTTP server
lib/tasks/mcp.rake        # Token management rake tasks
```
