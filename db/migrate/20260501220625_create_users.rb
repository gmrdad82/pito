class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.citext :username, null: false
      t.citext :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end

    # Globally unique (NOT scoped to tenant) per spec.
    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
  end
end
