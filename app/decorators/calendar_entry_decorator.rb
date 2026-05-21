# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Decorator for the CalendarEntry JSON shape consumed by
# `GET /calendar/schedule.json`, `GET /calendar/month/:y/:m.json`,
# `GET /calendar/entries/:id.json`, and the CRUD endpoints under
# `/calendar/entries.json`. Boundary booleans serialize as
# `"yes"` / `"no"` strings; timestamps as ISO-8601.
#
# `as_summary_json` is the per-row shape used in lists; `as_detail_json`
# returns the full record including parent / child id mirrors and the
# `Pito::Calendar::NotificationDispatchDeclaration.declarations_for(entry)`
# array under `dispatch_declarations`.
class CalendarEntryDecorator < ApplicationDecorator
  def as_summary_json
    {
      id: id,
      entry_type: entry_type,
      title: title,
      starts_at: starts_at&.iso8601,
      ends_at: ends_at&.iso8601,
      all_day: YesNo.to_yes_no(all_day),
      timezone: timezone,
      state: state,
      source: source,
      read_only: YesNo.to_yes_no(read_only?),
      game_id: game_id,
      video_id: video_id,
      channel_id: channel_id,
      milestone_rule_id: milestone_rule_id
    }
  end

  def as_detail_json
    as_summary_json.merge(
      description: description,
      manual_date_override: YesNo.to_yes_no(manual_date_override),
      release_precision: release_precision,
      tba_remind_monthly: YesNo.to_yes_no(tba_remind_monthly),
      notify_anyway: YesNo.to_yes_no(notify_anyway),
      metadata: metadata || {},
      parent_entry_id: parent_entry_id,
      child_entry_ids: child_entries.pluck(:id),
      created_by_user_id: created_by_user_id,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    )
  end

  # Top-level sibling array shipped alongside `entry` on the show
  # response. Mirrors `Pito::Calendar::NotificationDispatchDeclaration.declarations_for`
  # with ISO-8601 timestamps applied to the `fires_at` field.
  def dispatch_declarations_json
    Pito::Calendar::NotificationDispatchDeclaration.declarations_for(object).map do |d|
      d.merge(fires_at: d[:fires_at]&.iso8601)
    end
  end
end
