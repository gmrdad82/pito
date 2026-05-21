module Pito
  # Pito::TimeZonePanelComponent
  #
  # The time-zone panel on /settings. Renders a single dropdown over every
  # ActiveSupport::TimeZone entry (common optgroup) plus the full IANA tzinfo
  # set (all-IANA optgroup). Submits PATCH /settings/time_zone.
  # Extracted from `app/views/settings/_time_zone_pane.html.erb`.
  #
  # ## Kwargs
  #
  # (none — all data is resolved from Current.user at render time)
  #
  # ## Cable channel
  #
  # `pito:home:time_zone` — reserved for future broadcasts (e.g. after
  # a Rake task or job updates the stored zone server-side).
  #
  # ## Focusables
  #
  # ordered list:
  # - `time_zone_select` (style: :input) — the timezone <select> dropdown
  #
  class TimeZonePanelComponent < ViewComponent::Base
    CABLE_CHANNEL = "pito:home:time_zone".freeze

    def initialize
    end

    def focusables
      [ { key: "time_zone_select", style: :input } ]
    end

    def current_iana
      @current_iana ||= begin
        zone = Current.user&.time_zone.presence || "Etc/UTC"
        ActiveSupport::TimeZone[zone]&.tzinfo&.name || zone
      end
    end

    def friendly_iana_names
      @friendly_iana_names ||= ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }.to_set
    end
  end
end
