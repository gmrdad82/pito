# Phase 12 — surfaced by Youtube::VideosClient / Youtube::VideosReader
# on a 5xx response. Distinct from the lower-level
# `Youtube::TransientError` so the sync-back job can rescue it
# explicitly. The job re-raises so Sidekiq retries with backoff.
module Youtube
  class ServerError < TransientError; end
end
