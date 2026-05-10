# Phase 14 §2 — Bundles + Composite Covers.
#
# `bundles` is a curated grouping of Games used as a video- attribution
# pivot. Four `bundle_type` values: series / collection / genre / custom.
# An optional IGDB-source pair (`igdb_source_type`, `igdb_source_id`)
# pins the bundle to an IGDB resource (franchise / collection / genre).
# Composite cover output lands under `<PITO_ASSETS_PATH>/composites/`
# at `<bundle_type>-<bundle_id>.jpg` (flat path per ADR 0003).
#
# `bundle_members` is the join table. Composite uniqueness on
# `(bundle_id, game_id)`. `position` controls insertion order (default
# `MAX(position) + 1`); display-only, not the cover-content checksum
# input (see `Composite::Checksum`).
class CreateBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :bundles do |t|
      t.integer :bundle_type, null: false, default: 0
      t.string  :name,        null: false
      t.integer :igdb_source_type
      t.bigint  :igdb_source_id
      t.string  :composite_cover_path
      t.string  :composite_cover_checksum
      t.text    :last_error

      t.timestamps
    end

    add_index :bundles, :bundle_type
    add_index :bundles, :igdb_source_id,
              where: "igdb_source_id IS NOT NULL",
              name: "index_bundles_on_igdb_source_id"
    add_index :bundles, [ :igdb_source_type, :igdb_source_id ],
              unique: true,
              where: "igdb_source_type IS NOT NULL AND igdb_source_id IS NOT NULL",
              name: "index_bundles_on_igdb_source_pair"

    create_table :bundle_members do |t|
      t.references :bundle, null: false, foreign_key: { on_delete: :cascade }
      t.references :game,   null: false, foreign_key: { on_delete: :cascade }
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :bundle_members, [ :bundle_id, :game_id ], unique: true,
              name: "index_bundle_members_on_bundle_and_game"
    add_index :bundle_members, [ :bundle_id, :position ],
              name: "index_bundle_members_on_bundle_and_position"
  end
end
