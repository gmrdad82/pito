# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Response body for `read.json` / `unread.json`. Locked decision #2:
# replaces the previous `head :no_content` with a structured body that
# carries the new read state + the recomputed unread_count.
json.partial! "notifications/state_change"
