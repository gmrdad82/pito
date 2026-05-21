class DropNotesTable < ActiveRecord::Migration[8.1]
  def change
    drop_table :notes do |t|
      t.datetime "created_at", null: false
      t.column "embedding", "vector(1024)"
      t.datetime "last_modified_at", null: false
      t.string "path", null: false
      t.bigint "project_id", null: false
      t.string "title", default: "Untitled note", null: false
      t.datetime "updated_at", null: false
      t.integer "words_count", default: 0, null: false
      t.index [ "project_id", "path" ], name: "index_notes_on_project_id_and_path", unique: true
      t.index [ "project_id" ], name: "index_notes_on_project_id"
    end
  end
end
