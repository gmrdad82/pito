# Phase 4 §3.4 — Footage row carries probed metadata + project linkage.
# `tenant_id` denormalized for tenant-scoped uniqueness on `local_path`.
# Validations + enums live on the model.
#
# Rollback: reversible.
class CreateFootages < ActiveRecord::Migration[8.1]
  def change
    create_table :footages do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :game, null: true, foreign_key: true, index: true
      t.references :tenant, null: true, foreign_key: true, index: true
      t.integer :kind, null: false                # enum a_roll:0, b_roll:1
      t.integer :source, null: false              # enum obs:0, camera:1
      t.string :platform
      t.string :local_path, null: false
      t.string :nas_path
      t.string :filename, null: false
      t.text :description
      t.datetime :recorded_at
      t.integer :duration_seconds
      t.string :resolution
      t.decimal :fps, precision: 6, scale: 3
      t.string :codec
      t.integer :bit_depth, null: false, default: 8
      t.string :color_profile
      t.string :aspect_ratio
      t.integer :orientation                      # enum landscape:0, portrait:1
      t.integer :audio_track_count
      t.boolean :has_commentary_track, null: false, default: false

      t.timestamps
    end

    add_index :footages, [ :tenant_id, :local_path ], unique: true
  end
end
