# frozen_string_literal: true

# Adds the channel description (the YouTube "about" blurb) so `show channel`
# can render it in the detail kv-table. Synced from the channel `snippet`
# (already fetched by ChannelInfoJob); nullable text — empty until the next sync.
class AddDescriptionToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :description, :text
  end
end
