class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      t.string     :uuid,         null: false
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :event,        null: false, foreign_key: true, index: false
      t.timestamps
    end

    add_index :shares, :uuid,     unique: true
    add_index :shares, :event_id, unique: true
  end
end
