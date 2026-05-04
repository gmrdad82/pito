# Phase 4 §3.1 — Project is the workspace shell: gather games / collections /
# footage / notes / timelines. Tenant-scoped. The polymorphic references to
# Game and Collection live on `project_references` (next migration).
#
# Rollback: reversible.
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.string :name, null: false, default: "Untitled project"
      t.text :concept

      t.timestamps
    end

    add_index :projects, [ :tenant_id, :name ]
  end
end
