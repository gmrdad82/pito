# Phase 7 — Step B (7b-youtube-client-and-audit.md) — append-only
# audit log of every YouTube / OAuth-revocation API call we issue.
# One row per logical call (final outcome) — the retry loop in
# `Youtube::Client` collapses 5xx attempts into the single row that
# reflects the eventual success/failure (locked decision in 7B).
class CreateYoutubeApiCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_api_calls do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :google_identity, null: true, foreign_key: true

      t.string :client_kind, null: false           # "oauth" | "public"
      t.string :endpoint, null: false              # e.g. "channels.list"
      t.string :http_method, null: false           # "GET" | "POST"
      t.integer :units, null: false                # quota cost (rounded up)
      t.string :outcome, null: false               # see model inclusion list
      t.integer :http_status                       # nullable
      t.text :error_message
      t.integer :duration_ms

      t.datetime :created_at, null: false
    end

    add_index :youtube_api_calls,
              [ :tenant_id, :google_identity_id, :created_at ],
              name: "index_youtube_api_calls_on_tenant_identity_time"
    add_index :youtube_api_calls,
              [ :tenant_id, :client_kind, :created_at ],
              name: "index_youtube_api_calls_on_tenant_kind_time"
    add_index :youtube_api_calls,
              [ :tenant_id, :outcome, :created_at ],
              name: "index_youtube_api_calls_on_tenant_outcome_time"
  end
end
