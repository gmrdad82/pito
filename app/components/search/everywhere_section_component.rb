# Phase 37 — "everywhere" omnisearch section wrapper.
#
# Standalone sibling of `Search::OmnisearchSectionComponent`. After
# the 2026-05-19 flat-list refactor the section component contributes
# ONLY the `<ul>` of row components — no heading, no leading hairline,
# no empty-state copy. Empty sections render nothing (the row-level
# type label on the right edge already conveys category, so missing
# kinds need no announcement). The component still exists as a
# grouping seam so the results template stays uniform and so future
# per-section styling has a hook to attach to.
#
# Args:
#   hits:    Enumerable. Empty → render nothing.
#   kind:    one of :game | :bundle | :channel. Drives the per-row
#             branch in `EverywhereRowComponent`.
module Search
  class EverywhereSectionComponent < ViewComponent::Base
    KINDS = %i[game bundle channel].freeze

    def initialize(hits:, kind:)
      raise ArgumentError, "unknown section kind: #{kind.inspect}" unless KINDS.include?(kind)

      @hits = hits
      @kind = kind
    end

    attr_reader :hits, :kind

    def empty?
      Array(@hits).empty?
    end
  end
end
