# Pure function. Renders a calendar window identifier as a human label.
#
# Two variants: short (default) for compact display, long for prose.
#
# Examples:
#   call("7d")           => "7d"
#   call("7d", long: true)   => "last 7 days"
#   call("28d")          => "28d"
#   call("90d")          => "90d"
#   call("lifetime")     => "lifetime"
#   call("unknown")      => "unknown"  (passthrough)
module Pito
  module Formatter
    module AnalyticsWindowLabel
      WINDOW_SHORT = {
        "7d"       => "7d",
        "28d"      => "28d",
        "90d"      => "90d",
        "lifetime" => "lifetime"
      }.freeze

      WINDOW_LONG = {
        "7d"       => "last 7 days",
        "28d"      => "last 28 days",
        "90d"      => "last 90 days",
        "lifetime" => "lifetime"
      }.freeze

      module_function

      def call(window, long: false)
        table = long ? WINDOW_LONG : WINDOW_SHORT
        table.fetch(window.to_s, window.to_s)
      end
    end
  end
end
