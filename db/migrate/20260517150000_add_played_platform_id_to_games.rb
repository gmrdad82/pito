class AddPlayedPlatformIdToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :played_platform, foreign_key: { to_table: :platforms }, null: true
  end
end
