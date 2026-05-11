# Phase 26 — 01h. Scheduled-publish tz wiring.
#
# UTC is the storage rule; user-tz is the picker rule. This helper is
# the single conversion site between the two for the video scheduled-
# publish flow:
#
#   - `parse_user_local_to_utc(date_str, time_str, user_tz)` takes the
#     form's date + time strings (from `<input type="datetime-local">`
#     or a separate date + time pair) plus the user's stored zone and
#     returns a UTC `Time`. Raises `AmbiguousLocalTime` on a DST
#     spring-forward gap; returns the first occurrence (pre-fallback)
#     with a `warning` flag on a DST fall-back repeat per the locked
#     decision.
#
#   - `render_publish_at_for_user(publish_at_utc, user_tz, format:)`
#     reverses the trip: stored-UTC instant + user-tz returns the
#     user-local string the picker pre-fills with.
#
#   - `reminder_window(publish_at_utc, user_tz, offset:)` computes the
#     UTC instant for an offset reminder (e.g., `offset: -1.hour`).
#     Used by a future reminder cron; defined here so the math lives
#     next to the parse / render pair.
#
# The helper is pure: it does not read `Current.user` or `Time.zone`.
# Callers pass the explicit zone (`Current.user.time_zone` from a
# controller, or a frozen UTC zone for tests) so the conversion is
# auditable end to end.
module ScheduledPublishHelper
  # Raised when the supplied date + time string falls inside a DST
  # spring-forward gap (the local clock skips an hour, so the
  # requested instant simply does not exist in the user's zone).
  class AmbiguousLocalTime < StandardError; end

  # The result of `parse_user_local_to_utc`. Carries the UTC instant
  # plus a `warning` flag set on a DST fall-back repeat (the user
  # picked the ambiguous hour; we resolved to the first occurrence
  # but want the caller to surface a notice).
  ParsedPublishAt = Struct.new(:utc, :warning, keyword_init: true) do
    def to_time
      utc
    end
  end

  # Parse a user-local date + time pair in the user's zone and return
  # a UTC `Time`. Accepts either a combined ISO 8601 local string
  # (`"2026-06-01T09:00"`) or a separate `date_str` / `time_str` pair.
  #
  #   parse_user_local_to_utc("2026-06-01", "09:00", "Europe/Bucharest")
  #   # => ParsedPublishAt(utc: 2026-06-01 07:00:00 UTC, warning: nil)
  #
  # Raises `AmbiguousLocalTime` on spring-forward gaps. Returns the
  # FIRST occurrence (pre-fallback) on fall-back repeats with
  # `warning: :dst_fallback_first_occurrence`.
  #
  # Returns nil when either input is blank.
  def parse_user_local_to_utc(date_str, time_str = nil, user_tz = nil)
    user_tz ||= "Etc/UTC"

    return nil if date_str.blank?

    # Allow the combined form (date_str carries the full datetime).
    combined =
      if time_str.blank?
        date_str.to_s
      else
        "#{date_str}T#{time_str}"
      end
    return nil if combined.blank?

    zone = ActiveSupport::TimeZone[user_tz.to_s]
    raise AmbiguousLocalTime, "unknown time zone: #{user_tz}" if zone.nil?

    # Pre-parse the components so we can detect spring-forward gaps.
    # `Time.parse` on a tzless string treats it as the *local* time
    # in `Time.zone`, which is exactly what we want once `zone.local`
    # runs — but the gap check needs the components in hand.
    year, month, day, hour, min, sec = parse_components(combined)
    raise AmbiguousLocalTime, "could not parse date+time: #{combined.inspect}" if year.nil?

    local = zone.local(year, month, day, hour, min, sec)

    # Spring-forward gap detection. When `zone.local(...)` lands on a
    # nonexistent local clock-time, TZInfo silently shifts it forward
    # by an hour. Round-trip: if the rendered local clock back from
    # `local` does not match the requested input, the requested input
    # was inside the gap.
    rendered = local.strftime("%Y-%m-%dT%H:%M:%S")
    requested = format("%04d-%02d-%02dT%02d:%02d:%02d",
                       year, month, day, hour, min, sec)
    if rendered != requested
      raise AmbiguousLocalTime,
            "That time does not exist due to DST spring-forward."
    end

    warning = detect_fallback_warning(zone, year, month, day, hour, min, sec)

    ParsedPublishAt.new(utc: local.utc, warning: warning)
  end

  # Reverse: convert a stored-UTC instant back to a user-local string
  # for re-render in the picker. Defaults to `%Y-%m-%dT%H:%M` (the
  # value shape `<input type="datetime-local">` expects).
  #
  #   render_publish_at_for_user(Time.utc(2026, 6, 1, 7, 0), "Europe/Bucharest")
  #   # => "2026-06-01T09:00"
  def render_publish_at_for_user(publish_at_utc, user_tz, format: :input)
    return nil if publish_at_utc.nil?

    user_tz ||= "Etc/UTC"
    zone = ActiveSupport::TimeZone[user_tz.to_s] || ActiveSupport::TimeZone["Etc/UTC"]

    local = publish_at_utc.in_time_zone(zone)

    case format
    when :input
      local.strftime("%Y-%m-%dT%H:%M")
    when :long
      local.strftime("%b %-d, %Y %H:%M %Z")
    when :short
      local.strftime("%H:%M %Z")
    when :date
      local.strftime("%b %-d, %Y")
    when :iso
      local.iso8601
    else
      local.strftime("%Y-%m-%dT%H:%M")
    end
  end

  # Given a UTC publish instant and an offset duration (e.g.,
  # `-1.hour`, `-30.minutes`), return the UTC instant a reminder
  # should fire at. The user_tz argument is accepted for symmetry
  # with the picker contract (and for future reminder bodies rendered
  # in user-tz), but the math itself is offset-based — the reminder
  # window is the same UTC instant regardless of the user's zone.
  #
  #   reminder_window(Time.utc(2026, 6, 1, 7, 0), "Europe/Bucharest", offset: -1.hour)
  #   # => 2026-06-01 06:00:00 UTC
  def reminder_window(publish_at_utc, _user_tz, offset:)
    return nil if publish_at_utc.nil? || offset.nil?
    (publish_at_utc + offset).utc
  end

  private

  # `Time.parse` accepts the combined form (`"2026-06-01T09:00"`,
  # `"2026-06-01 09:00"`, `"2026-06-01 09:00:00"`). Return the
  # broken-out integer components, or nil on parse failure.
  def parse_components(combined)
    str = combined.to_s.strip
    m = str.match(/\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?\z/)
    return nil unless m
    [
      m[1].to_i,
      m[2].to_i,
      m[3].to_i,
      m[4].to_i,
      m[5].to_i,
      (m[6] || "0").to_i
    ]
  end

  # On a DST fall-back repeat, the local clock 01:00–02:00 occurs
  # twice. `zone.local` resolves to the FIRST occurrence
  # (pre-fallback, in DST). Detect the repeat by checking whether
  # `local.utc + 1.hour` renders to the *same* wall-clock in the
  # user's zone — if so, the wall-clock is ambiguous and we picked
  # the first occurrence.
  def detect_fallback_warning(zone, year, month, day, hour, min, sec)
    local = zone.local(year, month, day, hour, min, sec)
    later_utc = local.utc + 1.hour
    later_local = later_utc.in_time_zone(zone)

    if later_local.year == local.year &&
       later_local.month == local.month &&
       later_local.day == local.day &&
       later_local.hour == local.hour &&
       later_local.min == local.min
      :dst_fallback_first_occurrence
    end
  end
end
