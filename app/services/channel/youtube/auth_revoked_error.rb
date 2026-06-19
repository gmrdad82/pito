# Surfaced by Channel::Youtube::VideosClient / Channel::Youtube::VideosReader
# on a 401 response from the API. Distinct from
# `Channel::Youtube::NeedsReauthError` (which is the OAuth-side surface raised
# by the token refresher) — this name keeps the sync-back job's
# rescue blocks readable and matches the spec's failure-mode taxonomy.
class Channel
  module Youtube
    class AuthRevokedError < Error; end
  end
end
