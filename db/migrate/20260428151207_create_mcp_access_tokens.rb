class CreateMcpAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_access_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :last_token_preview, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :mcp_access_tokens, :token_digest, unique: true
  end
end
