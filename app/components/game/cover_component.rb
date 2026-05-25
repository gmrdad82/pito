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
# Genres / Bundles shelves) render this component instead of
# inlining `image_tag` calls — that way size changes happen in one
# place.
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
class Game::CoverComponent < ViewComponent::Base
  # Variant → [width, height, IGDB size token, css modifier].
  #
  # Widths and heights are real pixel dimensions of the rendered
  # `<img>` slot. The IGDB token is the source asset key — the
  # browser receives a different URL per variant (different cache
  # key) instead of CSS-scaling one source asset. See the spec's
  # "Flaw" assertions: no inline `transform: scale`, no inline
  # `width: 65%` style emitted.
  # 2026-05-25 — `:shelf_fill` variant. Unlike `:grid` / `:shelf` which
  # render at fixed pixel dimensions, this variant lets the surrounding
  # container drive the rendered height while a CSS `aspect-ratio: 3 / 4`
  # rule keeps the 3:4 cover proportion intact. Used by
  # `Pito::GamesReleasing::ShelfTileComponent` so the upcoming-games
  # shelf cover art fills the available tile height (which the home-grid
  # row computes dynamically per viewport) without needing the panel
  # to know the exact pixel value.
  #
  # `width` / `height` HTML attrs are omitted for `:shelf_fill` (the
  # `<img>` is sized by CSS `height: 100%; width: auto`). The IGDB
  # source token stays `t_cover_big_2x` so the asset has enough native
  # resolution to fill larger tile heights without softening.
  DIMENSIONS = {
    grid: { width: 150, height: 200, igdb_size: "t_cover_big", css_modifier: "grid" },
    shelf: { width: 98, height: 130, igdb_size: "t_cover_small_2x", css_modifier: "shelf" },
    shelf_fill: { width: nil, height: nil, igdb_size: "t_cover_big_2x", css_modifier: "shelf-fill" }
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

  # Phase 27 follow-up (2026-05-17) — prefer the normalized local
  # master (`/covers/games/<id>/master.jpg`) over the IGDB CDN. Falls back to
  # the IGDB URL at the variant's source token when the master is
  # missing (not yet normalized). The size mapping for the IGDB
  # fallback is preserved per-variant so behavior is unchanged for
  # rows the normalizer has not touched yet.
  def cover_url
    @game.cover_master_url(fallback_size: igdb_size)
  end

  def cover_present?
    cover_url.present?
  end

  def link_to_show?
    @link_to_show
  end

  # Fallback SVG path for the missing-cover case.
  #
  # Pito is single-theme (dark) — the previous dual light/dark emission
  # was removed alongside the theme system. The `_dark` suffix in the
  # asset filename is preserved as the canonical asset name.
  #
  # 2026-05-25 — `:shelf_fill` reuses the existing `shelf` SVG (CSS
  # `aspect-ratio: 3 / 4` + `height: 100%` stretches it to whatever
  # height the surrounding tile resolves to). Avoids shipping a
  # second visually identical asset.
  def fallback_path
    asset_modifier = (variant == :shelf_fill) ? "shelf" : @dim[:css_modifier]
    helpers.image_path("game_cover_fallback_#{asset_modifier}_dark.svg")
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
