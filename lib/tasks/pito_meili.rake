# Phase B (2026-05-19) — Meilisearch backfill tasks for Channel.
#
# Operator entry point for re-indexing the entire Channel corpus
# into the dedicated `channels_<env>` Meilisearch index. Used after:
#   - Initial Channel-search rollout (existing channels need their
#     first index pass).
#   - A `Channel::MeilisearchIndexer` attribute-list change that
#     requires a forced reconfigure across the whole corpus.
#   - Operator-triggered "rebuild channel search" workflow.
#
# Synchronous by design (one indexer call per Channel, inline) —
# the Channel corpus is small relative to Games + Bundles and the
# operator gets per-row progress feedback. Sidekiq-async backfill
# was considered but rejected for Channel because the surface is
# small and operator-facing.
namespace :pito do
  namespace :meili do
    desc "Reindex all channels into Meilisearch (idempotent)"
    task reindex_channels: :environment do
      total = Channel.count
      Channel.find_each.with_index(1) do |channel, idx|
        Channel::MeilisearchIndexer.new(channel).call
        puts "[#{idx}/#{total}] indexed channel #{channel.id}"
      end
    end
  end
end
