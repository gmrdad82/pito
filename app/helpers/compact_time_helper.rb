module CompactTimeHelper
  # Compact, presentation-only relative time string.
  # Raw timestamps in JSON stay ISO 8601 — this is for the view layer only.
  #
  # Rounding rule: always ROUND DOWN. A "just-finished" event shows
  # `~0s ago`, not `~60s ago`. Integer division (`/`) already floors for
  # non-negative integers; the bug was the hardcoded `~60s ago` bucket
  # at the bottom — fixed by emitting `~Xs ago` for the 0..59s range.
  # A negative delta (clock skew, future-stamped row) clamps to `~0s ago`.
  def compact_time_ago(time)
    return "never" if time.nil?
    seconds = (Time.current - time).to_i
    seconds = 0 if seconds.negative?
    return "~#{seconds}s ago" if seconds < 60
    return "~#{seconds / 60}m ago" if seconds < 3600
    return "~#{seconds / 3600}h ago" if seconds < 86_400
    return "~#{seconds / 86_400}d ago" if seconds < 2_592_000  # 30 days
    return "~#{seconds / 2_592_000}mo ago" if seconds < 31_536_000  # 365 days
    "~#{seconds / 31_536_000}yr ago"
  end
end
