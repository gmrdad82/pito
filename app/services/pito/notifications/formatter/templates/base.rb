# Notification formatter.
#
# Per-event-type template base. Subclasses implement `#title`, `#body`,
# and `#url`, each of which reads ONLY from `notification.event_payload`
# (verified by the test sweep — see Spec 02 acceptance "reads ONLY from
# notification.event_payload"). The constructor stashes the row so the
# subclasses can also read top-level columns when the spec calls for
# them (e.g., `id`, `event_type`, `severity`, `fires_at`, `kind`).
#
# ── SUBCLASS CONTRACT ────────────────────────────────────────────────
#
# Every concrete template MUST implement exactly three methods:
#
#   title(→ String)
#     Short one-liner shown as the notification headline. Must degrade
#     gracefully when required payload keys are absent (use `fetch` /
#     `placeholder` rather than bare hash access).
#
#   body(→ String)
#     Longer human-readable detail line. May include `[text](url)`
#     markdown — the channel formatters rewrite these for their target
#     (Discord embed, Slack mrkdwn, in-app `<a>`). Must also degrade
#     gracefully on missing keys.
#
#   url(→ String | nil)
#     The "view in pito" destination — an absolute URL or a leading-
#     slash app path. Return `nil` when there is no meaningful target;
#     channel formatters skip the link block in that case.
#
# DATA CONTRACT — event_payload is the ONLY data source:
#   All three methods MUST source their content exclusively from
#   `notification.event_payload` (accessed via the private `fetch`
#   helper) or from non-content top-level columns (`id`,
#   `source_calendar_entry_id`, `event_type`, `severity`, `fires_at`,
#   `kind`). They MUST NOT call external services, read ENV vars, or
#   touch any other association — the formatter is pure (input:
#   Notification row; output: payload), idempotent, and
#   round-trip-safe across source-row edits.
#
# Templates are graceful about missing keys: `event_payload` may have
# been written by a stale `Pito::Notifications::PayloadBuilder` shape,
# by a malformed source helper, or by hand-inserted DB rows. The
# formatter never crashes on a malformed row — the visible degradation
# ("data unavailable" / blank fields) is acceptable since the row is
# already in the DB.
module Pito
  module Notifications
    module Formatter
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
  end
end
