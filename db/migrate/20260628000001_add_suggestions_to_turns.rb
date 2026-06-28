# frozen_string_literal: true

class AddSuggestionsToTurns < ActiveRecord::Migration[8.1]
  def change
    add_column :turns, :suggestions, :jsonb, default: [], null: false
  end
end
