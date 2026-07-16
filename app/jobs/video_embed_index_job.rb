# frozen_string_literal: true

# Background embedding indexer for a single Video. Thin wrapper around
# `Video::EmbeddingIndexer.call` (digest-gated). Embeds the video and nothing
# else — channels have no embedding of their own (design B): the channel↔game
# recommendations are derived on demand from the channel's video vectors, so a
# video (re)embed needs no downstream recompute.
#
# Enqueued by: `Pito::Sync::VideoLibrary#upsert` (per created/changed video)
# and `NightlyReindexJob`.
#
# Queue is `:search` — same lane as the other embed index jobs.
#
# 2026-07-15 — Voyage decommission: renamed from the retired Voyage AI
# per-record job, repointed onto `Video::EmbeddingIndexer` (the local-embedder
# successor to the retired Voyage AI indexer).
class VideoEmbedIndexJob < ApplicationJob
  queue_as :search

  # A nil embedding (transient network blip, or a sidecar hiccup) raises
  # EmbeddingNil. Retry with backoff rather than leaving the video
  # permanently unembedded (which makes it invisible to
  # Game::ChannelRecommendation). Mirrors GameImportJob.
  retry_on Pito::Error::EmbeddingNil, wait: :polynomially_longer, attempts: 5

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    Video::EmbeddingIndexer.call(video)
  end
end
