# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Calendar entry summary partial. Reused by schedule, month, and the
# show endpoint (which uses the detail variant). Uses
# `CalendarEntryDecorator#as_summary_json` so the shape stays in one
# place.
json.merge!(CalendarEntryDecorator.new(entry).as_summary_json)
