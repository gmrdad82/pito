# Phase 27 follow-up (2026-05-17) — Bundle model simplification.
#
# Per the 2026-05-17 user-direction: "We only have one thing — Bundle.
# That's the only way of grouping a bunch of games together. Their only
# attribute is name. A game may be in 1, many, or none."
#
# The previous Collection→Bundle merge migration (20260517120000)
# preserved `bundle_type` so the rolled-in `Collection` rows could be
# distinguished from native Bundle rows. With the user direction this
# distinction goes away — every bundle is "just a bundle" with a name
# and a composite-cover artifact. Drop the discriminator columns and
# the IGDB-source provenance columns; drop the `last_error` column
# (only the IGDB seed / build path wrote it, both of which are being
# removed).
#
# What gets dropped:
#   - `bundles.bundle_type`        (integer enum: series/collection/genre/custom)
#   - `bundles.igdb_source_type`   (integer enum: franchise/source_collection/source_genre)
#   - `bundles.igdb_source_id`     (bigint — IGDB-side id)
#   - `bundles.last_error`         (text — last build / seed failure)
#   - `index_bundles_on_bundle_type`
#   - `index_bundles_on_igdb_source_id`
#   - `index_bundles_on_igdb_source_pair`
#
# What survives:
#   - `bundles.name`, `bundles.slug` (slug is auto-derived via FriendlyId
#     from name; kept for URL stability and the `:history` redirect
#     module).
#   - `bundles.composite_cover_path`, `bundles.composite_cover_checksum`.
#   - `bundle_members` join table (M2M) and its `position` column.
#
# Reversibility: the down path recreates the four columns and the three
# indexes but cannot restore the dropped values — rows reset to defaults
# (`bundle_type = 0` / series, `igdb_source_type = NULL`,
# `igdb_source_id = NULL`, `last_error = NULL`). Reverting after data
# loss is best-effort; the prior structural shape is restored so the
# app boots, no more.
class SimplifyBundlesDropCollectionsArtifacts < ActiveRecord::Migration[8.1]
  def up
    if index_exists?(:bundles, :bundle_type, name: "index_bundles_on_bundle_type")
      remove_index :bundles, name: "index_bundles_on_bundle_type"
    end
    if index_exists?(:bundles, :igdb_source_id, name: "index_bundles_on_igdb_source_id")
      remove_index :bundles, name: "index_bundles_on_igdb_source_id"
    end
    if index_exists?(:bundles, %i[igdb_source_type igdb_source_id], name: "index_bundles_on_igdb_source_pair")
      remove_index :bundles, name: "index_bundles_on_igdb_source_pair"
    end

    remove_column :bundles, :bundle_type      if column_exists?(:bundles, :bundle_type)
    remove_column :bundles, :igdb_source_type if column_exists?(:bundles, :igdb_source_type)
    remove_column :bundles, :igdb_source_id   if column_exists?(:bundles, :igdb_source_id)
    remove_column :bundles, :last_error       if column_exists?(:bundles, :last_error)
  end

  def down
    add_column :bundles, :bundle_type, :integer, default: 0, null: false
    add_column :bundles, :igdb_source_type, :integer
    add_column :bundles, :igdb_source_id, :bigint
    add_column :bundles, :last_error, :text

    add_index :bundles, :bundle_type, name: "index_bundles_on_bundle_type"
    add_index :bundles, :igdb_source_id,
              name: "index_bundles_on_igdb_source_id",
              where: "(igdb_source_id IS NOT NULL)"
    add_index :bundles, %i[igdb_source_type igdb_source_id],
              name: "index_bundles_on_igdb_source_pair",
              unique: true,
              where: "((igdb_source_type IS NOT NULL) AND (igdb_source_id IS NOT NULL))"
  end
end
