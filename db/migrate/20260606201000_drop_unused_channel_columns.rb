class DropUnusedChannelColumns < ActiveRecord::Migration[8.1]
  # The channel is used only for grouping/filtering (by channel_id) — its
  # long-form content fields are never read in pito (they live in YouTube
  # Studio). Drop `description` and `keywords`; channel keeps identity/display
  # bits (title, handle, avatar/banner) + stats.
  def change
    remove_column :channels, :description, :text
    remove_column :channels, :keywords, :text
  end
end
