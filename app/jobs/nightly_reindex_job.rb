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
# Also derives every game's computed traits (Game::Traits::Derive,
# traits-design.md section 5) FIRST, before the NL sync and the games pass —
# the exact idempotent/self-healing sweep `rake pito:traits:derive` runs by
# hand, invoked directly (not the rake task) so a freshly-healed derived tag
# (an IGDB re-sync changed the underlying facts) lands in that SAME game's
# embed text this cycle instead of waiting for the next nightly run. Rescued
# PER GAME and logged, never fatal: one game's derive hiccup must not skip
# deriving the rest, or sink the NL sync / games / videos / events passes
# that follow.
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
    derive_traits
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

  # See the class header — mirrors Game::Traits::Derive's own heal loop
  # (lib/tasks/pito_traits.rake `pito_traits_derive_all!`) but rescues PER
  # GAME so one bad row can't skip deriving the rest of the games, and never
  # lets a derive failure sink the NL sync / games / videos / events passes
  # that follow.
  def derive_traits
    ::Game.find_each do |game|
      ::Game::Traits::Derive.call(game)
    rescue StandardError => e
      Rails.logger.warn("[NightlyReindexJob] Game::Traits::Derive failed for game ##{game.id}: #{e.class}: #{e.message}")
    end
  end

  # See the class header — never lets a router-cache failure sink the
  # games/videos/events pass that follows.
  def sync_nl_examples
    Pito::Nl::Router.sync!
  rescue StandardError => e
    Rails.logger.warn("[NightlyReindexJob] Pito::Nl::Router.sync! failed: #{e.class}: #{e.message}")
  end
end
