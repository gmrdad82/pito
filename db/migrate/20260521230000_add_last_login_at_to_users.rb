class AddLastLoginAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_login_at, :datetime
    add_index :users, :last_login_at
  end
end
