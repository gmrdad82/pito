# Phase 37 Wave A1 (landscape redesign, 2026-05-19) — channel ID card.
#
# 2026-05-19 second follow-up (locked by user): card shrunk by 30%
# from the prior 226 × 358 footprint. New dimensions: 158 px tall ×
# 251 px wide (226 × 0.7 = 158.2 → 158; 358 × 0.7 = 250.6 → 251).
# Avatar scales the same way: 150 × 0.7 = 105 → 105 px. Internal
# fixed padding/gaps (6 px column padding, 8 px inter-element gap,
# 6 px name-row vertical / 8 px horizontal) stay unchanged because
# they were already small fixed values. Background tone moves to the
# new `--color-channel-id-card-bg` token (value copied from the
# Discord pane's `--color-pane-bg-a` tone; independent so future
# tweaks don't couple). Name row keeps CSS ellipsis truncation
# (`white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
# max-width: 100%`) so long channel names ellipsize on overflow
# only — short names render in full.
#
# Prior 2026-05-19 follow-up (now superseded by the resize above):
# card was sized at 226 px tall × 358 px wide. Height matched the
# /games index tile's visible total per the user's DevTools
# measurement: 150 × 220 cover/caption shell + 6 px caption padding-
# bottom = 226. Width recomputed via the ISO/IEC 7810 ID-1 landscape
# aspect ratio (1.586:1): 226 × 1.586 = 358.4 → 358 px. The five
# visual enhancements that shipped with that resize:
#
#   1. Channel-name row picks up 2 px padding on all sides.
#   2. Avatar gets more breathing room — extra top/bottom spacing
#      vs. the surrounding hairlines and extra left margin from the
#      card edge.
#   3. The `@handle` link centers horizontally under the avatar.
#   4. Bottom footer becomes RIGHT-COLUMN ONLY. The horizontal hairline
#      between body and footer also stays inside the right column. The
#      left column now extends down through the full body height,
#      giving the avatar a much larger vertical budget and the handle
#      more horizontal room. Footer copy changes `[ studio ]` → `[
#      YouTube Studio ]` (brand-names-capitalized rule).
#   5. The stat grid's column order flips. Was `arrow / number / unit`;
#      now `number / unit / arrow` so the trend arrow lives at the
#      right edge of the card (vertically aligned across the three
#      rows) with a small right margin.
#
# Per-channel summary card rendered in the ID-card shelf below the
# title/chips hairline on `/channels`. Layout (locked spec):
#
#   ┌────────────────────────────────────────────────────────────┐
#   │ Studio Aurora                                              │  name row (2px padding all sides)
#   │────────────────────────────────────────────────────────────│  full-width hairline
#   │                          │                                 │
#   │     ┌────────┐           │     2.3K   subs    ▲            │
#   │     │        │           │                                 │
#   │     │   ◯    │           │      47M   views   –            │
#   │     │        │           │                                 │
#   │     └────────┘           │   1.200h   hours   ▼            │
#   │                          │─────────────────────────────────│  hairline only on right column
#   │      @studioaurora       │              [ YouTube Studio ] │  footer only on right column
#   └────────────────────────────────────────────────────────────┘
#
# All values are mocked this slice — `Channels::MockData.channels` feeds
# the hash. Wave B replaces the data source.
#
# Tokens / spacing — traceable to canonical sources:
#
#   * Outer card border: `var(--color-cover-border)` + 2 px radius.
#     Same framed-thumbnail convention as /games tiles and the
#     /channels avatar shelf's per-avatar border.
#   * Card height: 226 px (locked by user 2026-05-19 from DevTools
#     measurement against the /games tile's visible total — 150 × 220
#     cover/caption shell + 6 px caption padding-bottom).
#   * Card width: 358 px = 226 × 1.586 (ISO/IEC 7810 ID-1 landscape
#     aspect, locked).
#   * Avatar size: 150 px square. Computed against the new layout's
#     left-column vertical budget (the left column now extends through
#     the full body height because the bottom hairline + footer are
#     right-column-only):
#       body height        = 226 − 21 (name row: 2+2 padding + 13 px
#                             body × ~1.3 ≈ 17) − 1 (top hairline)
#                            ≈ 204 px.
#       left col content   = body − 6 (top padding) − 6 (bottom
#                             padding)
#                            ≈ 192 px.
#       handle row         ≈ 17 px (bracketed link, body 13 px).
#       inter-row gap      = 8 px (extra breathing per Enhancement 2 —
#                             "more spacing in the avatar and the
#                             hairlines that surround it").
#       avatar budget      ≈ 192 − 17 − 8 = 167 px.
#       avatar width budget = (card_width / 2) − 6 (left margin from
#                             Enhancement 2) − 4 (right padding inside
#                             left col)
#                            = 179 − 6 − 4 = 169 px.
#       avatar size        = 150 px → fits both vertical and
#                             horizontal budgets with comfortable
#                             slack, up substantially from the prior
#                             124 px because the left column reclaimed
#                             the footer's vertical space.
#   * Stat value font-size: 13 px (body default per CLAUDE.md visual
#     style §Font — "13 px base"). `font-variant-numeric: tabular-nums`
#     keeps digit widths consistent across rows.
#   * Channel name (top row): 13 px body font-size, `font-weight: 700`.
#   * Stat grid: CSS Grid `grid-template-columns: 1fr auto auto`
#     (Enhancement 5). Number cell uses `justify-self: end` so the
#     three number right edges align at the same x against the unit
#     label. Unit cell uses `justify-self: start` so the three unit
#     left edges align. Arrow cell uses `justify-self: end` so the
#     three arrows align at the right edge of the right column with
#     ~4 px breathing space from the card's right edge (via the
#     right-column padding).
#   * Inner hairlines: 1 px solid `var(--color-border)`, matching
#     `hr.hairline` and the existing convention. The horizontal
#     hairline below the name still spans the full card width; the
#     hairline above the footer now spans only the right column
#     (rendered as a `border-top` on the footer element scoped to the
#     right column).
#   * Trend glyph color: `var(--color-trend-up|steady|down)`. Glyphs
#     `▲ ▼ –` match the sortable-table convention.
#
# External links — `BracketedLinkComponent` auto-detects absolute
# `http(s)://` URLs and emits `target="_blank"` + `rel="noopener
# noreferrer"` itself. Both the handle link and the `[ YouTube Studio
# ]` link go through it unmodified.
#
# Inert — no Stimulus, no actions. The two external `<a>` tags are the
# only interactive surfaces.
class Channels::IdCardComponent < ViewComponent::Base
  # @param channel [Hash] one entry from `Channels::MockData.channels`.
  #   Required keys: `:id`, `:display_name`, `:handle`,
  #   `:youtube_channel_id`, `:avatar_url` (may be nil),
  #   `:subscriber_count`, `:view_count`, `:watch_hours`,
  #   `:subscriber_count_trend`, `:view_count_trend`,
  #   `:watch_hours_trend`.
  def initialize(channel:)
    @channel = channel
  end

  attr_reader :channel

  # 158 px — 30% reduction of the prior 226 px (226 × 0.7 = 158.2 → 158), locked by user 2026-05-19 follow-up.
  def card_height_px
    "158px"
  end

  # 314 px — diverge from ISO ID-1; widen by 25% (251 × 1.25 = 313.75 → 314) with the extra 63 px flowing entirely to the right column (left col stays 125 px fixed; right col auto-expands from 126 → 189 px).
  def card_width_px
    "314px"
  end

  # 105 px — 30% reduction of the prior 150 px (150 × 0.7 = 105).
  def avatar_dimension_px
    "105px"
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
    Formatting::CompactCount.call(channel[:subscriber_count])
  end

  def view_count_formatted
    Formatting::CompactCount.call(channel[:view_count])
  end

  def watch_hours_formatted
    Formatting::CompactHours.call(channel[:watch_hours])
  end
end
