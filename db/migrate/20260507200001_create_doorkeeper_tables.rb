# frozen_string_literal: true

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md). Doorkeeper installer
# output, modified per the spec:
#   - `oauth_applications.confidential` defaults to `false` (PKCE-encouraged
#     for new public clients; confidential is opt-in via the form).
#   - `tenant_id` (`bigint`, NOT NULL after backfill, FK, indexed) on all
#     three Doorkeeper tables — applications are tenant-scoped primitives,
#     and tokens / grants inherit the application's tenant. The custom
#     models (`OauthApplication`, `OauthAccessToken`, `OauthAccessGrant`)
#     include `BelongsToTenant` so the runtime path enforces the scope.
class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string  :name,    null: false
      t.string  :uid,     null: false
      # Public clients (PKCE) submit no client_secret; the column is still
      # NOT NULL because Doorkeeper generates a value per row regardless.
      t.string  :secret,  null: false

      t.text    :redirect_uri, null: false
      t.string  :scopes,       null: false, default: ""
      # Phase 6B locked decision: PKCE-encouraged → default `confidential`
      # to false. The form lets the user flip it to confidential explicitly.
      t.boolean :confidential, null: false, default: false
      # Tenant ownership; `BelongsToTenant` enforces scope at the model.
      t.references :tenant, null: false, foreign_key: true
      t.timestamps null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner,  null: false
      t.references :application,     null: false
      t.references :tenant,          null: false, foreign_key: true
      t.string   :token,             null: false
      t.integer  :expires_in,        null: false
      t.text     :redirect_uri,      null: false
      t.string   :scopes,            null: false, default: ""
      t.datetime :created_at,        null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key(
      :oauth_access_grants,
      :oauth_applications,
      column: :application_id
    )

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true
      t.references :application,    null: false
      t.references :tenant,         null: false, foreign_key: true

      t.string :token, null: false

      t.string   :refresh_token
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at

      # Refresh-token rotation: when a refresh exchange runs, the previous
      # refresh token is recorded here. Doorkeeper revokes it as soon as a
      # new access token is created (or once the related access token is
      # actually used, depending on configuration). Phase 6B locked
      # decision: rotation enabled.
      t.string   :previous_refresh_token, null: false, default: ""
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true

    add_foreign_key(
      :oauth_access_tokens,
      :oauth_applications,
      column: :application_id
    )
  end
end
