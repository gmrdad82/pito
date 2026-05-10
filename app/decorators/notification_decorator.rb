# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Decorator for the Notification JSON shape consumed by
# `GET /notifications.json`, `GET /notifications/:id.json`, and the
# read/unread/mark-read response bodies. Boundary booleans serialize as
# `"yes"` / `"no"` strings; timestamps as ISO-8601.
#
# `as_summary_json` is the per-row shape used by the index and the
# state-change responses. `as_detail_json` wraps the existing
# `NotificationFormatter::InApp.payload_for` so the CLI / MCP detail
# render gets the same body the in-app modal renders.
class NotificationDecorator < ApplicationDecorator
  def as_summary_json
    {
      id: id,
      kind: kind,
      severity: severity,
      event_type: event_type,
      title: title,
      body: body,
      url: url,
      fires_at: fires_at&.iso8601,
      in_app_read_at: in_app_read_at&.iso8601,
      read: YesNo.to_yes_no(read?),
      discord_delivered_at: discord_delivered_at&.iso8601,
      slack_delivered_at: slack_delivered_at&.iso8601,
      retry_count: retry_count,
      last_error: last_error,
      created_at: created_at&.iso8601
    }
  end

  def as_detail_json
    {
      notification: as_summary_json,
      payload: NotificationFormatter::InApp.payload_for(object)
    }
  end
end
