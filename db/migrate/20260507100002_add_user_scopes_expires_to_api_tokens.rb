# Phase 3 — Step B (5b-token-and-auth-concern.md) — extend api_tokens.
#
# Adds the columns the renamed table did not yet carry:
#   - tenant_id (FK NOT NULL): the parallel Step A pass adds tenant_id to most
#     data tables; api_tokens was deferred to this step's rename so we add it
#     here.
#   - user_id (FK NOT NULL): every token belongs to a user (and through the
#     user, to a tenant).
#   - scopes (jsonb, NOT NULL, default `[]`): scope catalog strings, validated
#     in Ruby against `Scopes::ALL`.
#   - expires_at (datetime, nullable): optional expiry. UI for setting custom
#     expiry is Phase 12; the model supports it now.
#
# Backfill rules (existing seeded rows survive the rename):
#   - tenant_id ← Tenant.first.id
#   - user_id   ← User.first.id
#   - scopes    ← ["dev:read", "dev:write"]  # Phase 1 de-facto set
#
# Reversible.
class AddUserScopesExpiresToApiTokens < ActiveRecord::Migration[8.1]
  def up
    # 1. tenant_id — add nullable, backfill, then enforce NOT NULL + FK + index.
    add_reference :api_tokens, :tenant, foreign_key: true, null: true

    if Tenant.exists?
      tenant_id = Tenant.first.id
      execute <<~SQL.squish
        UPDATE api_tokens SET tenant_id = #{tenant_id} WHERE tenant_id IS NULL
      SQL
    end
    change_column_null :api_tokens, :tenant_id, false

    # 2. user_id — same pattern.
    add_reference :api_tokens, :user, foreign_key: true, null: true

    if User.exists?
      user_id = User.first.id
      execute <<~SQL.squish
        UPDATE api_tokens SET user_id = #{user_id} WHERE user_id IS NULL
      SQL
    end
    change_column_null :api_tokens, :user_id, false

    # 3. scopes — jsonb array of catalog strings. Default `[]`; backfill
    # existing rows to the Phase 1 dev:* set so CRUD continues working.
    add_column :api_tokens, :scopes, :jsonb, null: false, default: []

    execute <<~SQL.squish
      UPDATE api_tokens
         SET scopes = '["dev:read","dev:write"]'::jsonb
       WHERE scopes IS NULL OR scopes = '[]'::jsonb
    SQL

    # 4. expires_at — nullable. No backfill needed.
    add_column :api_tokens, :expires_at, :datetime, null: true

    # Indexes for the common lookup paths.
    add_index :api_tokens, :tenant_id, name: "index_api_tokens_on_tenant_id" unless index_exists?(:api_tokens, :tenant_id)
    add_index :api_tokens, :user_id, name: "index_api_tokens_on_user_id" unless index_exists?(:api_tokens, :user_id)
    add_index :api_tokens, :expires_at, name: "index_api_tokens_on_expires_at"
  end

  def down
    remove_index :api_tokens, name: "index_api_tokens_on_expires_at" if index_name_exists?(:api_tokens, "index_api_tokens_on_expires_at")
    remove_column :api_tokens, :expires_at
    remove_column :api_tokens, :scopes
    remove_reference :api_tokens, :user, foreign_key: true
    remove_reference :api_tokens, :tenant, foreign_key: true
  end
end
