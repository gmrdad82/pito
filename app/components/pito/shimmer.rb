# frozen_string_literal: true

require "zlib"

module Pito
  # Shared helpers for the shimmer effects (keybinding / identifier / hashtag).
  #
  # SINGLE SOURCE OF TRUTH for the staggered animation-delay bucket: every
  # shimmer call site derives its `.pito-shimmer-dN` class from `offset_class`
  # so adjacent tokens never pulse in sync, and changing the bucket count is a
  # one-line edit here (mirrored by the `.pito-shimmer-d0..dN-1` classes in
  # application.css). The colour classes (`.pito-reference-shimmer`,
  # `.pito-action-shimmer`, `.pito-hashtag-shimmer`) live in application.css.
  module Shimmer
    # Number of shared staggered delay buckets (.pito-shimmer-d0..d{OFFSETS-1}).
    OFFSETS = 20

    module_function

    # Stable per-text delay-bucket class. Uses a CRC32-based hash so that
    # neighbouring / sequential inputs scatter to distant buckets rather than
    # landing in adjacent ones (bytes.sum clusters; CRC32 avalanches).
    #
    # `seed:` (optional) mixes an extra value into the hash so that two cells
    # with the SAME text but different seeds land in different buckets — used by
    # list-row call sites to break synchrony when the same @handle or genre
    # repeats down every row.  The seed-less behaviour is unchanged (back-compat).
    def offset_class(text, buckets: OFFSETS, seed: nil)
      input = seed.nil? ? text.to_s : "#{seed}\x00#{text}"
      "pito-shimmer-d#{Zlib.crc32(input) % buckets}"
    end
  end
end
