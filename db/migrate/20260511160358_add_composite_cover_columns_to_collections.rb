# Phase 27 §01h — Collections composite cover columns.
#
# Mirrors the `bundles.composite_cover_*` shape so the new
# `Collections::CoverComposer` service can stamp the on-disk fingerprint
# and re-derive the public URL. Both columns nullable — the composite
# only exists after the first 2..6+ member composer run; counts of 0 / 1
# return nil without persisting.
#
# `composite_cover_path` stores the relative path under
# `<PITO_ASSETS_PATH>/composites/` (mirrors `Bundle#composite_cover_path`).
# `composite_cover_checksum` carries the SHA-256 fingerprint computed by
# `Composite::Checksum.compute(cover_image_ids_sorted, layout_name)`.
class AddCompositeCoverColumnsToCollections < ActiveRecord::Migration[8.1]
  def change
    add_column :collections, :composite_cover_path,     :string
    add_column :collections, :composite_cover_checksum, :string
  end
end
