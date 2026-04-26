class AddOwnedToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :owned, :boolean, default: false, null: false
  end
end
