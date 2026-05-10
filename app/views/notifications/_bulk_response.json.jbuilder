# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Shared body for the bulk mark-read / mark-all-read responses. Mounted
# via `json.partial! "notifications/bulk_response"`.
json.marked @marked
json.unread_count @unread_count
json.has_failures YesNo.to_yes_no(@has_failures)
