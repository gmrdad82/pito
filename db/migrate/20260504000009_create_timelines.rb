# Phase 4 §3.6 — Timeline tracks DaVinci-side editing state per project.
# `state` is aasm-managed (editing → exported → uploaded; see model). `video_id`
# becomes non-null on the upload! transition (Phase B).
#
# Rollback: reversible.
class CreateTimelines < ActiveRecord::Migration[8.1]
  def change
    create_table :timelines do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true, index: true
      t.references :video, null: true, foreign_key: true, index: true
      t.string :title, null: false, default: "Untitled timeline"
      t.integer :state, null: false, default: 0
      t.integer :duration_seconds
      t.string :resolution
      t.decimal :fps, precision: 6, scale: 3
      t.string :export_filename

      t.timestamps
    end

    add_index :timelines, :state
  end
end
