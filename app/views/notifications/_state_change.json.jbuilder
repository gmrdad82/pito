# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Shared response body for `read.json` / `unread.json` and the
# `respond_with_state_change` JSON branch. Locked decision #2.
json.id @notification.id
json.read YesNo.to_yes_no(@notification.read?)
json.in_app_read_at @notification.in_app_read_at&.iso8601
json.unread_count @unread_count
