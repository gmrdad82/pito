# Phase 25 — 01c. In-app template for `login_pending_approval`.
#
# Renders the urgent "someone is trying to log in from a new
# location" notification. The user reads this from their trusted
# browser; two bracketed-link actions (`[yeah, it's me]` /
# `[block the intruder]`) sit on the notification card and the
# notification detail page.
#
# Required `event_payload` keys (written by
# `NotificationSource::LoginPendingApproval#report!`):
#
#   - `login_attempt_id` — the pending attempt row (FK target).
#   - `session_id`       — the pending session row id.
#   - `email`            — the email the requester used.
#   - `browser`, `os`    — the requester's normalized UA.
#   - `ip`               — the requester's IP (presentation form).
#   - `ip_prefix`        — the requester's /24 or /64.
#   - `fingerprint_short`— first 12 hex of the fingerprint hash.
#   - `geo_summary`      — "city, country (region)" or nil.
#
# All keys are graceful about missing data — the template renders
# `(unavailable)` placeholders rather than crashing.
module NotificationFormatter
  module Templates
    class LoginPendingApproval < Base
      def title
        "new-location login: #{fetch(:email, placeholder('email'))}"
      end

      def body
        browser = fetch(:browser, "unknown browser")
        os = fetch(:os, "unknown OS")
        ip = fetch(:ip, placeholder("ip"))
        location = fetch(:geo_summary).presence || "location unknown"
        fp = fetch(:fingerprint_short, placeholder("fingerprint"))

        approve_url = approve_path
        block_url   = block_path

        lines = []
        lines << "someone with the correct password is trying to sign in from a new location."
        lines << "browser: #{browser} on #{os}."
        lines << "location: #{location}."
        lines << "ip: #{ip}."
        lines << "fingerprint: #{fp}."
        lines << ""

        if approve_url && block_url
          lines << "[yeah, it's me](#{approve_url}) or [block the intruder](#{block_url})."
        end

        lines.join("\n")
      end

      def url
        # The notification detail page (`/notifications/:id`) renders
        # the same two actions, so the `url` slot points there. Browser
        # / TUI / MCP all resolve this consistently.
        return nil if notification.id.blank?

        "/notifications/#{notification.id}"
      end

      private

      def approve_path
        id = fetch(:login_attempt_id)
        return nil if id.blank?

        "/login/approvals/#{id.to_i}"
      end

      def block_path
        id = fetch(:login_attempt_id)
        return nil if id.blank?

        "/login/blocks/#{id.to_i}"
      end
    end
  end
end
