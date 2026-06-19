# Surfaced by Channel::Youtube::VideosClient / Channel::Youtube::VideosReader
# on a 5xx response. Distinct from the lower-level
# `Channel::Youtube::TransientError` so the sync-back job can rescue it
# explicitly. The job re-raises so Sidekiq retries with backoff.
class Channel
  module Youtube
    class ServerError < TransientError; end
  end
end
