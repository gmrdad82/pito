# Phase 25 — 01a. Trusted-location list. Schema-only here; the upsert on
# successful login lands in 01b together with the new-location detection
# logic. The 01a sub-spec only creates the table so the schema is
# forward-compatible.
#
# Composite unique key on (user_id, fingerprint_hash, ip_prefix) per
# LD-5. `first_seen_at` is set at row creation; `last_seen_at` is
# bumped on every subsequent successful login from the pair.
class CreateTrustedLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :trusted_locations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :fingerprint_hash, null: false, limit: 64
      t.string :ip_prefix, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :trusted_locations,
              [ :user_id, :fingerprint_hash, :ip_prefix ],
              unique: true,
              name: "index_trusted_locations_unique_triple"
    add_index :trusted_locations, :last_seen_at
  end
end
