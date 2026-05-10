# Phase 14 §2 — Composite cover checksum.
#
# Pure module. `Composite::Checksum.compute(image_ids, layout_name)`
# returns a hex SHA-256 string over the sorted list of cover_image_ids
# plus the layout name. Sorting is lexical (string compare) so the
# checksum is invariant under member reordering — repositioning members
# in the bundle does NOT trigger a cover regen. Layout differences DO.
#
# Nil entries in the array are filtered out before hashing (members
# without IGDB cover art).
module Composite
  module Checksum
    module_function

    def compute(image_ids, layout_name)
      cleaned = Array(image_ids).compact.map(&:to_s).sort
      payload = "#{layout_name}|#{cleaned.join(',')}"
      Digest::SHA256.hexdigest(payload)
    end
  end
end
