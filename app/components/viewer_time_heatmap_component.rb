# Phase 26 — 01g. Viewer-time analytics implementation.
#
# Renders a 7x24 day-of-week x hour-of-day heatmap from the rollup
# hash produced by `Analytics::ViewerTimeRollup#call`. Single-hue
# intensity gradient (link-blue with alpha 0.0..1.0) — no red, per
# the project's design rules.
#
# `data` is a hash keyed `[dow_local, hod_local] => Result` where each
# Result responds to `views` and `watch_time_seconds`. Missing cells
# render as the zero-intensity baseline.
#
# Mobile collapses to a vertical 7-strip stack via a CSS media query
# in `app/assets/tailwind/application.css`.
class ViewerTimeHeatmapComponent < ViewComponent::Base
  # Day-of-week labels are indexed by Postgres `extract(dow ...)`:
  # Sunday = 0, Saturday = 6.
  DAY_LABELS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
  HOURS = (0..23).to_a.freeze
  DAYS  = (0..6).to_a.freeze

  INTENSITY_OPTIONS = %i[views watch_time].freeze

  def initialize(data:, tz: nil, intensity_by: :views)
    @data = data || {}
    @tz = tz
    @intensity_by = intensity_by.to_sym
    unless INTENSITY_OPTIONS.include?(@intensity_by)
      raise ArgumentError,
            "intensity_by must be one of #{INTENSITY_OPTIONS.inspect} (got #{intensity_by.inspect})"
    end
  end

  def empty?
    @data.empty?
  end

  # Maximum intensity in the data — drives the alpha normalization.
  # Returns 0 when the data is empty (caller checks `#empty?` first).
  def max_value
    @max_value ||= @data.values.map { |cell| value_for(cell) }.max.to_i
  end

  def value_for(cell)
    case @intensity_by
    when :views
      cell.views.to_i
    when :watch_time
      cell.watch_time_seconds.to_i
    end
  end

  # Cell at `(dow, hod)` — returns the Result or nil.
  def cell_at(dow, hod)
    @data[[ dow, hod ]]
  end

  # 0.0..1.0 normalized intensity for the cell. Empty cells return
  # 0.0; the renderer uses CSS rgba() to interpolate to link-blue.
  def intensity_at(dow, hod)
    cell = cell_at(dow, hod)
    return 0.0 if cell.nil?
    return 0.0 if max_value.zero?

    value_for(cell).to_f / max_value.to_f
  end

  # Pretty tooltip text — day name, hour, both totals — for the hover.
  def tooltip_at(dow, hod)
    cell = cell_at(dow, hod)
    label = "#{DAY_LABELS[dow]} #{hod.to_s.rjust(2, '0')}:00"
    if cell.nil?
      "#{label} — no data"
    else
      "#{label} — #{cell.views.to_i} views, #{cell.watch_time_seconds.to_i}s watched"
    end
  end

  # CSS rgba string for the cell. Link-blue (#0000cc) with alpha
  # proportional to the cell's normalized intensity. The "no data"
  # baseline reuses the body bg-tint so empty cells blend into the
  # surrounding surface (pane backgrounds were dropped 2026-05-20).
  def background_for(dow, hod)
    intensity = intensity_at(dow, hod)
    if intensity.zero?
      "var(--color-bg-tint, #fafafa)"
    else
      "rgba(0, 0, 204, #{intensity.round(4)})"
    end
  end

  def tz_label
    return nil if @tz.blank?
    @tz.to_s
  end

  def intensity_by
    @intensity_by
  end
end
