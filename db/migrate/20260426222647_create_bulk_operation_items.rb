class CreateBulkOperationItems < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_operation_items do |t|
      t.references :bulk_operation, null: false, foreign_key: true
      t.references :video, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :bulk_operation_items, [ :bulk_operation_id, :video_id ], unique: true
  end
end
