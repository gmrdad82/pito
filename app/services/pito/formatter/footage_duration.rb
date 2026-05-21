# Pure function. Humanized duration for footage table cells.
#
# Renders a duration in seconds as "Xh Ym Zs" / "Ym Zs" / "Zs".
# Returns "—" for nil and non-positive values (means "not probed yet").
#
# Differs from Pito::Formatter::Duration (H:MM:SS for video stats) in
# that it uses the verbose Xh Ym Zs form suited to footage-cell density.
#
# Examples:
#   call(nil)    => "—"
#   call(0)      => "—"
#   call(45)     => "45s"
#   call(125)    => "2m 5s"
#   call(3725)   => "1h 2m 5s"
module Pito
  module Formatter
    module FootageDuration
      EM_DASH = "—"

      module_function

      def call(seconds)
        return EM_DASH if seconds.nil?

        secs = seconds.to_i
        return EM_DASH if secs <= 0

        hours = secs / 3_600
        mins  = (secs % 3_600) / 60
        rem   = secs % 60

        parts = []
        parts << "#{hours}h" if hours.positive?
        parts << "#{mins}m"  if mins.positive? || hours.positive?
        parts << "#{rem}s"
        parts.join(" ")
      end
    end
  end
end
