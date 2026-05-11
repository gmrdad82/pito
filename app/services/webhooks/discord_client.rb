# Phase 26 — 01c. Discord webhook HTTP client.
#
# Mirror of `Webhooks::SlackClient` — same `Result` struct, same
# `#ping` / `#deliver` shape, same timeout posture. Two public methods:
#
#   * `#ping(text)` — sends a tiny `{ "content": text }` payload as a
#     test ping during Settings-pane save. Discord webhook endpoints
#     require an inline `content` field (Slack accepts `{ "text" }`);
#     the only meaningful difference between this client and the Slack
#     one is the payload key. Returns a `Result` so the caller can
#     branch on `result.success?` / `result.error`.
#   * `#deliver(payload)` — POSTs an already-built payload (Discord
#     embed blob from `NotificationFormatter::Discord.payload_for(...)`).
#     Used by the Phase 26 01e digest scheduler. Same `Result` shape.
#
# Network failure handling lives here (timeouts, DNS failures,
# malformed URIs) — every failure routes through the `Result` so the
# caller never needs `rescue` boilerplate around it. Retries DO NOT
# live here — `#deliver` is used by the delivery job which owns the
# Sidekiq retry policy.
#
# Timeouts mirror the PORO dispatcher in
# `NotificationDeliveryChannel::Base#configure_http` (open/ssl: 5s,
# read/write: 10s).
require "net/http"
require "uri"

module Webhooks
  class DiscordClient
    # `success` — true iff the response carried a 2xx status code.
    # `status` — integer HTTP status (nil on network failure).
    # `body`   — response body (best effort; truncated to keep logs tidy).
    # `error`  — human-readable reason (nil on success).
    Result = Struct.new(:success, :status, :body, :error, keyword_init: true) do
      def success?
        !!success
      end
    end

    OPEN_TIMEOUT  = 5
    READ_TIMEOUT  = 10
    WRITE_TIMEOUT = 10
    SSL_TIMEOUT   = 5

    def initialize(webhook_url)
      @webhook_url = webhook_url.to_s
    end

    # Sends a fixed text-only payload (Discord requires the `content`
    # field key — not `text`). Used by the Settings pane test ping.
    # Returns a `Result`.
    def ping(message_text)
      post({ "content" => message_text.to_s })
    end

    # Sends an already-built payload (Discord embeds blob).
    # Used by the digest scheduler (Phase 26 01e). Returns a `Result`.
    def deliver(payload)
      post(payload)
    end

    private

    def post(payload)
      uri = parse_uri
      return Result.new(success: false, error: "invalid webhook URL") unless uri

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout  = OPEN_TIMEOUT
      http.read_timeout  = READ_TIMEOUT
      http.write_timeout = WRITE_TIMEOUT
      http.ssl_timeout   = SSL_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri,
                                    "Content-Type" => "application/json")
      request.body = payload.to_json

      response = http.request(request)
      code = response.code.to_i
      body = response.body.to_s

      if code.between?(200, 299)
        Result.new(success: true, status: code, body: body)
      else
        Result.new(
          success: false,
          status: code,
          body: body,
          error: "HTTP #{code}#{body.empty? ? '' : ": #{body.first(200)}"}"
        )
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
      Result.new(success: false, error: "timeout: #{e.message}")
    rescue SocketError => e
      Result.new(success: false, error: "DNS failure: #{e.message}")
    rescue OpenSSL::SSL::SSLError => e
      Result.new(success: false, error: "TLS failure: #{e.message}")
    rescue StandardError => e
      Result.new(success: false, error: "network error: #{e.message}")
    end

    def parse_uri
      uri = URI.parse(@webhook_url)
      return nil unless uri.is_a?(URI::HTTPS)
      return nil if uri.host.blank?
      uri
    rescue URI::InvalidURIError
      nil
    end
  end
end
