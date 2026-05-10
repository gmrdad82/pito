# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Detail response. `NotificationDecorator#as_detail_json` returns a
# `{ notification:, payload: }` hash where `payload` is the existing
# `NotificationFormatter::InApp.payload_for(@notification)` body.
detail = NotificationDecorator.new(@notification).as_detail_json
json.notification detail[:notification]
json.payload      detail[:payload]
