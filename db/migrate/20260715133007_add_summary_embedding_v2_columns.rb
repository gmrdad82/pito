# frozen_string_literal: true

# 3.0.0 embeddinggemma re-embed — additive first step.
#
# embeddinggemma-300m (768-dim, local llama.cpp sidecar — see
# `Pito::Embedding::Client`) replaces Voyage AI as the embedding
# provider. This migration only ADDS the new 768-dim columns
# alongside the existing 1024-dim Voyage columns; nothing is renamed
# or dropped here, so no data loss and no downtime. The old
# `summary_embedding` columns stay live and queryable until the
# backfill into the `_v2` columns is verified full. A LATER migration
# swaps the names (v2 -> canonical) and drops the retired Voyage
# columns (L8).
#
# NOTE: a `notes` table/model does not exist in the current schema
# (it was purged in the "Beta reboot: chat-first pito" consolidation —
# see db/migrate/20260607182924_beta_migration.rb). Only `games` and
# `videos` currently carry a Voyage `summary_embedding` column, so
# only those two get a `summary_embedding_v2` column here. If a notes
# concept is reintroduced, its embedding column belongs in that
# table's own creation migration, not bolted on here.
class AddSummaryEmbeddingV2Columns < ActiveRecord::Migration[8.1]
  def change
    add_column :games,  :summary_embedding_v2, :vector, limit: 768
    add_column :videos, :summary_embedding_v2, :vector, limit: 768
  end
end
