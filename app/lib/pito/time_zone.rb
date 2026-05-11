# Phase 26 — viewer-time analytics support utility.
#
# Pure-function helper that normalizes whatever `time_zone` shape a
# caller hands us into a canonical IANA name. Originally lived on
# `VideoViewerTimeBucket.resolve_iana` (P26 §01g); moved here per the
# P26 reviewer concern 5 — the helper is not a model concern, it is a
# tz-shape conversion utility shared by the rollup scope, the
# `Analytics::ViewerTimeRollup` service, and any future caller that
# needs to pass an IANA tz name into a SQL `AT TIME ZONE` clause.
#
# Accepts:
#
#   - `ActiveSupport::TimeZone` instances — uses the tzinfo identifier.
#   - IANA names (`"Europe/Bucharest"`, `"America/New_York"`,
#     `"Pacific/Kiritimati"`) — passes them straight through.
#   - Rails-friendly aliases (`"Eastern Time (US & Canada)"`) — resolves
#     via `ActiveSupport::TimeZone[]` to the IANA name.
#
# Returns:
#
#   - The IANA name on success.
#   - `"Etc/UTC"` for nil / non-string / unrecognized input — the
#     defensive default the rollup query and the renderer both treat
#     as the "no preference" baseline.
module Pito
  module TimeZone
    module_function

    def resolve_iana(tz)
      case tz
      when ActiveSupport::TimeZone
        tz.tzinfo.name
      when String, Symbol
        lookup = ActiveSupport::TimeZone[tz.to_s]
        lookup ? lookup.tzinfo.name : tz.to_s
      else
        "Etc/UTC"
      end
    end
  end
end
