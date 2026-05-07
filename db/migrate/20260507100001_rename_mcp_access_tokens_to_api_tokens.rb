# Phase 3 — Step B (5b-token-and-auth-concern.md) — table rename.
#
# Renames `mcp_access_tokens` → `api_tokens` and renames the matching
# unique index. The follow-up migration (5b step 2) adds tenant_id /
# user_id / scopes / expires_at columns.
#
# Reversible. No data loss; existing rows survive.
class RenameMcpAccessTokensToApiTokens < ActiveRecord::Migration[8.1]
  def up
    rename_table :mcp_access_tokens, :api_tokens

    # rename_table renames the implicit PK sequence and the implicit
    # `id` index, but the named unique index on `token_digest` keeps
    # the old name. Rename it explicitly.
    if index_name_exists?(:api_tokens, "index_mcp_access_tokens_on_token_digest")
      rename_index :api_tokens,
                   "index_mcp_access_tokens_on_token_digest",
                   "index_api_tokens_on_token_digest"
    end
  end

  def down
    if index_name_exists?(:api_tokens, "index_api_tokens_on_token_digest")
      rename_index :api_tokens,
                   "index_api_tokens_on_token_digest",
                   "index_mcp_access_tokens_on_token_digest"
    end

    rename_table :api_tokens, :mcp_access_tokens
  end
end
