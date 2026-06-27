class AddDeletingAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :deleting_at, :datetime
    add_index :conversations, :deleting_at
  end
end
