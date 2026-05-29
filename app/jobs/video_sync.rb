# Phase 23 §23c — Video sync entry point.
#
# `BulkSyncJob` dispatches `<TargetType>Sync.perform_async(id)` per
# `bulk_operation_item`. For `target_type: "Video"`, that resolves to
# `VideoSync` (this class).
#
# Phase 23 reframes "sync a video" as "check the video against
# YouTube and surface any divergence as a diff dialog". The actual
# work is `VideoDiffCheckJob`'s — `VideoSync` is the convention shim
# that lets the bulk-as-foundation framework dispatch us without a
# special case.
#
# Note: `VideoSync` is distinct from `VideoSyncBack` (Phase 12). The
# latter pushes a locally-edited video back to YouTube post-edit; the
# former pulls YouTube state and surfaces divergence. They are NOT
# the same path.
class VideoSync < ApplicationJob
  queue_as :default

  def perform(video_id)
    VideoDiffCheckJob.new.perform(video_id)
  end
end
