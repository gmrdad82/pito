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
  end
end
