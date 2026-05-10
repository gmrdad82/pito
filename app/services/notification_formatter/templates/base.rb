# Phase 16 §2 — Notification formatter.
#
# Per-event-type template base. Subclasses implement `#title`, `#body`,
# and `#url`, each of which reads ONLY from `notification.event_payload`
# (verified by the test sweep — see Spec 02 acceptance "reads ONLY from
# notification.event_payload"). The constructor stashes the row so the
# subclasses can also read top-level columns when the spec calls for
# them (e.g., `id`, `event_type`, `severity`, `fires_at`, `kind`).
#
# Templates are graceful about missing keys: `event_payload` may have
# been written by a stale `NotificationPayloadBuilder` shape, by a
# malformed source helper, or by hand-inserted DB rows. The formatter
# never crashes on a malformed row — the visible degradation
# ("data unavailable" / blank fields) is acceptable since the row is
# already in the DB.
module NotificationFormatter
  module Templates
    class Base
      attr_reader :notification

      def initialize(notification)
        @notification = notification
      end

      def title
        raise NotImplementedError
      end

      def body
        raise NotImplementedError
      end

      def url
        raise NotImplementedError
      end

      private

      # Convenience accessor for the JSONB payload. ActiveRecord returns
      # a HashWithIndifferentAccess for jsonb columns when the column
      # is configured normally; here we coerce to ensure both string +
      # symbol key reads work. `nil` payload (validation hole) becomes
      # an empty hash rather than crashing.
      def payload
        @payload ||= (notification.event_payload || {}).with_indifferent_access
      end

      def fetch(key, fallback = nil)
        v = payload[key]
        v.nil? ? fallback : v
      end

      # Many templates need a "data unavailable" placeholder for missing
      # required keys. Centralized so the message is consistent.
      def placeholder(field)
        "(#{field} unavailable)"
      end

      # Helper for joining arrays into a comma-separated string with
      # graceful fallback when the array is nil / empty.
      def join_list(items, fallback: "")
        return fallback if items.nil?

        list = Array(items).compact.reject { |s| s.to_s.strip.empty? }
        return fallback if list.empty?

        list.join(", ")
      end
    end
  end
end
