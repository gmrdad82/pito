# Shared OAuth-refresh plumbing for `Channel::Youtube::Client` and related
# OAuth-backed clients. Provides the same token-freshness path across callers.
#
# `ensure_token_fresh!` consults `YoutubeConnection#access_token_expired?`
# and delegates to `Channel::Youtube::TokenRefresher.call` when the access token is
# within the skew window. The refresher itself owns the HTTP POST to
# `https://oauth2.googleapis.com/token` and the `needs_reauth` flip on
# `invalid_grant`.
#
# The old `build_oauth_credentials` helper was removed from this module.
# `Channel::Youtube::ServiceFactory` is the single source for OAuth-authorized
# service construction (see `ServiceFactory.data_service`), and every
# OAuth-backed client routes through it. The factory owns its own copy of the
# authorization-adapter helper so callers never bypass the HTTP timeouts.
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
