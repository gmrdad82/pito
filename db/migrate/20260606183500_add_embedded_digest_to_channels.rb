class AddEmbeddedDigestToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :embedded_digest, :string
  end
end
