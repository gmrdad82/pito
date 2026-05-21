class DropProjects < ActiveRecord::Migration[8.1]
  # D18 (2026-05-21) — drop Projects entirely. Footage attaches to Game
  # directly going forward; Timeline + ProjectReference were Project-
  # only models so they go with it. CalendarEntry + Video keep their
  # `project_id` FK column removed (the model relations are also gone).
  def change
    # 1) Drop FKs pointing at projects from sibling tables.
    remove_foreign_key :footages,          :projects, if_exists: true
    remove_foreign_key :calendar_entries,  :projects, if_exists: true
    remove_foreign_key :videos,            :projects, if_exists: true
    remove_foreign_key :project_references, :projects, if_exists: true
    remove_foreign_key :timelines,         :projects, if_exists: true
    remove_foreign_key :timelines,         :videos,   if_exists: true

    # 2) Drop project_id columns from sibling tables.
    remove_reference :footages,         :project, foreign_key: false, if_exists: true
    remove_reference :calendar_entries, :project, foreign_key: false, if_exists: true
    remove_reference :videos,           :project, foreign_key: false, if_exists: true

    # 3) Drop dependent tables (timelines, project_references).
    drop_table :timelines do |t|
      t.datetime :created_at, null: false
      t.integer  :duration_seconds
      t.string   :export_filename
      t.decimal  :fps, precision: 6, scale: 3
      t.bigint   :project_id, null: false
      t.string   :resolution
      t.integer  :state, default: 0, null: false
      t.string   :title, default: "Untitled timeline", null: false
      t.datetime :updated_at, null: false
      t.bigint   :video_id

      t.index [ :project_id ], name: "index_timelines_on_project_id"
      t.index [ :state ],      name: "index_timelines_on_state"
      t.index [ :video_id ],   name: "index_timelines_on_video_id"
    end

    drop_table :project_references do |t|
      t.datetime :created_at, null: false
      t.bigint   :project_id, null: false
      t.bigint   :referenceable_id, null: false
      t.string   :referenceable_type, null: false
      t.datetime :updated_at, null: false

      t.index [ :project_id, :referenceable_type, :referenceable_id ],
              name: "index_project_references_unique_per_project", unique: true
      t.index [ :project_id ], name: "index_project_references_on_project_id"
      t.index [ :referenceable_type, :referenceable_id ],
              name: "index_project_references_on_referenceable"
    end

    # 4) Drop the projects table itself.
    drop_table :projects do |t|
      t.datetime :created_at, null: false
      t.integer  :footage_duration_seconds, default: 0, null: false
      t.integer  :footages_count, default: 0, null: false
      t.string   :name, default: "Untitled project", null: false
      t.integer  :notes_count, default: 0, null: false
      t.integer  :notes_words_total, default: 0, null: false
      t.string   :slug, null: false
      t.integer  :timelines_count, default: 0, null: false
      t.datetime :updated_at, null: false

      t.index [ :name ], name: "index_projects_on_name"
      t.index [ :slug ], name: "index_projects_on_slug", unique: true
    end
  end
end
