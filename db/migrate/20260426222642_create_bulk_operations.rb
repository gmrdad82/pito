class CreateBulkOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_operations do |t|
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :parameters
      t.jsonb :target_video_ids
      t.jsonb :dry_run_preview
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
