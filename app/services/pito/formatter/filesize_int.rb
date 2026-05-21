# Pure function. Integer-only byte formatter.
#
# KB is the smallest unit shown. Always rounds to the nearest integer.
# Nil returns "—". Zero returns "0 KB" (legitimate zero — stack-pane
# storage probes always return a real number, not "not probed yet").
#
# Differs from FootageHelper#human_filesize in two ways:
#   1. KB minimum unit (never "512 Bytes").
#   2. Always integer output (no fractional digits).
#
# Used by the /settings stack pane tables (Postgres / Redis /
# Meilisearch / assets / notes).
#
# Examples:
#   nil         => "—"
#   0           => "0 KB"
#   512         => "1 KB"
#   1_024       => "1 KB"
#   49_800      => "49 KB"
#   1_048_576   => "1 MB"
module Pito
  module Formatter
    module FilesizeInt
      EM_DASH = "—"
      UNITS = %w[KB MB GB TB PB].freeze

      module_function

      def call(bytes)
        return EM_DASH if bytes.nil?

        n = bytes.to_f / 1_024.0
        unit_index = 0

        while n >= 1_024 && unit_index < UNITS.length - 1
          n /= 1_024.0
          unit_index += 1
        end

        "#{n.round} #{UNITS[unit_index]}"
      end
    end
  end
end
