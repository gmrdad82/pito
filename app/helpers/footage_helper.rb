module FootageHelper
  # Pito's "no value" placeholder for table cells. Mirrors the convention
  # already used in `app/views/channels/_pane.html.erb` and the resolution
  # column of `app/views/projects/_footage_pane.html.erb`.
  EMPTY_VALUE = "—".freeze

  # Renders a byte count using Rails' `number_to_human_size` (2-digit
  # precision, non-significant — matches the rest of the app's numeric
  # display style). Returns the em-dash placeholder for `nil` and `0`
  # since both mean "the importer hasn't probed this row yet" rather
  # than a legitimate zero-byte file.
  def human_filesize(bytes)
    return EMPTY_VALUE if bytes.nil? || bytes.zero?
    number_to_human_size(bytes, precision: 2, significant: false)
  end

  # Renders a duration in seconds as a compact `Xh Ym Zs` / `Ym Zs` / `Zs`
  # string. Pito's project workspace footage table uses this for the
  # `duration` column; sibling tables stay on `format_duration`
  # (`HH:MM:SS`) which suits per-row precision. The two helpers coexist
  # by intent — choose the form that matches the table's density.
  #
  # Returns the em-dash placeholder for nil / non-positive values
  # (mirrors `human_filesize` / `format_duration`: both mean "not
  # probed yet" rather than a legitimate zero-length clip).
  def human_duration(seconds)
    return EMPTY_VALUE if seconds.nil?
    secs = seconds.to_i
    return EMPTY_VALUE if secs <= 0
    hours = secs / 3600
    mins  = (secs % 3600) / 60
    rem   = secs % 60
    parts = []
    parts << "#{hours}h" if hours.positive?
    parts << "#{mins}m"  if mins.positive? || hours.positive?
    parts << "#{rem}s"
    parts.join(" ")
  end

  # Industry-standard fractional fps values that should render with a
  # 2-decimal short label rather than the default 2-decimal pattern. These
  # are the canonical broadcast/cinema rates — 23.976 (24/1.001), 29.97
  # (30/1.001), 59.94 (60/1.001) — and a couple of common siblings.
  # Matching is fuzzy: any input within ±0.01 of a key rounds to the
  # canonical label so BigDecimal/Float noise (`23.976000`, `29.97000`)
  # collapses cleanly. Order doesn't matter; the lookup is by tolerance.
  STANDARD_FPS = {
    23.976 => "23.97",
    29.97  => "29.97",
    47.952 => "47.95",
    59.94  => "59.94"
  }.freeze

  # Renders an fps value for the project workspace footage table.
  #
  # - nil / 0 / negative -> EMPTY_VALUE (em-dash placeholder, mirrors
  #   `human_filesize` / `human_duration`).
  # - Integer-equivalent (24.0, 30.0, 60.0, 120.0, ...) -> integer
  #   string (`"24"`, `"30"`, `"60"`). Fuzzy match (±0.001) so
  #   BigDecimal("60.000") survives Float coercion noise without falling
  #   into the fractional branch.
  # - Industry-standard fractional rates (23.976, 29.97, 59.94, ...) ->
  #   2-decimal canonical label from `STANDARD_FPS`. Matched within
  #   ±0.01 so stored values like 23.97600 still hit.
  # - Any other fractional value -> 2-decimal precision via
  #   `format("%.2f", ...)` (e.g. 50.5 -> `"50.50"`).
  #
  # Mirrors the table-cell helper pattern used elsewhere in the
  # workspace: pick the densest representation that doesn't lose
  # information at the row's precision.
  def human_fps(value)
    return EMPTY_VALUE if value.nil?
    f = value.to_f
    return EMPTY_VALUE if f <= 0

    rounded = f.round
    return rounded.to_s if (f - rounded).abs < 0.001

    STANDARD_FPS.each do |key, label|
      return label if (f - key).abs < 0.01
    end

    format("%.2f", f)
  end

  # Source-enum -> display label. The `source` column on the project
  # workspace footage table previously rendered the raw enum string
  # (`"obs"` / `"camera"`); the user-facing label uses the acronym
  # convention (`OBS`) for `obs` and a proper-noun-style capitalization
  # (`Camera`) for `camera`. Unknown values fall back to `titleize` so
  # adding a new enum member doesn't require a label-table edit; once
  # the new value is shipped, add it to `SOURCE_LABELS` for the
  # canonical form.
  SOURCE_LABELS = {
    "obs"    => "OBS",
    "camera" => "Camera"
  }.freeze

  def human_source(source)
    return EMPTY_VALUE if source.blank?
    SOURCE_LABELS.fetch(source.to_s, source.to_s.titleize)
  end

  # Project workspace footage filename column. Thin wrapper over
  # `ApplicationHelper#middle_truncate` that pins the footage-specific
  # head/tail defaults so OBS-style timestamped names collapse to
  # `Ghost 'n…23-11-43.mkv` (8 + 1 + 12 = 21 chars). The shared helper
  # produces a single `<head>…<tail>` string with a Unicode ellipsis
  # (U+2026) — never three ASCII dots. The view keeps the full filename
  # in a `title` attribute for hover-reveal. Mirrors the CLI TUI
  # middle-truncation pattern at
  # `extras/cli/src/footage/ui/confirmation.rs#middle_truncate`.
  FILENAME_HEAD = 8
  FILENAME_TAIL = 12

  def filename_truncate_middle(filename, head: FILENAME_HEAD, tail: FILENAME_TAIL)
    middle_truncate(filename, head: head, tail: tail)
  end
end
