# frozen_string_literal: true

# Background Voyage indexer for a single Video. Thin wrapper around
# `Video::VoyageIndexer.call` (digest-gated). Embeds the video and nothing
# else — channels have no embedding of their own (design B): the channel↔game
# recommendations are derived on demand from the channel's video vectors, so a
# video (re)embed needs no downstream recompute.
#
# Enqueued by: `ImportVideosJob` (per created/changed video), the
# `pito:voyage:reindex_videos` backfill, and the nightly reindex (P14).
#
# Queue is `:search` — same lane as the other Voyage index jobs.
class VideoVoyageIndexJob < ApplicationJob
  queue_as :search

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    Video::VoyageIndexer.call(video)
  end
end
