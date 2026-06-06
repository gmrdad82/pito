# frozen_string_literal: true

# Lightweight struct that duck-types a Notification row for template/formatter
# tests. The real Notification table only carries `message` + `read_at`; the
# richer columns (event_payload, id, source_calendar_entry_id, etc.) live in
# the aspirational Phase-26 schema. All template logic is pure Ruby, so a
# struct is sufficient.
unless defined?(NotificationDouble)
  NotificationDouble = Struct.new(
    :event_payload, :id, :source_calendar_entry_id,
    :severity, :event_type, :fires_at, :read_at,
    keyword_init: true
  ) do
    def read?
      read_at.present?
    end
  end
end
