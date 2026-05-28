class CreateConversationsTurnsEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.string :title, null: true
      t.timestamps
    end

    create_table :turns do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.integer :position, null: false
      t.string :input_kind, null: false
      t.string :input_text, null: false
      t.timestamps

      t.index [ :conversation_id, :position ], unique: true
    end

    create_table :events do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :turn, null: false, foreign_key: true, index: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps

      t.index [ :conversation_id, :position ], unique: true
    end
  end
end
