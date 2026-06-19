# Raised when a 401 persists after one refresh
# attempt OR the refresh itself yields `invalid_grant`. The client
# (or `TokenRefresher`) flips `needs_reauth: true` on the identity
# before raising.
class Channel
  module Youtube
    class NeedsReauthError < Error; end
  end
end
