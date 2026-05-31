# Phase 7 — Step B (7b-youtube-client-and-audit.md). Token refresh
# helper extracted from `Channel::Youtube::Client` so it is easy to spec in
# isolation.
#
# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006). The
# parameter name follows the new local model; the upstream call to
# Google's token endpoint is unchanged.
#
# POSTs to `https://oauth2.googleapis.com/token` with
# `grant_type=refresh_token`. On 200, updates `access_token`,
# `expires_at`, `last_refreshed_at` on the connection. On 400 with
# `error: "invalid_grant"`, sets `needs_reauth: true` and raises
# `Channel::Youtube::NeedsReauthError`. Other failures raise
# `Channel::Youtube::TransientError` so the caller's retry path may re-try.
require "net/http"
require "uri"
require "json"

class Channel
  module Youtube
    module TokenRefresher
      REFRESH_URL = URI("https://oauth2.googleapis.com/token").freeze

      module_function

      def call(youtube_connection)
        raise Channel::Youtube::NeedsReauthError, "no refresh token on file" if youtube_connection.refresh_token.blank?

        # Google OAuth credentials are sourced from ENV vars
        # (PITO_GOOGLE_OAUTH_CLIENT_ID / PITO_GOOGLE_OAUTH_CLIENT_SECRET).
        response = post_form(
          client_id:     ENV["PITO_GOOGLE_OAUTH_CLIENT_ID"],
          client_secret: ENV["PITO_GOOGLE_OAUTH_CLIENT_SECRET"],
          refresh_token: youtube_connection.refresh_token,
          grant_type:    "refresh_token"
        )

        body = parse_body(response)

        case response.code.to_i
        when 200
          apply_success!(youtube_connection, body)
          youtube_connection
        when 400
          if body["error"].to_s == "invalid_grant"
            youtube_connection.update_columns(needs_reauth: true)
            raise Channel::Youtube::NeedsReauthError, "invalid_grant — refresh token revoked"
          end

          raise Channel::Youtube::TransientError, "refresh failed (#{response.code}): #{body['error']}"
        when 500..599
          raise Channel::Youtube::TransientError, "refresh failed (#{response.code})"
        else
          raise Channel::Youtube::TransientError, "refresh failed (#{response.code})"
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

      def apply_success!(youtube_connection, body)
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
        youtube_connection.update!(attrs)
      end
    end
  end
end
