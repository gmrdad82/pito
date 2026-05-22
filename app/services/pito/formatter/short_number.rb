module Pito
  module Formatter
    # Pito::Formatter::ShortNumber — short-format a non-negative integer for
    # display in width-constrained UI cells (e.g. top status bar Sidekiq
    # queue-depth cells `b<n> e<n> r<n>`).
    #
    # The output is intentionally NOT padded — callers pad to their own
    # column width (the sidekiq cells pad to 4 chars via Ruby `ljust` /
    # JS `padEnd`).
    #
    # Truth table (must agree with JS counterpart in
    # `tui_sidekiq_stats_controller.js#shortFormat`):
    #
    #   0              → "0"
    #   32             → "32"
    #   999            → "999"
    #   1_000          → "1k"
    #   22_345         → "22k"
    #   899_000        → "899k"
    #   1_000_000      → "1M"
    #   1_500_000      → "1M"
    #   999_999_999    → "999M"
    #   1_000_000_000  → "1B"
    #
    # Negative inputs are treated as their absolute value. `nil` returns "".
    #
    # @contract see app/javascript/controllers/tui_sidekiq_stats_controller.js
    module ShortNumber
      module_function

      # Short-format a value for a 4-char-wide UI cell.
      #
      # @param value [Integer, nil] the raw count
      # @return [String] short-formatted string (no padding)
      def call(value)
        return "" if value.nil?

        n = value.to_i.abs
        return n.to_s              if n < 1_000
        return "#{n / 1_000}k"     if n < 1_000_000
        return "#{n / 1_000_000}M" if n < 1_000_000_000

        "#{n / 1_000_000_000}B"
      end
    end
  end
end
