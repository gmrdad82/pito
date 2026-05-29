# frozen_string_literal: true

# Add trigram GIN indexes for fuzzy title matching (P8 / T8.6 + T8.7).
class AddTrigramIndexesToGamesAndVideos < ActiveRecord::Migration[8.1]
  def change
    add_index :games, :title,
              name: "index_games_on_title_trigram",
              using: :gin,
              opclass: :gin_trgm_ops

    add_index :videos, :title,
              name: "index_videos_on_title_trigram",
              using: :gin,
              opclass: :gin_trgm_ops
  end
end
