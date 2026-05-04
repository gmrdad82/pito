# Phase 4 §3.2 — Collection groups Games (e.g. "FromSoftware",
# "Steam Deck favorites"). Tenant-scoped from day one.
#
# Rollback: `bin/rails db:rollback STEP=N` reaches this migration; the
# `change` block is reversible (drop_table inferred from create_table).
class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.string :name, null: false, default: "Untitled collection"

      t.timestamps
    end

    add_index :collections, [ :tenant_id, :name ]
  end
end
