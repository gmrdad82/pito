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

  # Default tail length covers OBS-style trailing timestamps:
  # ` - YYYY-MM-DD HH-MM-SS.mkv` is exactly 26 characters; 23 keeps the
  # space + date + time + extension in view (`23-34-48.mkv` and the
  # immediately preceding ` - YYYY-MM-DD `) without burning so much
  # width that the head collapses on shorter pane widths. Mirrors the
  # CLI TUI middle-truncation pattern (see
  # `extras/cli/src/footage/ui/confirmation.rs#middle_truncate`).
  FOOTAGE_FILENAME_TAIL = 23

  # Splits a footage filename into a [head, tail] pair so the view can
  # middle-truncate via CSS — the head shrinks with `text-overflow:
  # ellipsis`, the tail stays pinned. Returns `[full_name, ""]` when the
  # filename is short enough that no truncation is necessary, letting the
  # caller render a single span and skip the flex split.
  def filename_split(filename, tail: FOOTAGE_FILENAME_TAIL)
    name = filename.to_s
    return [ name, "" ] if name.length <= tail
    [ name[0...-tail], name[-tail..] ]
  end
end
