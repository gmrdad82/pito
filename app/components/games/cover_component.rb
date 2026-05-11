# Phase 27 sub-spec 01e — explicit cover-art variant pipeline.
#
# Renders a Game cover-art image at one of two server-side sizes:
#
#   :grid   the existing all-games-grid tile size — 150 × 200 px,
#           sourced from the IGDB CDN's `t_cover_big` token
#           (264 × 374 native).
#   :shelf  the new shelf-row tile size — 98 × 130 px (65% of the
#           grid tile, per the addendum directive — see decision
#           below), sourced from IGDB's `t_cover_small_2x` token
#           (180 × 256 native, downsamples cleanly into the slot).
#
# The component owns the size mapping AND the CSS class name AND
# the `data-variant` attribute. Consumers (the all-games grid, the
# 01c Genres / Collections shelves, the 01d shelves-by-letter
# display mode) render this component instead of inlining
# `image_tag` calls — that way size changes happen in one place.
#
# # Size decision — `:shelf` at 65%
#
# The Phase 27 addendum
# (`docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`)
# locks: "try 50% first; if Claude Code judges 50% too small in
# practice — covers unreadable, cramped, titles printed on art lost
# — use 65–70% instead without asking." Concretely:
#
#   50% of 150 × 200 → 75 × 100 px. Below the legibility threshold
#                      for IGDB cover art — title overlays
#                      (Persona-style banners, sequel "II"
#                      subtitles, year stamps printed on art)
#                      disappear into noise at sub-90px widths.
#   65% of 150 × 200 → 97.5 × 130 → rounded to 98 × 130 px.
#                      Recognizable, dense, titles printed on art
#                      still legible. Matches the spec's locked
#                      ratio and the lower end of the addendum's
#                      fallback range.
#   70% of 150 × 200 → 105 × 140 px. Marginally larger; gains
#                      readability but loses ~14% horizontal
#                      density per shelf vs. 65%.
#
# Decision: **65%** (98 × 130). Recorded here, in the variant
# DIMENSIONS map below, and in the Phase 27 log.
class Games::CoverComponent < ViewComponent::Base
  # Variant → [width, height, IGDB size token, css modifier].
  #
  # Widths and heights are real pixel dimensions of the rendered
  # `<img>` slot. The IGDB token is the source asset key — the
  # browser receives a different URL per variant (different cache
  # key) instead of CSS-scaling one source asset. See the spec's
  # "Flaw" assertions: no inline `transform: scale`, no inline
  # `width: 65%` style emitted.
  DIMENSIONS = {
    grid: { width: 150, height: 200, igdb_size: "t_cover_big", css_modifier: "grid" },
    shelf: { width: 98, height: 130, igdb_size: "t_cover_small_2x", css_modifier: "shelf" }
  }.freeze

  VARIANTS = DIMENSIONS.keys.freeze

  def initialize(game:, variant: :grid, link_to_show: true)
    variant_sym = variant.to_sym
    unless DIMENSIONS.key?(variant_sym)
      raise ArgumentError,
            "Unknown cover variant #{variant.inspect} (expected one of #{VARIANTS.inspect})"
    end

    @game = game
    @variant = variant_sym
    @dim = DIMENSIONS.fetch(variant_sym)
    @link_to_show = link_to_show
  end

  attr_reader :game, :variant

  def width
    @dim[:width]
  end

  def height
    @dim[:height]
  end

  def igdb_size
    @dim[:igdb_size]
  end

  def css_classes
    "game-cover game-cover--#{@dim[:css_modifier]}"
  end

  def cover_url
    @game.cover_url(size: igdb_size)
  end

  def cover_present?
    cover_url.present?
  end

  def link_to_show?
    @link_to_show
  end

  # Theme-aware fallback SVG paths for the missing-cover case.
  #
  # Theme resolution in pito is client-side (localStorage + the
  # `<html data-theme=...>` attribute set by the head boot script and the
  # `theme` Stimulus controller — see `app/javascript/controllers/theme_controller.js`).
  # The server cannot reliably pick a single theme at render time because
  # the active value depends on a per-browser preference plus a system
  # media query the request never observes. We therefore emit BOTH
  # variants and let CSS pick the visible one via the
  # `.game-cover-fallback--{light,dark}` rule scoped on
  # `[data-theme="dark"]` (defined in `app/assets/tailwind/application.css`).
  def fallback_light_path
    helpers.image_path("game_cover_fallback_#{@dim[:css_modifier]}_light.svg")
  end

  def fallback_dark_path
    helpers.image_path("game_cover_fallback_#{@dim[:css_modifier]}_dark.svg")
  end

  # Friendly-URL aware path. `Game#to_param` returns `igdb_slug` when
  # present, falls back to `id.to_s` (see Game model). The
  # component intentionally goes through the URL helper rather than
  # hand-rolling `/games/#{slug}` so a future routing change
  # propagates cleanly.
  def game_path
    helpers.game_path(@game)
  end
end
