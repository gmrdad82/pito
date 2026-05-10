# Phase 12 — surfaced by Youtube::VideosClient / Youtube::VideosReader
# on a 401 response from the API. Distinct from
# `Youtube::NeedsReauthError` (which is the OAuth-side surface raised
# by the token refresher) — this name keeps the sync-back job's
# rescue blocks readable and matches the spec's failure-mode taxonomy.
module Youtube
  class AuthRevokedError < Error; end
end
