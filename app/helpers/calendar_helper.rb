# Phase 15 §2 — Calendar Views (Month Grid + Schedule).
#
# Small helpers for the month grid + schedule views. Each method
# returns lowercase monospace strings per `docs/design.md`.
module CalendarHelper
  # Per-type prefix glyph (Q6 master decision). Used by the chip
  # component on the month grid AND the schedule row partial.
  ENTRY_GLYPHS = {
    "channel_published" => "c:",
    "video_published"   => "v:",
    "video_scheduled"   => "v?:",
    "game_release"      => "g:",
    "purchase_planned"  => "$:",
    "milestone_manual"  => "m:",
    "milestone_auto"    => "m*:",
    "custom"            => "~:"
  }.freeze

  # Maps the user-facing filter labels to their member entry_types.
  ENTRY_KIND_FILTERS = {
    "all"       => nil,                                       # no filter
    "video"     => %w[video_published video_scheduled],
    "game"      => %w[game_release],
    "milestone" => %w[milestone_manual milestone_auto],
    "purchase"  => %w[purchase_planned],
    "custom"    => %w[custom]
  }.freeze

  # Build the Monday-first 6×7 (or 5×7) grid of Date objects covering
  # the given month. The leading dates are the previous-month tail
  # needed to align the first day of the month under its weekday
  # column; the trailing dates round out to a complete row.
  def month_grid_dates(year, month)
    first = Date.new(year, month, 1)
    last  = Date.new(year, month, -1)
    # Monday-first: cwday 1 = Monday, ..., 7 = Sunday.
    leading = (first.cwday - 1)
    grid_start = first - leading.days
    # Round up to a multiple of 7.
    total_days = (last - grid_start).to_i + 1
    rows = (total_days / 7.0).ceil
    Array.new(rows * 7) { |i| grid_start + i.days }
  end

  def entry_chip_glyph(entry)
    ENTRY_GLYPHS.fetch(entry.entry_type, "~:")
  end

  # Class name driven by entry state. The view layer maps these to
  # CSS rules: `scheduled` is normal, `occurred` muted, `cancelled`
  # strike-through, `superseded` muted + strike-through.
  def entry_chip_class(entry)
    "calendar-entry calendar-entry--#{entry.state}"
  end

  # Time portion of a timed entry (HH:MM) in the install tz, or "" for
  # all-day. Per Q12.
  def entry_time_label(entry)
    return "" if entry.all_day
    install_tz = AppSetting.first&.timezone || "UTC"
    entry.starts_at.in_time_zone(install_tz).strftime("%H:%M")
  end

  # Lowercase abbreviated date label per `docs/design.md`. e.g. `mar 14`.
  def entry_date_label(entry)
    install_tz = AppSetting.first&.timezone || "UTC"
    entry.starts_at.in_time_zone(install_tz).strftime("%b %-d").downcase
  end

  # Cross-link target for a derived entry's title. Per Q13.
  # Returns nil for non-derived entries (the view falls back to the
  # entry's own show page).
  def entry_link_target(entry)
    case entry.entry_type
    when "video_published", "video_scheduled"
      Rails.application.routes.url_helpers.video_path(entry.video_id) if entry.video_id
    when "channel_published"
      Rails.application.routes.url_helpers.channel_path(entry.channel_id) if entry.channel_id
    when "game_release"
      Rails.application.routes.url_helpers.game_path(entry.game_id) if entry.game_id
    end
  end

  # Truncate a chip title to fit a fixed width. Per Open question #9
  # decision: 24 chars + ellipsis.
  CHIP_TITLE_LENGTH = 24

  def entry_chip_title(entry)
    raw = entry.title.to_s
    return raw if raw.length <= CHIP_TITLE_LENGTH
    "#{raw[0...CHIP_TITLE_LENGTH]}…"
  end

  # Lowercase abbreviated month-year heading: `mar 2026`.
  def calendar_month_heading(year, month)
    Date.new(year, month, 1).strftime("%b %Y").downcase
  end

  # Group entries by date (in install tz). Used by the month grid
  # bucketing.
  def bucket_entries_by_date(entries, tz: "UTC")
    entries.group_by { |e| e.starts_at.in_time_zone(tz).to_date }
  end
end
