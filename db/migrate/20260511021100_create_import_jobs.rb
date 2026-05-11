# Phase 22 §4.1 — ImportJob ledger.
#
# One row per (channel, user, click on `[start import]`). Tracks the
# per-channel video-import flow: counters, status, audit columns, and
# timestamps. Status is an integer enum
# (queued / running / completed / failed). Retention is forever — the
# rows double as an audit trail.
class CreateImportJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :import_jobs do |t|
      t.references :channel, null: false, foreign_key: { on_delete: :cascade }
      t.references :enqueued_by, null: false,
                                 foreign_key: { to_table: :users, on_delete: :restrict }
      t.integer  :status,          null: false, default: 0
      t.integer  :total_videos,    null: false, default: 0
      t.integer  :imported_videos, null: false, default: 0
      t.integer  :failed_videos,   null: false, default: 0
      t.jsonb    :error_payload
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    # `in_flight` scope hits (channel_id, status).
    add_index :import_jobs, %i[channel_id status]
    # Future dashboard / audit views.
    add_index :import_jobs, %i[status created_at]
  end
end
