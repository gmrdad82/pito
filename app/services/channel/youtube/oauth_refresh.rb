# Phase 13.2 — Analytics sync engine. Shared OAuth-refresh plumbing
# extracted from `Channel::Youtube::Client` so both the Data API v3 client and
# the new `Channel::Youtube::AnalyticsClient` use the same token-freshness path.
# Per the master-agent decision (open question 7), the extraction lives
# in a module that both clients include.
#
# `ensure_token_fresh!` consults `YoutubeConnection#access_token_expired?`
# and delegates to `Channel::Youtube::TokenRefresher.call` when the access token is
# within the skew window. The refresher itself owns the HTTP POST to
# `https://oauth2.googleapis.com/token` and the `needs_reauth` flip on
# `invalid_grant`.
#
# Phase 13 security fix-forward (F1) — the old `build_oauth_credentials`
# helper was removed from this module. `Channel::Youtube::ServiceFactory` is the
# single source for OAuth-authorized service construction (see
# `ServiceFactory.data_service` / `ServiceFactory.analytics_service`),
# and every OAuth-backed client routes through it. The factory owns its
# own copy of the authorization-adapter helper so callers never bypass
# the Phase 15 HTTP timeouts.
class Channel
  module Youtube
    module OauthRefresh
      private

      def ensure_token_fresh!(connection)
        return unless connection.access_token_expired?

        Channel::Youtube::TokenRefresher.call(connection)
      end
    end
  end
end
