# Phase 7 — Step B (7b-youtube-client-and-audit.md). Token refresh
# helper extracted from `Youtube::Client` so it is easy to spec in
# isolation.
#
# POSTs to `https://oauth2.googleapis.com/token` with
# `grant_type=refresh_token`. On 200, updates `access_token`,
# `expires_at`, `last_refreshed_at` on the identity. On 400 with
# `error: "invalid_grant"`, sets `needs_reauth: true` and raises
# `Youtube::NeedsReauthError`. Other failures raise
# `Youtube::TransientError` so the caller's retry path may re-try.
require "net/http"
require "uri"
require "json"

module Youtube
  module TokenRefresher
    REFRESH_URL = URI("https://oauth2.googleapis.com/token").freeze

    module_function

    def call(google_identity)
      raise Youtube::NeedsReauthError, "no refresh token on file" if google_identity.refresh_token.blank?

      response = post_form(
        client_id:     Rails.application.credentials.dig(:google_oauth, :client_id),
        client_secret: Rails.application.credentials.dig(:google_oauth, :client_secret),
        refresh_token: google_identity.refresh_token,
        grant_type:    "refresh_token"
      )

      body = parse_body(response)

      case response.code.to_i
      when 200
        apply_success!(google_identity, body)
        google_identity
      when 400
        if body["error"].to_s == "invalid_grant"
          google_identity.update_columns(needs_reauth: true)
          raise Youtube::NeedsReauthError, "invalid_grant — refresh token revoked"
        end

        raise Youtube::TransientError, "refresh failed (#{response.code}): #{body['error']}"
      when 500..599
        raise Youtube::TransientError, "refresh failed (#{response.code})"
      else
        raise Youtube::TransientError, "refresh failed (#{response.code})"
      end
    end

    def post_form(form_attrs)
      uri = REFRESH_URL
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(form_attrs)
      http.request(request)
    end

    def parse_body(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def apply_success!(google_identity, body)
      attrs = {
        access_token: body["access_token"],
        last_refreshed_at: Time.current
      }
      if body["expires_in"].present?
        attrs[:expires_at] = body["expires_in"].to_i.seconds.from_now
      end
      # Google sometimes returns a fresh refresh_token; if so, take
      # it. (We force prompt: "consent" on every authorization
      # request, but Google still occasionally rotates on refresh.)
      attrs[:refresh_token] = body["refresh_token"] if body["refresh_token"].present?
      google_identity.update!(attrs)
    end
  end
end
