module CompactTimeHelper
  # Compact, presentation-only relative time string.
  # Delegates to Pito::Formatter::CompactTimeAgo — see that module for
  # full rules and examples.
  def compact_time_ago(time)
    Pito::Formatter::CompactTimeAgo.call(time)
  end
end
