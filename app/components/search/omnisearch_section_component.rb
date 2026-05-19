# 2026-05-18 — Section chrome for an omnisearch results pane.
#
# Replaces `app/views/shared/_search_section.html.erb`. Owns the
# heading + leading hairline + empty-state copy + `<ul>` wrapper.
# Per-row markup is supplied by the caller as the captured ERB
# content (one or more `<li>` rows, typically rendered through
# `Search::OmnisearchResultRowComponent`). Future omnisearch
# surfaces (/projects, /videos, /channels) reuse this component.
#
# Args:
#   heading:    string. Section label rendered in
#                h3.omnisearch-section-heading.
#   empty_copy: string. Rendered in p.text-muted when empty: true.
#   empty:      bool. When true, render the empty-state paragraph
#                instead of the `<ul>` body. Caller computes this
#                from its own collection (`result.local_games.any?`
#                etc.) — the component never iterates.
#   first:      bool. When true, suppress the leading hairline so
#                the topmost section does not begin with a
#                separator. Defaults false.
module Search
  class OmnisearchSectionComponent < ViewComponent::Base
    # The block passed to this component is expected to yield zero or
    # more <li> rows (each typically rendered via
    # `OmnisearchResultRowComponent`). The section component owns the
    # heading + hairline + `<ul>` wrapper + empty-state copy; the
    # caller owns row markup so per-mode actions stay localized.
    #
    # `empty:` is a bool that disables the `<ul>` body entirely so the
    # empty-state paragraph renders instead. Callers compute this from
    # their own collection (`result.local_games.any?` etc.) because
    # the section component never iterates — it just wraps.
    def initialize(heading:, empty_copy:, empty:, first: false)
      @heading = heading
      @empty_copy = empty_copy
      @empty = empty
      @first = first
    end

    attr_reader :heading, :empty_copy

    def first?
      @first
    end

    def empty?
      @empty
    end
  end
end
