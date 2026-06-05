# frozen_string_literal: true

# Pure function. Renders a Time value as a compact relative string.
#
# Rounding rule: always ROUND DOWN (integer division floors for
# non-negative values). A just-finished event shows `~0s ago`, not
# `~60s ago`. Negative deltas (clock skew, future-stamped rows) clamp
# to `~0s ago`. Nil returns "never".
#
# Examples:
#   nil                         => "never"
#   0..59 seconds ago           => "~Xs ago"
#   60..3599 seconds ago        => "~Xm ago"
#   3600..86399 seconds ago     => "~Xh ago"
#   86400..2591999 seconds ago  => "~Xd ago"
#   2592000..31535999 secs ago  => "~Xmo ago"
#   31536000+ seconds ago       => "~Xyr ago"
#
# Pure function — no I/O, no Rails dependency (uses Time argument
# directly). Requires Time.current call at the call site if you need
# relative-to-now.
module Pito
  module Formatter
    module CompactTimeAgo
      module_function

      def call(time)
        return "never" if time.nil?

        seconds = (Time.current - time).to_i
        seconds = 0 if seconds.negative?

        return "~#{seconds}s ago" if seconds < 60
        return "~#{seconds / 60}m ago" if seconds < 3_600
        return "~#{seconds / 3_600}h ago" if seconds < 86_400
        return "~#{seconds / 86_400}d ago" if seconds < 2_592_000
        return "~#{seconds / 2_592_000}mo ago" if seconds < 31_536_000

        "~#{seconds / 31_536_000}yr ago"
      end
    end
  end
end
