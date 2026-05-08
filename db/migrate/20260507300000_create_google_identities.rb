# Phase 7 — Step A (7a-google-oauth-and-identity.md) — Google OAuth
# identity table. One row per (User, Google account) pair. Token
# columns are encrypted via Active Record Encryption (`encrypts ...`
# on the model); the columns themselves are plain text on the schema
# side because ARE writes the ciphertext into the same column.
class CreateGoogleIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :google_identities do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Stable Google subject id (`sub` claim). Unique within a tenant.
      t.string :google_subject_id, null: false

      # Citext for case-insensitive lookups on Google email.
      t.citext :email, null: false

      # Encrypted at the model layer via `encrypts :access_token` /
      # `encrypts :refresh_token`. The column type is `text` because
      # ARE writes a JSON-encoded ciphertext blob; `string` (varchar
      # 255) is too narrow.
      t.text :access_token, null: false
      t.text :refresh_token

      t.datetime :expires_at, null: false
      t.jsonb :scopes, null: false, default: []
      t.boolean :needs_reauth, null: false, default: false

      t.datetime :last_refreshed_at
      t.datetime :last_authorized_at, null: false

      t.timestamps
    end

    add_index :google_identities, [ :tenant_id, :google_subject_id ], unique: true
    add_index :google_identities, [ :tenant_id, :user_id ]
    add_index :google_identities, [ :tenant_id, :needs_reauth ],
              where: "needs_reauth = true",
              name: "index_google_identities_on_tenant_and_needs_reauth_partial"
  end
end
