# Phase 25 — 01c. Source helper for the pending-approval notification.
#
# Called by `Auth::SessionPendingApprover` (01b) immediately after a
# pending Session row + a `LoginAttempt` row with
# `reason: :new_location_pending` land. One notification per pending
# attempt — dedupe is anchored on the attempt id so retries collapse.
#
# Severity is `:urgent` per LD-7. The user sees this on the in-app
# banner / inbox, on the TUI notifications surface, and on the MCP
# `notifications_list` tool output. Two bracketed-link actions in the
# notification body (`[yeah, it's me]` / `[block the intruder]`) link
# to `/login/approvals/:id` and `/login/blocks/:id` respectively.
#
# When the notification lands, the helper also stamps the
# `login_attempts.notification_id` FK on the source attempt row so
# `Auth::LoginAttemptApprover` / `Auth::LoginAttemptBlocker` can
# resolve the linked notification without an extra lookup.
module NotificationSource
  module LoginPendingApproval
    EVENT_TYPE = "login_pending_approval"

    module_function

    # @param attempt [LoginAttempt] the pending attempt row.
    # @return [Notification]
    def report!(attempt:)
      raise ArgumentError, "attempt required" if attempt.nil?
      raise ArgumentError, "attempt must persist" if attempt.id.blank?

      payload = build_payload(attempt)
      dedup_key = dedup_key_for(attempt)

      notification = Notification.find_or_create_by!(
        event_type: EVENT_TYPE,
        dedup_key: dedup_key
      ) do |n|
        n.kind = :login_pending_approval
        n.severity = :urgent
        n.title = payload[:title]
        n.body = payload[:body]
        n.url = payload[:url]
        n.event_payload = payload[:event_payload]
        n.fires_at = Time.current
      end

      # Stamp the FK on the attempt row. `update_columns` skips
      # validations + callbacks so we don't accidentally re-stamp
      # `resolved_at` on the pending row (the model's
      # `stamp_resolved_at_on_resolution` hook would otherwise fire on
      # a plain `update!` even though the result didn't change).
      if attempt.notification_id != notification.id
        attempt.update_columns(notification_id: notification.id)
      end

      notification
    end

    def dedup_key_for(attempt)
      "login-pending-#{attempt.id}"
    end

    def build_payload(attempt)
      email   = attempt.email_attempted.presence ||
                attempt.user&.email.to_s
      browser = attempt.browser.presence
      os      = attempt.os.presence
      ip      = attempt.ip.to_s

      event_payload = {
        "login_attempt_id"  => attempt.id,
        "session_id"        => attempt.session_id,
        "user_id"           => attempt.user_id,
        "email"             => email,
        "browser"           => browser,
        "os"                => os,
        "ip"                => ip,
        "ip_prefix"         => attempt.ip_prefix.to_s,
        "fingerprint_short" => attempt.fingerprint_short,
        "geo_summary"       => attempt.geo_summary
      }

      NotificationPayloadBuilder.build(
        event_type: EVENT_TYPE,
        overrides: {
          title: "new-location login: #{email.presence || 'unknown account'}",
          body: nil,
          url: nil,
          event_payload: event_payload
        }
      )
    end
  end
end
