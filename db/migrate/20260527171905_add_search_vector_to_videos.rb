# frozen_string_literal: true

# Add full-text search vector to videos (P8 / T8.4 + T8.5).
class AddSearchVectorToVideos < ActiveRecord::Migration[8.1]
  def change
    execute <<~SQL
      ALTER TABLE videos ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))
        ) STORED;
    SQL

    add_index :videos, :search_vector, using: :gin
  end
end
