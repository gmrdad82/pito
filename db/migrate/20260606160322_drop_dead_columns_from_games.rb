class DropDeadColumnsFromGames < ActiveRecord::Migration[8.1]
  def up
    remove_column :games, :notes
    remove_column :games, :played_at
  end

  def down
    add_column :games, :notes, :text
    add_column :games, :played_at, :date
  end
end
