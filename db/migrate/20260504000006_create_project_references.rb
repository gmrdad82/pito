# Phase 4 §4 — polymorphic join. A Project references zero-or-more Games
# AND zero-or-more Collections via `referenceable_type`/`referenceable_id`.
# `referenceable_type` is constrained to {"Game","Collection"} at the model
# layer (validation in ProjectReference).
#
# Rollback: reversible.
class CreateProjectReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :project_references do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true, index: true
      t.string :referenceable_type, null: false
      t.bigint :referenceable_id, null: false

      t.timestamps
    end

    add_index :project_references,
              [ :referenceable_type, :referenceable_id ],
              name: "index_project_references_on_referenceable"

    add_index :project_references,
              [ :project_id, :referenceable_type, :referenceable_id ],
              unique: true,
              name: "index_project_references_unique_per_project"
  end
end
