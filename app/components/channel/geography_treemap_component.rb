# Phase 37 (audience-geography A-slice, 2026-05-19) — Variant 3:
# squarified treemap rendering of top-N countries.
#
# Each country becomes a rectangle whose AREA is proportional to its
# share of the aggregated view count. Bigger view share → bigger
# rectangle. Rectangles tile the canvas without gaps using the well-
# known squarified-treemap algorithm (Bruls / Huijsen / van Wijk 2000).
#
# Implementation strategy (CSS-only, no D3):
#
#   * Outer canvas is a fixed-aspect block (560×280 px).
#   * The squarify algorithm processes countries in descending order
#     and packs them into horizontal or vertical "strips" along the
#     shorter side of the remaining rectangle. The strip orientation
#     flips between iterations so the tiles stay close to square (the
#     "squarification" property).
#   * Each computed rectangle is emitted as an absolutely-positioned
#     `<div>` with `left/top/width/height` in % of the canvas. The view
#     layer reads these directly — no inline Stimulus, no JS-side
#     layout work.
#
# Color choice — every rectangle uses `var(--color-link)` as the base
# fill with the `opacity` modulated by rank so the largest tile is
# darkest and the smallest is lightest. That keeps the variant family
# (list / bar / treemap) on the same accent color without depending on
# a new palette token.
#
# Top-N — 10 countries. Anything beyond 10 in the mock-data tail is
# folded into the "Other" bucket so the treemap doesn't end up with
# 1-pixel slivers; small but visible "Other" rectangle is more legible.
class Channel::GeographyTreemapComponent < ViewComponent::Base
  TOP_N = 10
  CANVAS_WIDTH = 560
  CANVAS_HEIGHT = 280

  def initialize(channels:)
    @channels = Array(channels)
  end

  # Returns an Array of layout hashes:
  #   { country_code:, country_name:, views:, percent:,
  #     x:, y:, w:, h:, opacity: }
  # x/y/w/h are in % of the canvas (0..100).
  def tiles
    return @tiles if defined?(@tiles)

    rows = aggregated_rows
    return @tiles = [] if rows.empty?

    total = rows.sum { |r| r[:views] }
    return @tiles = [] if total.zero?

    # Squarify operates on areas. We scale every country's view share
    # to fill the canvas (in pixel-area units), then walk the algorithm
    # over the working rectangle.
    canvas_area = CANVAS_WIDTH * CANVAS_HEIGHT
    items = rows.map do |r|
      r.merge(area: r[:views].to_f * canvas_area / total)
    end

    placed = squarify(items, x: 0, y: 0, w: CANVAS_WIDTH, h: CANVAS_HEIGHT)

    @tiles = placed.each_with_index.map do |tile, idx|
      {
        country_code: tile[:country_code],
        country_name: tile[:country_name],
        views: tile[:views],
        percent: (tile[:views].to_f * 100 / total).round(1),
        x: (tile[:x] * 100.0 / CANVAS_WIDTH).round(3),
        y: (tile[:y] * 100.0 / CANVAS_HEIGHT).round(3),
        w: (tile[:w] * 100.0 / CANVAS_WIDTH).round(3),
        h: (tile[:h] * 100.0 / CANVAS_HEIGHT).round(3),
        # Opacity ramps from 0.95 (rank 0) to 0.45 (last rank).
        opacity: opacity_for(idx, placed.size)
      }
    end
  end

  def has_data?
    !tiles.empty?
  end

  def canvas_width_px
    CANVAS_WIDTH
  end

  def canvas_height_px
    CANVAS_HEIGHT
  end

  private

  # Aggregate views per country, take top TOP_N, fold the rest into
  # an "Other" pseudo-row. Returns an Array<Hash> sorted descending.
  def aggregated_rows
    sums = Hash.new(0)
    names = {}
    @channels.each do |c|
      Array(c[:geography]).each do |row|
        code = row[:country_code].to_s
        sums[code] += row[:views].to_i
        names[code] ||= row[:country_name].to_s
      end
    end
    return [] if sums.empty?

    ranked = sums.sort_by { |_, v| -v }
    top = ranked.first(TOP_N)
    rest = ranked.drop(TOP_N)

    rows = top.map do |code, views|
      { country_code: code, country_name: names[code], views: views }
    end
    if rest.any?
      rows << {
        country_code: "—",
        country_name: "Other",
        views: rest.sum { |_, v| v }
      }
    end
    rows
  end

  def opacity_for(idx, total)
    return 0.95 if total <= 1
    top = 0.95
    bottom = 0.45
    (top - (top - bottom) * idx / (total - 1)).round(3)
  end

  # ---- Squarified treemap (Bruls/Huijsen/van Wijk 2000) ------------
  #
  # `items` — Array<Hash> with `:area` set (in canvas-pixel units).
  # x/y/w/h — pixel bounds of the working rectangle.
  # Returns each input hash augmented with `:x, :y, :w, :h` (px).
  #
  # Convention: a "row" is placed along the SHORTER side of the
  # remaining rectangle and occupies the FULL length of that side.
  # `row_depth` is the extent of the row along the LONGER side
  # (= row_area / shorter_side). Items inside the row stack along the
  # SHORTER side, each occupying the full row_depth on the longer
  # axis and `item.area / row_depth` on the shorter axis.
  def squarify(items, x:, y:, w:, h:)
    placed = []
    remaining = items.dup
    current_x = x
    current_y = y
    current_w = w
    current_h = h

    while remaining.any?
      row = [ remaining.shift ]
      shorter = [ current_w, current_h ].min

      while remaining.any?
        next_item = remaining.first
        if worst_ratio(row, shorter) >= worst_ratio(row + [ next_item ], shorter)
          row << remaining.shift
        else
          break
        end
      end

      placed.concat(layout_row(row, current_x, current_y, current_w, current_h))

      # Shrink the working rectangle along the LONGER side by the
      # row's depth (row_area / shorter_side).
      row_area = row.sum { |r| r[:area] }
      row_depth = shorter.zero? ? 0 : row_area / shorter

      if current_w >= current_h
        # Wider than tall → row consumed a vertical strip on the left
        # edge; shift remaining rect right.
        current_x += row_depth
        current_w -= row_depth
      else
        # Taller than wide → row consumed a horizontal strip on the
        # top edge; shift remaining rect down.
        current_y += row_depth
        current_h -= row_depth
      end
    end

    placed
  end

  # Worst (largest) aspect ratio of a candidate row when packed along
  # `shorter` side. Lower is better (closer to 1 = squarer tiles).
  def worst_ratio(row, shorter)
    return Float::INFINITY if row.empty? || shorter.zero?
    sum = row.sum { |r| r[:area] }
    max = row.map { |r| r[:area] }.max
    min = row.map { |r| r[:area] }.min
    s2 = shorter.to_f**2
    sum2 = sum.to_f**2
    [ (s2 * max) / sum2, sum2 / (s2 * min) ].max
  end

  # Lay out a single row of items inside the working rectangle.
  # The row is placed along the shorter side; items stack along it.
  def layout_row(row, x, y, w, h)
    shorter = [ w, h ].min
    row_area = row.sum { |r| r[:area] }
    row_depth = shorter.zero? ? 0 : row_area / shorter

    if w >= h
      # Wider than tall → row strip is vertical along the left edge.
      # Items stack on y-axis; each item full row_depth wide, area /
      # row_depth tall.
      cursor = y
      row.map do |item|
        length = row_depth.zero? ? 0 : item[:area] / row_depth
        rect = item.merge(x: x, y: cursor, w: row_depth, h: length)
        cursor += length
        rect
      end
    else
      # Taller than wide → row strip is horizontal along the top edge.
      # Items stack on x-axis; each item area / row_depth wide,
      # row_depth tall.
      cursor = x
      row.map do |item|
        length = row_depth.zero? ? 0 : item[:area] / row_depth
        rect = item.merge(x: cursor, y: y, w: length, h: row_depth)
        cursor += length
        rect
      end
    end
  end
end
