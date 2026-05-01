class ChangeSavedViewsUrlToCitext < ActiveRecord::Migration[8.1]
  def up
    change_column :saved_views, :url, :citext, null: false
  end

  def down
    change_column :saved_views, :url, :string, null: false
  end
end
