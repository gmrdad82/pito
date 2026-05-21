# Phase 37 Wave A1 (landscape redesign, 2026-05-19) — channel ID card.
#
# 2026-05-19 spec correction (locked by user) — layout refactor:
#
#   1. The vertical hairline between the left column (avatar) and the
#      right column (stat grid) is REMOVED. The body becomes a single
#      flex row with no internal divider.
#   2. The `@handle` link, which previously stacked under the avatar
#      in the left column, moves to the FOOTER. The left column now
#      contains only the avatar.
#   3. The footer is now FULL-WIDTH (was right-column-only before this
#      correction). It is a flex row with `[@handle]` at the left and
#      `[ Studio ]` at the right. No inner vertical divider between the
#      two links (removed 2026-05-19 final ID-card refinement before
#      the component was LOCKED).
#   4. The horizontal hairline above the footer spans the FULL card
#      width (was right-column-only before this correction). It is a
#      `border-top` on the full-width footer element.
#   5. Footer copy: `[ YouTube Studio ]` → `[ Studio ]`. The link
#      target is unchanged (YouTube Studio URL).
#
# Avatar stays at 80 px (unchanged) — the freed-up vertical space
# from removing the handle from the left column is absorbed by
# `justify-content: center`, keeping the avatar visually centered
# inside the column with comfortable breathing room.
#
# Card outer dimensions (158 px tall × 314 px wide), the stat grid
# layout, the trend glyphs, the avatar shape + size, and the score-
# badge overlay are unchanged.
#
# Per-channel summary card rendered in the ID-card shelf below the
# title/chips hairline on `/channels`. Layout (current spec):
#
#   ┌────────────────────────────────────────────────────────────┐
#   │ Studio Aurora                                              │  name row (6px / 8px padding)
#   │────────────────────────────────────────────────────────────│  full-width hairline
#   │                                                            │
#   │   ┌────────┐         2.3K   subs    ▲                      │
#   │   │   ◯    │          47M   views   –                      │  body: avatar + stats, no divider
#   │   └────────┘        1.200h  hours   ▼                      │
#   │                                                            │
#   │────────────────────────────────────────────────────────────│  full-width hairline
#   │  [@studioaurora]                              [ Studio ]   │  full-width footer
#   └────────────────────────────────────────────────────────────┘
#
# All values are mocked this slice — `Channel::MockData.channels` feeds
# the hash. Wave B replaces the data source.
#
# Tokens / spacing — traceable to canonical sources:
#
#   * Outer card border: `var(--color-cover-border)` + 2 px radius.
#     Same framed-thumbnail convention as /games tiles and the
#     /channels avatar shelf's per-avatar border.
#   * Card height: 158 px — 30% reduction of the prior 226 px
#     (226 × 0.7 = 158.2 → 158), locked by user 2026-05-19 follow-up.
#   * Card width: 314 px — diverges from ISO ID-1; widened by 25%
#     (251 × 1.25 = 313.75 → 314) with the extra 63 px flowing into
#     the right (stats) column.
#   * Avatar size: 80 px square. Fits the left column's vertical
#     content area (158 card − 25 name row − 1 hairline − 1 footer
#     hairline − ~22 footer − 12 col padding ≈ 97 px budget) with
#     comfortable slack, centered via `justify-content: center`.
#     Now that the `@handle` is in the footer (not stacked under the
#     avatar), the left column hosts only the avatar.
#   * Stat value font-size: 13 px (body default per CLAUDE.md visual
#     style §Font — "13 px base"). `font-variant-numeric: tabular-nums`
#     keeps digit widths consistent across rows.
#   * Channel name (top row): 13 px body font-size, `font-weight: 700`.
#   * Stat grid: CSS Grid `grid-template-columns: 1fr auto auto`.
#     Number cell uses `justify-self: end` so the three number right
#     edges align at the same x against the unit label. Unit cell
#     uses `justify-self: start` so the three unit left edges align.
#     Arrow cell uses `justify-self: end` so the three arrows align
#     at the right edge of the right column with ~4 px breathing
#     space from the card's right edge.
#   * Inner hairlines: 1 px solid `var(--color-border)`, matching
#     `hr.hairline` and the existing convention. Two horizontal
#     hairlines, both FULL card width: one below the name row, one
#     above the footer. No vertical hairline inside the body.
#   * Footer: full card width, `display: flex` with
#     `justify-content: space-between`. `[@handle]` on the left,
#     `[ Studio ]` on the right. No inner vertical divider between
#     the two links (removed 2026-05-19 final ID-card refinement).
#   * Trend glyph color: `var(--color-trend-up|steady|down)`. Glyphs
#     `▲ ▼ –` match the sortable-table convention.
#
# External links — `BracketedLinkComponent` auto-detects absolute
# `http(s)://` URLs and emits `target="_blank"` + `rel="noopener
# noreferrer"` itself. Both the handle link and the `[ Studio ]`
# link go through it unmodified.
#
# Inert — no Stimulus, no actions. The two external `<a>` tags are the
# only interactive surfaces.
class Channel::IdCardComponent < ViewComponent::Base
  # @param channel [Hash] one entry from `Channel::MockData.channels`.
  #   Required keys: `:id`, `:display_name`, `:handle`,
  #   `:youtube_channel_id`, `:avatar_url` (may be nil),
  #   `:subscriber_count`, `:view_count`, `:watch_hours`,
  #   `:subscriber_count_trend`, `:view_count_trend`,
  #   `:watch_hours_trend`.
  # @param score [Integer, nil] 0–100 recommendation score. Optional —
  #   when present (recommended-channels-on-/games/:id usage), the card
  #   renders a small `[NN]` badge overlay in the top-right corner. When
  #   nil/absent (plain /channels usage), no badge renders and the card
  #   is byte-identical to its pre-score layout.
  def initialize(channel:, score: nil)
    @channel = channel
    @score = score
  end

  attr_reader :channel, :score

  # 158 px — 30% reduction of the prior 226 px (226 × 0.7 = 158.2 → 158), locked by user 2026-05-19 follow-up.
  def card_height_px
    "158px"
  end

  # 314 px — diverge from ISO ID-1; widen by 25% (251 × 1.25 = 313.75 → 314) with the extra 63 px flowing entirely to the right column (left col stays 125 px fixed; right col auto-expands from 126 → 189 px).
  def card_width_px
    "314px"
  end

  # 80 px — fits the left column's vertical content area inside the
  # 158 px card after the 2026-05-19 spec correction moved the
  # `@handle` into the full-width footer. Centered via
  # `justify-content: center` on the left column with comfortable
  # vertical slack on both sides.
  def avatar_dimension_px
    "80px"
  end

  # 13 px — body default per CLAUDE.md visual style.
  def stat_value_font_size
    "13px"
  end

  def handle_url
    "https://youtube.com/#{channel[:handle]}"
  end

  def studio_url
    "https://studio.youtube.com/channel/#{channel[:youtube_channel_id]}"
  end

  # Map trend symbol → glyph + token name. Returns `[glyph, css_var]`.
  # Solid arrows (U+25B2 / U+25BC) match the sortable-table header
  # convention at `app/assets/tailwind/application.css` L984 +
  # L1012/L1017/L1024/L1025 — the same arrow shapes that signal sort
  # direction on every sortable table, reused here for consistency.
  # The steady glyph stays as the U+2013 en-dash (already a muted
  # minus-like glyph; visually matches the steady state).
  TREND_GLYPHS = {
    up:     [ "▲", "--color-trend-up" ],
    steady: [ "–", "--color-trend-steady" ],
    down:   [ "▼", "--color-trend-down" ]
  }.freeze

  def trend(symbol)
    TREND_GLYPHS.fetch(symbol&.to_sym, TREND_GLYPHS[:steady])
  end

  def subscriber_count_formatted
    Pito::Formatter::CompactCount.call(channel[:subscriber_count])
  end

  def view_count_formatted
    Pito::Formatter::CompactCount.call(channel[:view_count])
  end

  def watch_hours_formatted
    Pito::Formatter::CompactHours.call(channel[:watch_hours])
  end
end
