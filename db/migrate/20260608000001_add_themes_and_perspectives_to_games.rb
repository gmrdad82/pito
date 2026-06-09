# frozen_string_literal: true

class AddThemesAndPerspectivesToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :themes, :text, array: true, null: false, default: []
    add_column :games, :player_perspectives, :text, array: true, null: false, default: []
    add_index :games, :themes, using: :gin
    add_index :games, :player_perspectives, using: :gin
  end
end
