# frozen_string_literal: true

# Pito::Stack — per-request log of outbound external API calls.
# One row per Voyage / IGDB / YouTube request; counted over 24h + month
# windows. Pruned to ~2 months by Pito::Stack housekeeping.
class CreateApiRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :api_requests do |t|
      t.string :provider, null: false
      t.string :endpoint
      t.integer :units
      t.datetime :created_at, null: false
    end

    add_index :api_requests, [ :provider, :created_at ]
  end
end
