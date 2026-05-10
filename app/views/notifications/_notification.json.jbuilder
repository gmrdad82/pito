# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Summary row for a Notification. Reused by `index.json` and consumers
# that embed notification summaries inline. Uses
# `NotificationDecorator#as_summary_json` so the shape stays in one
# place.
json.merge!(NotificationDecorator.new(notification).as_summary_json)
