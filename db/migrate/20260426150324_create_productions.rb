class CreateProductions < ActiveRecord::Migration[8.1]
  def change
    create_table :productions do |t|
      t.references :video, null: true, foreign_key: true
      t.string :title
      t.float :script_hours
      t.float :filming_hours
      t.float :editing_hours
      t.float :thumbnail_hours
      t.float :other_hours
      t.text :notes
      t.integer :status
      t.integer :cost_cents

      t.timestamps
    end
  end
end
