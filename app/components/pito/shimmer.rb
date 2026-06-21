# frozen_string_literal: true

require "zlib"

module Pito
  # Shared helpers for the shimmer effects (keybinding / identifier / hashtag).
  #
  # SINGLE SOURCE OF TRUTH for the staggered animation-delay bucket: every
  # shimmer call site derives its `.pito-shimmer-dN` class from `offset_class`
  # so adjacent tokens never pulse in sync, and changing the bucket count is a
  # one-line edit here (mirrored by the `.pito-shimmer-d0..dN-1` classes in
  # application.css). The colour classes (`.pito-token-shimmer`,
  # `.pito-kbd-shimmer`, `.pito-hashtag-shimmer`) live in application.css.
  module Shimmer
    # Number of shared staggered delay buckets (.pito-shimmer-d0..d{OFFSETS-1}).
    OFFSETS = 20

    module_function

    # Stable per-text delay-bucket class. Uses a CRC32-based hash so that
    # neighbouring / sequential inputs scatter to distant buckets rather than
    # landing in adjacent ones (bytes.sum clusters; CRC32 avalanches).
    def offset_class(text, buckets: OFFSETS)
      "pito-shimmer-d#{Zlib.crc32(text.to_s) % buckets}"
    end
  end
end
