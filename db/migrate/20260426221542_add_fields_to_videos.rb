class AddFieldsToVideos < ActiveRecord::Migration[8.1]
  def change
    add_column :videos, :scheduled_publish_at, :datetime
    add_column :videos, :privacy_status, :integer
    add_column :videos, :category_id, :integer
    add_column :videos, :default_language, :string
    add_column :videos, :made_for_kids, :boolean, default: false, null: false
  end
end
