module CompactTimeHelper
  # Compact, presentation-only relative time string.
  # Raw timestamps in JSON stay ISO 8601 — this is for the view layer only.
  def compact_time_ago(time)
    return "never" if time.nil?
    seconds = (Time.current - time).to_i
    return "~60s ago" if seconds < 60
    return "~#{seconds / 60}m ago" if seconds < 3600
    return "~#{seconds / 3600}h ago" if seconds < 86_400
    return "~#{seconds / 86_400}d ago" if seconds < 2_592_000  # 30 days
    return "~#{seconds / 2_592_000}mo ago" if seconds < 31_536_000  # 365 days
    "~#{seconds / 31_536_000}yr ago"
  end
end
