# Phase 26 — 01a. Timezone foundation render-layer helpers.
#
# `l_user_tz(time, format:)` is the single conversion site every view
# uses to render a stored-UTC timestamp into the authenticated user's
# local zone. UTC is the storage rule everywhere — the helpers here
# are the only render-time conversion contract.
#
# `Time.zone` is set per-request by
# `ApplicationController#set_user_time_zone` to the user's stored
# zone, so `time.in_time_zone` resolves to the correct local clock
# without the helper having to look up `Current.user` itself.
module TimeZoneHelper
  # Built-in `l(time, format:)` would format using `Time.zone` already,
  # but `l_user_tz` is the contract name downstream sub-specs (01e
  # digest scheduler, 01g viewer-time, 01h scheduled publish) read
  # against. Keep the indirection so swapping the conversion site is
  # a one-grep operation.
  #
  # Format set:
  #   - :long  (default) — "May 11, 2026 13:27 EEST"
  #   - :short            — "13:27 EEST"
  #   - :date             — "May 11, 2026"
  #   - :iso              — full ISO 8601 with offset
  #
  # Accepts `Time`, `DateTime`, `ActiveSupport::TimeWithZone`, or
  # `nil`. Nil returns the literal "—" so callers do not have to
  # short-circuit themselves.
  def l_user_tz(time, format: :long)
    return "—" if time.nil?

    local = time.in_time_zone(Time.zone)

    case format
    when :long
      local.strftime("%b %-d, %Y %H:%M %Z")
    when :short
      local.strftime("%H:%M %Z")
    when :date
      local.strftime("%b %-d, %Y")
    when :iso
      local.iso8601
    else
      local.strftime("%b %-d, %Y %H:%M %Z")
    end
  end

  # The user's current wall-clock time in their stored zone. Used by
  # the header chrome to confirm the active zone visually. Always
  # resolves through `Time.zone` (set per request by
  # `ApplicationController#set_user_time_zone`).
  def current_time_in_user_tz(format: :short)
    l_user_tz(Time.current, format: format)
  end
end
