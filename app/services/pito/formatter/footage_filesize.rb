# Pure function. Byte formatter for footage table cells.
#
# Returns the em-dash placeholder for nil and 0 since both mean
# "the importer hasn't probed this row yet" rather than a legitimate
# zero-byte file.
#
# Differs from Pito::Formatter::FilesizeInt (stack pane) in two ways:
#   1. 0 returns "—" (not a legitimate zero in this context).
#   2. Uses fractional precision (e.g. "1.4 GB").
#
# Standalone — no ActionView dependency.
#
# Examples:
#   call(nil)            => "—"
#   call(0)              => "—"
#   call(789)            => "789 B"
#   call(123_456)        => "121 KB"
#   call(1_500_000_000)  => "1.4 GB"
module Pito
  module Formatter
    class FootageFilesize
      UNITS = %w[B KB MB GB TB PB].freeze

      def self.call(bytes)
        return "—" if bytes.nil?
        bytes = bytes.to_f
        return "—" if bytes.zero?

        idx = 0
        while bytes >= 1024 && idx < UNITS.length - 1
          bytes /= 1024
          idx += 1
        end

        formatted = idx >= 2 ? format("%.1f", bytes) : bytes.round.to_s
        "#{formatted} #{UNITS[idx]}"
      end
    end
  end
end
