# Phase 26 — 01a. Timezone foundation.
#
# Mixed into `User`. Validates `time_zone` is a recognized zone — the
# canonical IANA set (`ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }`)
# plus the Rails-friendly alias values (`ActiveSupport::TimeZone::MAPPING.values`,
# the IANA-named subset Rails exposes through the `[name]` lookup) — and
# exposes `#tz` returning the resolved `ActiveSupport::TimeZone` instance.
#
# The default `"Etc/UTC"` (set at the column level) doubles as the
# "never set" sentinel the first-load JS detector checks before
# overwriting with the browser zone.
module Timezoned
  extend ActiveSupport::Concern

  # Build the allow-list at boot. We accept three name shapes:
  #
  #   1. The full IANA `tzinfo` set (`TZInfo::Timezone.all_identifiers`)
  #      — covers edge zones the Rails-curated `ActiveSupport::TimeZone.all`
  #      list does NOT include (e.g. `Pacific/Kiritimati`,
  #      `Pacific/Pago_Pago`, `Asia/Kolkata`). These are the canonical
  #      names browsers return via `Intl.DateTimeFormat()...timeZone`.
  #   2. The Rails-friendly aliases (`ActiveSupport::TimeZone::MAPPING.keys`
  #      — `"Eastern Time (US & Canada)"`, `"UTC"`, etc.). These are
  #      the dropdown labels the Settings pane stores when the user
  #      picks from `ActiveSupport::TimeZone.all`.
  #   3. The MAPPING values — the IANA names Rails curates as the
  #      "friendly" zone subset. Belt-and-braces; mostly a no-op
  #      because (1) already covers these.
  #
  # The union is frozen so the membership check is a constant-time
  # `Set#include?` rather than an allocating array scan per save.
  ALLOWED_TIME_ZONES = (
    TZInfo::Timezone.all_identifiers +
      ActiveSupport::TimeZone::MAPPING.values +
      ActiveSupport::TimeZone::MAPPING.keys
  ).uniq.to_set.freeze

  included do
    validates :time_zone,
              presence: true,
              inclusion: {
                in: ALLOWED_TIME_ZONES,
                message: "is not a recognized IANA time zone"
              }
  end

  # Resolved `ActiveSupport::TimeZone` instance for the stored name.
  # `ActiveSupport::TimeZone[]` accepts both Rails-friendly aliases
  # (`"Eastern Time (US & Canada)"`) and IANA names (`"America/New_York"`)
  # and resolves them through the same MAPPING table. Falls back to
  # `Etc/UTC` if the lookup ever returns nil (defensive — the
  # validation already gates the stored value).
  def tz
    ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["Etc/UTC"]
  end
end
