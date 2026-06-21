# frozen_string_literal: true

# Creates the analytics_cache table used by Pito::Analytics::Cache.
#
# analytics_cache — signature-keyed cache for async analytics fan-out.
#   signature  — opaque string key; unique across the table.
#   status     — lifecycle state: pending / ready / failed.
#   payload    — jsonb result (nil until ready).
#   expires_at — TTL expiry; nil means the row never expires.
#   error      — truncated failure message; nil unless failed.
class CreateAnalyticsCache < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_cache do |t|
      t.text     :error
      t.datetime :expires_at
      t.jsonb    :payload
      t.string   :signature, null: false
      t.string   :status,    null: false, default: "pending"
      t.timestamps
    end

    add_index :analytics_cache, :expires_at,
              name: "index_analytics_cache_on_expires_at"

    add_index :analytics_cache, :signature,
              unique: true,
              name: "index_analytics_cache_on_signature"
  end
end
