# Phase 12 — Step A (6a-sessions-and-login-ui.md) — server-side
# sessions table.
#
# The Rails default `cookie_store` carries the opaque session token
# (`pito_session` cookie); this table is the source of truth for "is
# this session still valid?". Cookie ↔ row binding via
# `HMAC-SHA256(:tokens.pepper, plaintext)` (`Pito::TokenDigest`) — same
# pepper as ApiToken, so one credential covers both surfaces.
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tenant, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.inet :ip
      t.text :user_agent
      t.boolean :remember, null: false, default: false
      t.datetime :last_activity_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :sessions, :token_digest, unique: true
    add_index :sessions, [ :tenant_id, :user_id ]
  end
end
