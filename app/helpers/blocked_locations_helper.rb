# Phase 25 — 01f. View helpers for the auto-block list surface.
#
# Maps the `BlockedLocation` enum + reason strings to display copy and
# formats the small bits of presentation logic (age, badge text) the
# row component and the show page share. Centralising the labels here
# keeps the index table, the detail page, and the unblock action-screen
# aligned on one vocabulary.
module BlockedLocationsHelper
  SOURCE_LABELS = {
    "web" => "web",
    "tui" => "tui",
    "mcp" => "mcp"
  }.freeze

  # Render the source-surface badge as a short uppercase code. The
  # original `source_surface` value is the enum string; if a future
  # surface is added the helper falls back to the raw value so the
  # display never silently drops a row.
  def blocked_location_source_badge(row)
    label = SOURCE_LABELS[row.source_surface.to_s] || row.source_surface.to_s
    label.upcase
  end

  # State label — `"active"` when the row is still enforcing the block,
  # `"unblocked"` when it has been soft-unblocked. The detail page also
  # surfaces the timestamp; the index table only needs the word.
  def blocked_location_state_label(row)
    row.active? ? "active" : "unblocked"
  end

  # CSS class for the state cell. Only the active state gets emphasis
  # (we never paint a `BlockedLocation` row red — the red is reserved
  # for destructive *actions* like `[purge]`, not for the block itself).
  def blocked_location_state_css(row)
    row.active? ? "" : "text-muted"
  end

  # Reason copy — `BlockedLocation#reason` is a free-text column today
  # (no enum). When absent fall back to a `"—"` sentinel so the dl/td
  # never renders empty.
  def blocked_location_reason_label(row)
    row.reason.presence || "—"
  end

  # Compact age string — "5m", "2h", "3d", etc. Used in the row
  # component's `blocked` column when the timestamp is recent enough to
  # be more readable as a delta than as a full ISO timestamp.
  def blocked_location_age(row, now: Time.current)
    return "—" unless row.blocked_at
    seconds = (now - row.blocked_at).to_i
    return "now" if seconds < 60
    return "#{seconds / 60}m"   if seconds < 3_600
    return "#{seconds / 3_600}h" if seconds < 86_400
    "#{seconds / 86_400}d"
  end
end
