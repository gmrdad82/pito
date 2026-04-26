class DropProductionsAndNotes < ActiveRecord::Migration[8.1]
  def change
    drop_table :productions do |t|
      t.integer "cost_cents"
      t.float "editing_hours"
      t.float "filming_hours"
      t.text "notes"
      t.float "other_hours"
      t.float "script_hours"
      t.integer "status"
      t.float "thumbnail_hours"
      t.string "title"
      t.bigint "video_id"
      t.timestamps
      t.index [ "video_id" ], name: "index_productions_on_video_id"
    end

    drop_table :notes do |t|
      t.text "body"
      t.integer "kind"
      t.string "title"
      t.timestamps
    end
  end
end
