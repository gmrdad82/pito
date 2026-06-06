class DropPrimaryGenreFromGames < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :games, column: :primary_genre_id
    remove_index :games, :primary_genre_id, if_exists: true
    remove_column :games, :primary_genre_id
  end

  def down
    add_column :games, :primary_genre_id, :bigint
    add_index :games, :primary_genre_id, name: "index_games_on_primary_genre_id"
    add_foreign_key :games, :genres, column: :primary_genre_id, on_delete: :nullify
  end
end
