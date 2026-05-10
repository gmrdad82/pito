# Phase 16 §2 — Notification formatter.
#
# Template for the `calendar_entry_firing` notification kind.
#
# Required `event_payload` keys: `entry_id`, `entry_type`, `title` (the
# calendar entry's own title), `description`, `starts_at` (iso8601).
module NotificationFormatter
  module Templates
    class CalendarEntryFiring < Base
      EMPTY_BODY_FALLBACK = "calendar entry fired."

      def title
        fetch(:title, placeholder("calendar entry title"))
      end

      def body
        description = fetch(:description)
        return EMPTY_BODY_FALLBACK if description.blank?

        description.to_s
      end

      def url
        entry_id = fetch(:entry_id) || notification.source_calendar_entry_id
        return nil if entry_id.blank?

        "/calendar/entries/#{entry_id}"
      end
    end
  end
end
