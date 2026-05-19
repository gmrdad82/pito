# Canonical horizontal-scroll shelf wrapper. Previously namespaced as
# `Games::ShelfComponent` (Phase 27 Wave F) — promoted to a top-level
# `ShelfComponent` on 2026-05-19 so non-/games surfaces (notably
# `/channels` Wave A1) can reuse the same chrome.
#
# Renders the shared chrome that was previously duplicated across
# `_letter_shelves.html.erb`, `_genre_sub_shelf.html.erb`, and
# `_bundles_for_shelf.html.erb`:
#
#   <section class="shelf <extra_classes>" data-controller="steam-shelf"
#            data-shelf="<shelf_kind>" ...extra_data>
#     [optional heading wrapper — emitted only when `heading:` is present]
#     <div class="dot-list">
#       <h2|h3>HEADING <StatusBadge count></h2|h3>
#       (optional [see all] BracketedLink)
#     </div>
#     <div class="shelf-row <row_classes>" data-steam-shelf-target="row">
#       (caller-provided tiles via `content` block)
#     </div>
#   </section>
#
# Tiles are passed through ViewComponent's `content` slot so the shelf
# has no knowledge of the specific tile type (game / genre / bundle /
# channel id-card / future). The hairline between consecutive sub-shelves
# is CSS-driven (see `app/assets/tailwind/application.css` selector
# `section[data-shelf="outer-genres"] > section.sub-shelf:not(:first-of-type)`)
# — the component does not emit an explicit `<hr>`.
#
# 2026-05-17 (Wave F rewire) — extended to absorb the divergent
# markup of the three /games callers without losing load-bearing CSS hooks
# or request-spec assertions:
#   * extra_classes  — appended to the outer `<section class="shelf ...">`
#     (e.g. "shelf--letter", "sub-shelf sub-shelf--genre", "shelf--bundles
#     outer-shelf"). Specs grep for these literals.
#   * shelf_kind     — emitted as `data-shelf="<kind>"` (e.g. "letter",
#     "genre-sub", "outer-bundles"). CSS + request specs depend on this.
#   * data           — extra `data-*` attributes on the outer section
#     (e.g. `{ letter: "A" }`, `{ genre_id: 42 }`).
#   * section_style  — inline style override for the outer section
#     (genre sub-shelf uses `margin-top: 12px`; the others omit the
#     style and rely on the CSS `.shelf { margin-top: 16px }` default,
#     which the hairline rule for sibling letter / genre shelves can
#     override down to the tighter `margin-top: 8px`).
#   * heading_style  — inline style override for the heading element
#     (genre sub-shelf compresses to `font-size: 13px`).
#   * heading_margin — inline `margin-bottom` for the heading wrapper
#     (genre sub-shelf uses 4px; the others use 6px).
#   * row_classes    — appended to the row `class` (e.g.
#     "letter-shelf-row", "sub-shelf-row", "bundles-shelf-row").
#   * row_gap        — inline `gap` on the row (bundles shelf uses 12px,
#     all others 6px).
#   * row_align      — inline `align-items` on the row (bundles uses
#     "flex-start"; the others omit it).
#   * more_href      — when present, renders a `[see all]` BracketedLink
#     in the heading row (genre sub-shelf with overflow).
#
# 2026-05-18 — `heading_extras` slot. ViewComponent slot for arbitrary
# additional markup inside the heading `dot-list`, rendered AFTER the
# heading + count chip and AFTER the optional `[see all]` link. The
# bundles shelf uses it to inject the `[+]` create-bundle button next
# to the count chip (the user-direction wording: "after the chip with
# the number of bundles"). The slot is intentionally generic so other
# shelves can layer in heading-level actions without growing
# bespoke kwargs.
#
# 2026-05-19 — `heading:` is now OPTIONAL (default nil). When nil, the
# shelf emits ONLY the scrollable row — no heading wrapper, no
# `<h2>`/`<h3>`, no whitespace placeholder. /channels Wave A1 uses
# this headless mode for the ID-card shelf; /games callers continue
# to pass non-nil heading strings.
class ShelfComponent < ViewComponent::Base
  renders_one :heading_extras

  def initialize(heading: nil, count: nil, heading_level: :h2,
                 show_count: true, extra_classes: nil, shelf_kind: nil,
                 data: {}, section_style: nil, heading_style: nil,
                 heading_margin: "6px", row_classes: nil,
                 row_gap: "6px", row_align: nil, more_href: nil)
    @heading = heading
    @count = count
    @heading_level = heading_level
    @show_count = show_count && !count.nil?
    @extra_classes = extra_classes
    @shelf_kind = shelf_kind
    @data = data
    @section_style = section_style
    @heading_style = heading_style
    @heading_margin = heading_margin
    @row_classes = row_classes
    @row_gap = row_gap
    @row_align = row_align
    @more_href = more_href
  end

  private

  attr_reader :heading, :count, :heading_level, :show_count,
              :extra_classes, :shelf_kind, :data, :section_style,
              :heading_style, :heading_margin, :row_classes, :row_gap,
              :row_align, :more_href

  # Headless mode (2026-05-19) — when `heading:` is nil the template
  # skips the entire heading wrapper. Callers like /channels Wave A1
  # render a bare scrollable row of tiles directly under the page chrome.
  def heading?
    !heading.nil?
  end

  def section_classes
    [ "shelf", extra_classes ].compact.join(" ")
  end

  def row_class_string
    [ "shelf-row", row_classes ].compact.join(" ")
  end

  def section_inline_style
    # NIL when the caller does not override — the default
    # `margin-top: 16px` is now expressed in CSS (`.shelf` rule in
    # `app/assets/tailwind/application.css`) so the hairline rules
    # for sibling letter / genre shelves can win with their tighter
    # `margin-top: 8px` (inline styles would beat the cascade).
    section_style.presence
  end

  def heading_wrapper_style
    "margin-bottom: #{heading_margin};"
  end

  def heading_inline_style
    heading_style.present? ? "margin: 0; #{heading_style}" : "margin: 0;"
  end

  def row_inline_style
    base = "display: flex; gap: #{row_gap}; overflow-x: auto; padding-bottom: 6px;"
    base += " align-items: #{row_align};" if row_align.present?
    base
  end
end
