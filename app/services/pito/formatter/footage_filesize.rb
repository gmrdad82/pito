# Pure function. Byte formatter for footage table cells.
#
# Returns the em-dash placeholder for nil and 0 since both mean
# "the importer hasn't probed this row yet" rather than a legitimate
# zero-byte file. Uses Rails' number_to_human_size semantics (2-digit
# precision, non-significant) when available, or falls back to a plain
# Ruby implementation.
#
# Differs from Pito::Formatter::FilesizeInt (stack pane) in two ways:
#   1. 0 returns "—" (not a legitimate zero in this context).
#   2. Uses fractional precision (e.g. "1.43 KB").
#
# This module delegates to ActionView::Helpers::NumberHelper when
# called from a helper context. For pure-Ruby usage (specs, services),
# callers must either include ActionView or use the standalone fallback
# below.
#
# Examples:
#   call(nil)    => "—"
#   call(0)      => "—"
#   call(512)    => "512 Bytes"
#   call(1_500)  => "1.46 KB"
module Pito
  module Formatter
    module FootageFilesize
      EM_DASH = "—"

      module_function

      def call(bytes, number_helper: nil)
        return EM_DASH if bytes.nil? || bytes.zero?

        if number_helper.respond_to?(:number_to_human_size)
          number_helper.number_to_human_size(bytes, precision: 2, significant: false)
        else
          human_size_fallback(bytes)
        end
      end

      def human_size_fallback(bytes)
        units = %w[Bytes KB MB GB TB]
        n = bytes.to_f
        unit_index = 0
        while n >= 1_024 && unit_index < units.length - 1
          n /= 1_024.0
          unit_index += 1
        end
        unit_index.zero? ? "#{n.round} Bytes" : "#{format('%.2f', n)} #{units[unit_index]}"
      end
    end
  end
end
