# frozen_string_literal: true

# Add full-text search vector to games (P8 / T8.2 + T8.3).
class AddSearchVectorToGames < ActiveRecord::Migration[8.1]
  def change
    # Generated stored column — kept in sync by PG automatically.
    execute <<~SQL
      ALTER TABLE games ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, ''))
        ) STORED;
    SQL

    add_index :games, :search_vector, using: :gin
  end
end
