# frozen_string_literal: true

# Avatars are now served from OUR ActiveStorage copy (Channel#avatar), attached
# during sync via Channel::Avatar::Ingest. The raw YouTube CDN URL is no longer
# stored — we never hotlink yt3.ggpht.com (it 429s).
class DropAvatarUrlFromChannels < ActiveRecord::Migration[8.1]
  def change
    remove_column :channels, :avatar_url, :string
  end
end
