# frozen_string_literal: true

# Stage 2 master: nightly reindex orchestrator, scheduled at 2:00 UTC via
# `config/recurring.yml` (`nightly_reindex`, both `production:` and
# `development:` blocks).
#
# Runs ≥1h after Stage 1 (`NightlySyncJob` at 1:00 UTC) so freshly synced
# games and videos have time to land before we check/queue their embeddings.
# Separate cron entries (NOT a delayed enqueue from Stage 1) so a long sync
# backlog can never compress the gap.
#
# Also self-heals the NL router's example cache (Pito::Nl::Router.sync!,
# 3.0.1 P11) before the games pass — the same materialize/prune/embed sweep
# `rake pito:nl:sync` runs by hand, so a tools.yml `nl_examples:` edit (or a
# sidecar that was down at the last sync) never drifts unnoticed for long.
# Rescued and logged, never fatal: a router-cache hiccup must not sink the
# games/videos/events reindex that follows.
#
# Fan-out strategy — atomic-jobs principle:
#
#   - `GameEmbedIndexJob.perform_later(id)` per game
#   - `VideoEmbedIndexJob.perform_later(id)` per video
#
# Both indexers are digest-gated (`Game::EmbeddingIndexer` /
# `Video::EmbeddingIndexer`): unchanged rows are no-ops so the nightly cost
# is only the actually-changed records. `pito:embeddings:reindex` is left
# for manual operator full-reindex runs; this master uses per-entity fan-out
# per the atomic-jobs locked decision.
#
# Events (conversation search) are different: they normally self-embed via
# `EventEmbedJob` right after each turn completes, and `Pito::Embedding::
# EventIndexer` is forgiving (never raises) rather than something to enqueue
# a retryable job for. This pass exists only to self-heal the ones that
# DIDN'T land — a sidecar hiccup mid-turn leaves `embedding: nil` behind with
# no automatic retry, so we re-attempt exactly those nil-embedding rows here
# inline, scoped to `EMBEDDABLE_KINDS` to keep the query cheap. Digest gating
# inside the indexer means an already-embedded event is never re-attempted.
#
# Design B (locked): channels have NO embedding of their own. Channel↔game
# recommendations are computed on demand from video vectors. There is NO
# channel-centroid step here.
class NightlyReindexJob < ApplicationJob
  queue_as :default

  def perform
    sync_nl_examples

    ::Game.find_each do |game|
      ::GameEmbedIndexJob.perform_later(game.id)
    end

    ::Video.find_each do |video|
      ::VideoEmbedIndexJob.perform_later(video.id)
    end

    ::Event.where(kind: Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS, embedding: nil).find_each do |event|
      Pito::Embedding::EventIndexer.call(event)
    end
  end

  private

  # See the class header — never lets a router-cache failure sink the
  # games/videos/events pass that follows.
  def sync_nl_examples
    Pito::Nl::Router.sync!
  rescue StandardError => e
    Rails.logger.warn("[NightlyReindexJob] Pito::Nl::Router.sync! failed: #{e.class}: #{e.message}")
  end
end
