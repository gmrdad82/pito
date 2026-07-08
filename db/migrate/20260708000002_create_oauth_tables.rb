# frozen_string_literal: true

# G130 (MCP): the hand-rolled OAuth 2.1 schema — three tables, digests only,
# never a raw secret. Public clients (PKCE, no client_secret). Access tokens are
# short-lived (24h); refresh tokens never expire (revocation only). Codes are
# single-use, 5-minute, PKCE-bound.
class CreateOauthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string :client_id,     null: false
      t.string :name,          null: false
      t.jsonb  :redirect_uris, null: false, default: []
      t.timestamps
    end
    add_index :oauth_clients, :client_id, unique: true

    create_table :oauth_codes do |t|
      t.string   :client_id,             null: false
      t.string   :code_digest,           null: false
      t.string   :code_challenge,        null: false
      t.string   :code_challenge_method, null: false, default: "S256"
      t.string   :redirect_uri,          null: false
      t.datetime :expires_at,            null: false
      t.boolean  :used,                  null: false, default: false
      t.timestamps
    end
    add_index :oauth_codes, :code_digest, unique: true
    add_index :oauth_codes, :client_id

    create_table :oauth_tokens do |t|
      t.string   :client_id,      null: false
      t.string   :token_digest,   null: false  # access token (rotated on refresh)
      t.string   :refresh_digest, null: false  # refresh token (never expires; revoke only)
      t.datetime :expires_at,     null: false  # ACCESS token expiry
      t.datetime :revoked_at                   # null = active
      t.timestamps
    end
    add_index :oauth_tokens, :token_digest,   unique: true
    add_index :oauth_tokens, :refresh_digest, unique: true
    add_index :oauth_tokens, :client_id
  end
end
