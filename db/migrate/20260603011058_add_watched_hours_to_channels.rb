class AddWatchedHoursToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :watched_hours, :bigint
  end
end
