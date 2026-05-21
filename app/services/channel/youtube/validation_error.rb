# Phase 12 — surfaced by Channel::Youtube::VideosClient on a 4xx response that
# the user can fix by editing the local row (e.g., title too long for
# the API even though pito's local validation didn't catch a UTF-8
# byte-counting edge case). Non-retriable: the sync-back job records
# the error and does NOT re-raise (Sidekiq won't retry).
class Channel
  module Youtube
    class ValidationError < Error; end
  end
end
