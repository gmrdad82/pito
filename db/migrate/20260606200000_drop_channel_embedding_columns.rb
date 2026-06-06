class DropChannelEmbeddingColumns < ActiveRecord::Migration[8.1]
  # Design B: channels have no embedding of their own. The channel↔game
  # recommendations are derived on demand from the channel's VIDEO vectors
  # (grouped by channel_id), so there is no synthetic channel centroid to store
  # or maintain. Drop the embedding columns (the HNSW index drops with the
  # vector column). (description/keywords are dropped separately in the next
  # migration — channel is grouping/filtering only.)
  def change
    remove_column :channels, :summary_embedding, :vector, limit: 1024
    remove_column :channels, :embedded_digest, :string
  end
end
