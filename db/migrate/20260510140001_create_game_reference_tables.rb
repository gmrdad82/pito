# Phase 14 §1 — `genres`, `platforms`, `companies` reference tables.
#
# Thin reference rows keyed by IGDB ID + name. NOT a full IGDB mirror;
# rows are populated lazily as games reference them.
class CreateGameReferenceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :genres do |t|
      t.bigint :igdb_id, null: false
      t.string :name,    null: false
      t.string :slug
      t.timestamps

      t.index :igdb_id, unique: true
    end

    create_table :platforms do |t|
      t.bigint :igdb_id,      null: false
      t.string :name,         null: false
      t.string :abbreviation
      t.string :slug
      t.timestamps

      t.index :igdb_id, unique: true
    end

    create_table :companies do |t|
      t.bigint :igdb_id, null: false
      t.string :name,    null: false
      t.string :slug
      t.timestamps

      t.index :igdb_id, unique: true
    end

    add_foreign_key :games, :platforms, column: :platform_owned_id, on_delete: :nullify
  end
end
