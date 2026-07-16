# frozen_string_literal: true

# Owner ruling, 2026-07-15: the retired Voyage vectors are re-derivable dead
# weight once every reader has moved to the 768-dim embeddinggemma seam
# (`summary_embedding_v2`, added in 20260715133007 / indexed in
# 20260715140000). Dropping the old 1024-dim columns and promoting `_v2` to
# the canonical name in one migration chain dissolves the deferred "finalize"
# step entirely — there is no longer a straggler migration waiting on a
# manual go-ahead. `rake pito:embeddings:reindex` after deploy repopulates
# `summary_embedding` from source text; nothing here needs the actual
# vectors to survive.
#
# Ordering proof (per table): `db/schema.rb` shows the canonical index name
# `index_{games,videos}_on_summary_embedding_hnsw` currently belongs to the
# OLD 1024-dim column (schema.rb L266/536), while the NEW 768-dim column
# is indexed under the `_v2_hnsw` name (L267/537). A single-column index is
# dropped automatically when its column is dropped, so step 1
# (`remove_column ...summary_embedding`) frees the canonical index name as a
# side effect. Step 2 renames the `_v2` column onto the now-vacant canonical
# column name. Step 3 can then `rename_index` the `_v2_hnsw` index onto the
# canonical name, which step 1 already vacated — reversing this order would
# collide step 3 against the still-live old index. This must run column
# rename before index rename per table, and drop before either.
#
# `down` restores STRUCTURE only — an empty 1024-dim `summary_embedding`
# column reappears, but its vectors are gone for good. That data loss is
# accepted; it's the entire point of this migration.
#
# The seam constants (`Pito::Embedding` readers/writers) flip from
# `summary_embedding_v2` to `summary_embedding` in the companion code step,
# not here, so schema and code land together in one release.
class DropVoyageEmbeddingsAndPromoteV2 < ActiveRecord::Migration[8.1]
  def change
    remove_column :games, :summary_embedding, :vector, limit: 1024
    rename_column :games, :summary_embedding_v2, :summary_embedding
    rename_index :games, "index_games_on_summary_embedding_v2_hnsw", "index_games_on_summary_embedding_hnsw"

    remove_column :videos, :summary_embedding, :vector, limit: 1024
    rename_column :videos, :summary_embedding_v2, :summary_embedding
    rename_index :videos, "index_videos_on_summary_embedding_v2_hnsw", "index_videos_on_summary_embedding_hnsw"
  end
end
