class CreateSavedViews < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_views do |t|
      t.integer :kind, null: false
      t.string :url, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :saved_views, [ :kind, :url ], unique: true
  end
end
