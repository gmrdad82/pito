# Phase 15 §2 — Calendar Views (Month Grid + Schedule).
#
# Small helpers for the month grid + schedule views. Each method
# returns lowercase monospace strings per `docs/design.md`.
module CalendarHelper
  # Per-type prefix glyph (Q6 master decision). Retained for backward
  # compatibility with JSON consumers / decorator paths only; the
  # month + schedule UI no longer renders the glyph (calendar refactor
  # 2026-05-11). The visible label is now produced by
  # `entry_type_label` — a typed token like `channel(joined)`.
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

  # Typed entry-type labels rendered on the month grid + schedule list
  # (calendar refactor 2026-05-11). Replaces the cryptic single-letter
  # glyph prefixes with a typed token of the form `type(event)`.
  ENTRY_TYPE_LABELS = {
    "channel_published" => "channel(joined)",
    "video_published"   => "video(published)",
    "video_scheduled"   => "video(scheduled)",
    "game_release"      => "game(released)",
    "purchase_planned"  => "purchase(planned)",
    "milestone_manual"  => "milestone",
    "milestone_auto"    => "milestone(auto)",
    "custom"            => "custom"
  }.freeze

  # Maps the user-facing filter labels to their member entry_types.
  # `"all"` is a synthetic master-toggle label used by the UI; it is not
  # accepted in the `?types=` URL csv (validation drops it). The five
  # individual labels are the only valid CSV members.
  ENTRY_KIND_FILTERS = {
    "all"       => nil,                                       # no filter
    "video"     => %w[video_published video_scheduled],
    "game"      => %w[game_release],
    "milestone" => %w[milestone_manual milestone_auto],
    "purchase"  => %w[purchase_planned],
    "custom"    => %w[custom]
  }.freeze

  # Individual kind labels (the 5 chips) — derived from
  # ENTRY_KIND_FILTERS minus the synthetic "all" master.
  CALENDAR_KIND_LABELS = (ENTRY_KIND_FILTERS.keys - [ "all" ]).freeze

  # Parse the `?types=` URL parameter into the active kind labels.
  #
  # Returns:
  #   :all   — param absent (default state — all 5 checked)
  #   :none  — param present but empty / all-invalid (all 5 unchecked)
  #   Array  — explicit subset of valid labels
  def calendar_active_kinds(raw)
    return :all if raw.nil?
    values = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    return :none if values.empty?
    kept = values.select { |v| CALENDAR_KIND_LABELS.include?(v) }
    return :none if kept.empty?
    kept
  end

  # Is the given individual kind label currently rendered as checked?
  def calendar_kind_checked?(label, raw_types_param)
    active = calendar_active_kinds(raw_types_param)
    case active
    when :all  then true
    when :none then false
    else            active.include?(label)
    end
  end

  # Master-toggle "all" checked state. Mirrors the spec: checked when
  # the param is absent OR every individual label is in the csv.
  def calendar_all_kinds_checked?(raw_types_param)
    active = calendar_active_kinds(raw_types_param)
    case active
    when :all  then true
    when :none then false
    else            (CALENDAR_KIND_LABELS - active).empty?
    end
  end

  # Build the URL for clicking an individual kind chip. Toggles the
  # label's membership in the csv list. Other params on `current_params`
  # (e.g. `state`, `source`, `page`) are preserved.
  def calendar_kind_chip_href(label, raw_types_param, current_params:)
    new_params = current_params.to_h.with_indifferent_access.except(:controller, :action, :year, :month).to_h.transform_keys(&:to_s)
    case calendar_active_kinds(raw_types_param)
    when :all
      # Implicit "all" → flip this label off, leaving the other 4 explicit.
      remaining = CALENDAR_KIND_LABELS - [ label ]
      new_params["types"] = remaining.join(",")
    when :none
      # Implicit "none" → flip this label on, leaving the other 4 off.
      new_params["types"] = label
    else
      values = calendar_active_kinds(raw_types_param)
      if values.include?(label)
        values = values - [ label ]
      else
        values = (values + [ label ]).uniq
      end
      new_params["types"] = values.join(",")
    end
    new_params.empty? ? "?" : "?#{new_params.to_query}"
  end

  # URL for the master `[all]` synthetic toggle. Clicking flips
  # between "all checked" and "all unchecked". Checked → unchecked sets
  # `?types=` (empty). Unchecked → checked drops the `types` param so
  # the URL reverts to the "no param = all" default.
  def calendar_all_kinds_chip_href(raw_types_param, current_params:)
    new_params = current_params.to_h.with_indifferent_access.except(:controller, :action, :year, :month).to_h.transform_keys(&:to_s)
    if calendar_all_kinds_checked?(raw_types_param)
      new_params["types"] = ""
    else
      new_params.delete("types")
    end
    new_params.empty? ? "?" : "?#{new_params.to_query}"
  end

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

  # Typed token label rendered on the month grid + schedule list as a
  # replacement for the legacy single-letter glyph prefix. Lowercase
  # monospace per `docs/design.md`. Unknown types fall back to
  # `custom`.
  def entry_type_label(entry)
    ENTRY_TYPE_LABELS.fetch(entry.entry_type, "custom")
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
    install_tz = Rails.application.config.x.pito.timezone
    entry.starts_at.in_time_zone(install_tz).strftime("%H:%M")
  end

  # Lowercase abbreviated date label per `docs/design.md`. e.g. `mar 14`.
  def entry_date_label(entry)
    install_tz = Rails.application.config.x.pito.timezone
    entry.starts_at.in_time_zone(install_tz).strftime("%b %-d").downcase
  end

  # Schedule view per-day grouping label rendered in the date column.
  # Format: `may 10 sun` — lowercase abbreviated month, day-of-month,
  # lowercase 3-letter weekday. Calendar refactor 2026-05-11.
  def entry_date_grouping_label(entry)
    install_tz = Rails.application.config.x.pito.timezone
    entry.starts_at.in_time_zone(install_tz).strftime("%b %-d %a").downcase
  end

  # Stable cache key used by the schedule view to detect "same day as
  # previous row" — the date column is suppressed when this matches the
  # previous iteration. Uses the entry's starts_at in the install
  # timezone.
  def entry_grouping_day_key(entry)
    install_tz = Rails.application.config.x.pito.timezone
    entry.starts_at.in_time_zone(install_tz).to_date.iso8601
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

  # ── Home-panel calendar filter helpers (4-category `calendar_filter[*]`) ──
  #
  # The home Calendar panel uses a coarser 4-chip filter model than the
  # standalone /calendar views. Four category chips map to the 8 entry_types:
  #
  #   channel  → channel_published, video_published, video_scheduled
  #   game     → game_release, purchase_planned
  #   system   → milestone_auto
  #   manual   → milestone_manual, custom
  #
  # URL shape: `?calendar_filter[channel]=on&calendar_filter[game]=on`
  # (Rails hash param). When ALL chips are on (or param absent entirely),
  # no WHERE clause is added — all entries are shown. When ALL are off,
  # an empty result is returned (`.none`).

  PANEL_CALENDAR_CATEGORIES = {
    "channel" => %w[channel_published video_published video_scheduled],
    "game"    => %w[game_release purchase_planned],
    "system"  => %w[milestone_auto],
    "manual"  => %w[milestone_manual custom]
  }.freeze

  # Parse `params[:calendar_filter]` (Hash of category→"on" pairs).
  # Returns:
  #   :all   — param absent / nil (default — all 4 categories shown)
  #   :none  — param present (even empty hash) but no category is "on"
  #   Array  — explicit subset of valid category keys
  def panel_calendar_active_categories(raw_filter)
    return :all if raw_filter.nil?
    active = PANEL_CALENDAR_CATEGORIES.keys.select { |k| raw_filter[k].to_s == "on" }
    active.empty? ? :none : active
  end

  # Is the given category chip currently active?
  def panel_calendar_category_active?(category, raw_filter)
    active = panel_calendar_active_categories(raw_filter)
    case active
    when :all  then true
    when :none then false
    else            active.include?(category)
    end
  end

  # Build the toggle URL for clicking a category chip. Flips the chip's
  # membership. Other URL params (sort, etc.) are preserved.
  def panel_calendar_chip_href(category, raw_filter, current_params:)
    base = current_params.to_h.with_indifferent_access
                         .except(:controller, :action)
                         .to_h.transform_keys(&:to_s)
    existing = panel_calendar_active_categories(raw_filter)
    current_set = case existing
    when :all  then PANEL_CALENDAR_CATEGORIES.keys.dup
    when :none then []
    else            existing.dup
    end
    if current_set.include?(category)
      current_set.delete(category)
    else
      current_set << category
    end
    # Rebuild calendar_filter hash
    if current_set.sort == PANEL_CALENDAR_CATEGORIES.keys.sort
      # All on — drop the param entirely (canonical "all" state = no param)
      base.delete("calendar_filter")
    elsif current_set.empty?
      base["calendar_filter"] = {}
    else
      base["calendar_filter"] = current_set.index_with { "on" }
    end
    base.empty? ? "?" : "?#{base.to_query}"
  end

  # Filter an entries scope by the active panel calendar categories.
  # Returns the relation (possibly `.none`) to the caller.
  def panel_calendar_filter_scope(scope, raw_filter)
    active = panel_calendar_active_categories(raw_filter)
    case active
    when :all  then scope
    when :none then scope.none
    else
      types = active.flat_map { |cat| PANEL_CALENDAR_CATEGORIES[cat] }.compact
      scope.where(entry_type: types)
    end
  end

  # Short display text for a calendar entry bullet in a day cell.
  # Truncates to PANEL_CHIP_TITLE_LENGTH characters.
  PANEL_CHIP_TITLE_LENGTH = 22

  def panel_calendar_bullet_text(entry)
    raw = entry.title.to_s
    raw.length <= PANEL_CHIP_TITLE_LENGTH ? raw : "#{raw[0...PANEL_CHIP_TITLE_LENGTH]}…"
  end

  # CSS category modifier for coloring bullets and chips.
  def panel_calendar_entry_category(entry)
    case entry.entry_type
    when "channel_published", "video_published", "video_scheduled" then "channel"
    when "game_release", "purchase_planned"                         then "game"
    when "milestone_auto"                                           then "system"
    else                                                                 "manual"
    end
  end
end
