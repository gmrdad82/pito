class RemoveTagsFromChannels < ActiveRecord::Migration[8.1]
  # Channels have no native `tags` field in the YouTube Data API — only
  # videos do (`video.snippet.tags`). The column added in
  # AddEmbeddingToChannels was never backed by a data source; the real
  # future signal is an aggregate of the channel's videos' tags, folded
  # into the embedding text via `videos.tags` when /videos returns.
  def change
    remove_column :channels, :tags, :text, array: true, default: [], null: false
  end
end
