# Phase 4 §3.5 — Note record mirrors a markdown file on disk under
# <PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/<file>.md (flat — no
# subdirs). `embedding` is a pgvector(1024) column for voyage-3; populated
# by Notes::EmbedJob (Phase B) when voyage_embeddings_enabled is true.
#
# pgvector extension is already enabled by the earlier
# enable_postgres_extensions migration (Phase 2).
#
# Rollback: reversible. Drops the table; the vector type itself stays
# enabled for other tables.
class CreateProjectNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true, index: true
      t.string :path, null: false
      t.string :title, null: false, default: "Untitled note"
      t.datetime :last_modified_at, null: false
      t.column :embedding, "vector(1024)"

      t.timestamps
    end

    add_index :notes, [ :tenant_id, :path ], unique: true
  end
end
