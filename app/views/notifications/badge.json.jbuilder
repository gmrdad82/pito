# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Cookie-authed badge endpoint. Two counters: unread count + whether
# any of the unread rows carry a `last_error` (the nav badge surfaces
# both signals).
json.unread_count @unread_count
json.has_failures YesNo.to_yes_no(@has_failures)
