# Phase 12 — surfaced by Youtube::VideosReader on a 404 response.
# The video has been deleted from YouTube (likely in Studio). The
# sync-back job records the error and stops; re-trying won't bring
# the video back.
module Youtube
  class NotFoundError < Error; end
end
