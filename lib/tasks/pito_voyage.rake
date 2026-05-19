# Phase 34 (2026-05-18) — Voyage AI / Meilisearch backfill tasks.
#
# Operator entry points for re-indexing the entire Game corpus
# through the Voyage + Meilisearch pipeline. Used after:
#   - Initial Voyage rollout (existing games need their first
#     embedding pass).
#   - A model change (`Voyage::Client::DEFAULT_MODEL` swap) that
#     requires re-embedding every row.
#   - Operator-triggered "rebuild search" workflow.
#
# Async by design: enqueues one `GameVoyageIndexJob` per Game on
# the `:search` queue. Sidekiq workers absorb the rate-limit /
# back-pressure shape; the rake task returns as soon as every job
# is enqueued so the operator's shell isn't held open for the
# duration of the embedding sweep.
#
# Filter: `where.not(summary: nil)` excludes the unsynced rows that
# have nothing to embed yet. A row with a title-only would also be
# embeddable but its signal-to-noise is poor; the IGDB-sync hook
# (`Igdb::SyncGame#call` success path) will pick those up the next
# time they re-sync.
namespace :pito do
  namespace :voyage do
    desc "Re-enqueue Voyage embedding + Meilisearch indexing for every " \
         "synced Game. Async — returns once jobs are enqueued."
    task reindex_games: :environment do
      scope = Game.where.not(summary: nil)
      total = scope.count
      enqueued = 0

      scope.find_each do |game|
        GameVoyageIndexJob.perform_later(game.id)
        enqueued += 1
      end

      puts "enqueued #{enqueued} GameVoyageIndexJob#{'s' unless enqueued == 1} " \
           "(of #{total} synced games). Watch Sidekiq's :search queue " \
           "for progress."
    end

    # Phase 34 (2026-05-18) — Bundle backfill. Mirrors
    # `reindex_games` for the Bundle half of the unified `/games`
    # corpus. No filter on `Bundle.summary_embedding` — we want every
    # bundle indexed, including ones with no members yet (the
    # indexer no-ops cleanly on a fully-blank input set).
    desc "Re-enqueue Voyage embedding + Meilisearch indexing for every " \
         "Bundle. Async — returns once jobs are enqueued."
    task reindex_bundles: :environment do
      total = Bundle.count
      enqueued = 0

      Bundle.find_each do |bundle|
        BundleVoyageIndexJob.perform_later(bundle.id)
        enqueued += 1
      end

      puts "enqueued #{enqueued} BundleVoyageIndexJob#{'s' unless enqueued == 1} " \
           "(of #{total} bundles). Watch Sidekiq's :search queue " \
           "for progress."
    end

    # Phase 35 (2026-05-19) — Channel backfill. Mirrors
    # `reindex_games` / `reindex_bundles` for the Channel half of the
    # Voyage corpus. No filter on `Channel.summary_embedding` — every
    # channel goes through the indexer; the indexer itself no-ops on
    # blank composite text (rows before the first YouTube sync land
    # populates title / description / keywords).
    desc "Re-enqueue Voyage embedding for every Channel. Async — " \
         "returns once jobs are enqueued."
    task reindex_channels: :environment do
      total = Channel.count
      enqueued = 0

      Channel.find_each do |channel|
        ChannelVoyageIndexJob.perform_later(channel.id)
        enqueued += 1
      end

      puts "enqueued #{enqueued} ChannelVoyageIndexJob#{'s' unless enqueued == 1} " \
           "(of #{total} channels). Watch Sidekiq's :search queue " \
           "for progress."
    end

    # Phase 34 (2026-05-18) — full-corpus backfill convenience. Runs
    # `reindex_games`, `reindex_bundles`, and `reindex_channels` in
    # one shot so a single operator command refreshes the entire
    # Voyage embedding corpus (Games + Bundles power the unified
    # `/games` Meilisearch index; Channels power the pgvector
    # neighbor lookups via `has_neighbors :summary_embedding`).
    desc "Re-enqueue Voyage embedding + Meilisearch indexing for every " \
         "Game + Bundle + Channel. Async."
    task reindex_all: %i[reindex_games reindex_bundles reindex_channels]
  end
end
