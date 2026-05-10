# Phase 13.2 — Analytics sync engine. Shared OAuth-refresh plumbing
# extracted from `Youtube::Client` so both the Data API v3 client and
# the new `Youtube::AnalyticsClient` use the same token-freshness path.
# Per the master-agent decision (open question 7), the extraction lives
# in a module that both clients include.
#
# `ensure_token_fresh!` consults `YoutubeConnection#access_token_expired?`
# and delegates to `Youtube::TokenRefresher.call` when the access token is
# within the skew window. The refresher itself owns the HTTP POST to
# `https://oauth2.googleapis.com/token` and the `needs_reauth` flip on
# `invalid_grant`.
module Youtube
  module OauthRefresh
    private

    def ensure_token_fresh!(connection)
      return unless connection.access_token_expired?

      Youtube::TokenRefresher.call(connection)
    end

    # Build a Google authorization adapter that always returns the
    # connection's current `access_token` value (so a refresh applied
    # mid-call is visible on the next attempt).
    def build_oauth_credentials(connection)
      bound_connection = connection
      Class.new do
        define_method(:apply!) do |headers|
          headers["Authorization"] = "Bearer #{bound_connection.access_token}"
        end
        define_method(:apply) do |headers|
          h = headers.dup
          apply!(h)
          h
        end
      end.new
    end
  end
end
