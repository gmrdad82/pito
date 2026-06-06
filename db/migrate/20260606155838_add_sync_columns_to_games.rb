class AddSyncColumnsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :last_sync_error, :text
    add_column :games, :resyncing, :boolean, null: false, default: false
  end
end
