# Phase 12 — surfaced by Channel::Youtube::VideosReader on a 404 response.
# The video has been deleted from YouTube (likely in Studio). The
# sync-back job records the error and stops; re-trying won't bring
# the video back.
class Channel
  module Youtube
    class NotFoundError < Error; end
  end
end
