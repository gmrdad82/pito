module FootageHelper
  # Pito's "no value" placeholder for table cells.
  EMPTY_VALUE = "—".freeze

  FILENAME_HEAD = 8
  FILENAME_TAIL = 12

  # Delegates to Pito::Formatter::FootageFilesize.
  # Returns "—" for nil and 0 (not probed yet).
  def human_filesize(bytes)
    Pito::Formatter::FootageFilesize.call(bytes)
  end

  # Delegates to Pito::Formatter::FootageDuration.
  # Renders seconds as "Xh Ym Zs" / "Ym Zs" / "Zs". Returns "—" for nil/0.
  def human_duration(seconds)
    Pito::Formatter::FootageDuration.call(seconds)
  end

  # Delegates to Pito::Formatter::FootageFps.
  # Renders fps with canonical labels for industry-standard rates.
  def human_fps(value)
    Pito::Formatter::FootageFps.call(value)
  end

  # Delegates to Pito::Formatter::FootageSource.
  # Renders enum source string as display label (OBS, Camera, etc.).
  def human_source(source)
    Pito::Formatter::FootageSource.call(source)
  end

  # Footage filename column. Delegates to Pito::Formatter::MiddleTruncate
  # with footage-specific head/tail defaults.
  def filename_truncate_middle(filename, head: FILENAME_HEAD, tail: FILENAME_TAIL)
    Pito::Formatter::MiddleTruncate.call(filename, head: head, tail: tail)
  end
end
