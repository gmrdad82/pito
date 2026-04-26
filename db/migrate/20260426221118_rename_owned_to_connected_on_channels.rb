class RenameOwnedToConnectedOnChannels < ActiveRecord::Migration[8.1]
  def change
    rename_column :channels, :owned, :connected
  end
end
