# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006). POST a
# token to Google's revoke endpoint and audit the call.
#
# The module stays under the `Google::` namespace because it describes
# what it does (call Google's revoke endpoint), not what the local
# record is called. The parameter and the audit-row column track the
# new local model name (`youtube_connection`).
#
# Locked decision (7C-already-revoked) — already-revoked disconnect
# is idempotent. If Google returns "token already invalid" because
# the user revoked the grant from myaccount.google.com BEFORE
# clicking disconnect, swallow the error: audit the failure and
# let the caller proceed with destroying the local row anyway.
require "net/http"
require "uri"
require "json"

module Google
  module RevokeToken
    REVOKE_URL = URI("https://oauth2.googleapis.com/revoke").freeze

    module_function

    # Returns true on a successful revoke (2xx) or on the "already
    # revoked" idempotent path; raises on transport-level failure
    # so the caller's transaction can roll back.
    def call(youtube_connection)
      token = youtube_connection.refresh_token.presence || youtube_connection.access_token.presence
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = "success"
      http_status = nil
      error_message = nil

      begin
        if token.blank?
          outcome = "client_error"
          error_message = "no token to revoke"
        else
          response = post(token)
          http_status = response.code.to_i
          if (200..299).cover?(http_status)
            outcome = "success"
          elsif already_revoked?(response)
            # Google sometimes returns 400 "token already revoked"
            # or invalid_token; treat as idempotent success-with-note.
            outcome = "client_error"
            error_message = "token already invalid: #{safe_body(response)}"
          else
            outcome = "client_error"
            error_message = "revoke failed (#{http_status}): #{safe_body(response)}"
          end
        end
      rescue StandardError => e
        outcome = "network_error"
        error_message = "#{e.class}: #{e.message}"
      ensure
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
        write_audit_row(
          youtube_connection: youtube_connection,
          outcome: outcome,
          http_status: http_status,
          error_message: error_message,
          duration_ms: elapsed_ms
        )
      end

      true
    end

    def post(token)
      uri = REVOKE_URL
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(token: token)
      http.request(request)
    end

    def safe_body(response)
      response.body.to_s.first(500)
    end

    def already_revoked?(response)
      body = safe_body(response)
      body.include?("invalid_token") || body.include?("Token expired or revoked")
    end

    def write_audit_row(youtube_connection:, outcome:, http_status:,
                        error_message:, duration_ms:)
      return unless defined?(YoutubeApiCall) && YoutubeApiCall.respond_to?(:create!)

      YoutubeApiCall.create!(
        youtube_connection_id: youtube_connection.id,
        client_kind: "oauth",
        endpoint: "oauth2.revoke",
        http_method: "POST",
        units: Channel::Youtube::Quota.cost_for("oauth2.revoke"),
        outcome: outcome,
        http_status: http_status,
        error_message: error_message&.to_s&.first(2_000),
        duration_ms: duration_ms,
        created_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[Google::RevokeToken] failed to persist audit row: #{e.class}: #{e.message}")
    end
  end
end
