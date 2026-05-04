# Phase 4 §3.3 — Game holds title, optional collection grouping, and a
# jsonb `platforms` array of `{platform, owned, recorded_on}` triples.
# Active Storage attaches `cover_art` (variants declared on the model).
#
# Rollback: reversible.
class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :collection, null: true, foreign_key: true, index: true
      t.string :title, null: false, default: "Untitled game"
      t.string :publisher
      t.jsonb :platforms, null: false, default: []

      t.timestamps
    end

    add_index :games, [ :tenant_id, :title ]
  end
end
