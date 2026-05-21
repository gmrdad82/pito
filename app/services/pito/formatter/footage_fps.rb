# Pure function. Fps value formatter for footage table cells.
#
# Returns "—" for nil, 0, or negative values. Integer-equivalent floats
# (24.0, 30.0, 60.0) render as integer strings. Industry-standard
# fractional rates (23.976, 29.97, 59.94) render as canonical 2-decimal
# labels. Any other fractional value renders with 2-decimal precision.
#
# Examples:
#   call(nil)    => "—"
#   call(0)      => "—"
#   call(24.0)   => "24"
#   call(23.976) => "23.97"
#   call(29.97)  => "29.97"
#   call(60.0)   => "60"
#   call(50.5)   => "50.50"
module Pito
  module Formatter
    module FootageFps
      EM_DASH = "—"

      STANDARD_FPS = {
        23.976 => "23.97",
        29.97  => "29.97",
        47.952 => "47.95",
        59.94  => "59.94"
      }.freeze

      module_function

      def call(value)
        return EM_DASH if value.nil?

        f = value.to_f
        return EM_DASH if f <= 0

        rounded = f.round
        return rounded.to_s if (f - rounded).abs < 0.001

        STANDARD_FPS.each do |key, label|
          return label if (f - key).abs < 0.01
        end

        format("%.2f", f)
      end
    end
  end
end
