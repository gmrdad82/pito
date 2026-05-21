# Pure function. Source-enum to display-label formatter for footage.
#
# The source column on the footage table renders the enum string as a
# human-readable label. Unknown values fall back to titleize so adding
# a new enum member doesn't require a label-table edit.
#
# Examples:
#   call(nil)       => "—"
#   call("")        => "—"
#   call("obs")     => "OBS"
#   call("camera")  => "Camera"
#   call("drone")   => "Drone"  (titleize fallback)
module Pito
  module Formatter
    module FootageSource
      EM_DASH = "—"

      SOURCE_LABELS = {
        "obs"    => "OBS",
        "camera" => "Camera"
      }.freeze

      module_function

      def call(source)
        return EM_DASH if source.to_s.blank?

        SOURCE_LABELS.fetch(source.to_s, source.to_s.split("_").map(&:capitalize).join(" "))
      end
    end
  end
end
