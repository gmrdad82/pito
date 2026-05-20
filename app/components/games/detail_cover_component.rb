# Beta-3 Lane B (B1) — Games::DetailCoverComponent.
#
# Extracts the inline cover + platform-chip overlay block from
# `app/views/games/show.html.erb` (the wrapper `.game-cover-detail`
# + the slug computation + the bottom-right chip overlay strip) into
# a focused ViewComponent.
#
# The outer wrapper carries the stable DOM id
# `game_detail_cover_<id>` so a future ownership-toggle Turbo Stream
# flow (the breadcrumb `[+ platform]` / ownership editor) can broadcast
# a single replace targeting this element.
#
# Slug computation mirrors the inline block it replaces verbatim — it
# walks `PlatformChipsHelper::KNOWN_CHIPS` (locked order: ps, switch,
# steam) and selects each slug appearing in either
# `game_detail_chip_slugs(game)` or
# `Array(game_index_tile_chip_slug(game))`. Walking `KNOWN_CHIPS`
# (instead of the helper's own ordered output) is what guarantees the
# detail-row chip order matches the shelf-tile order.
#
# The shared `shared/_igdb_cover` partial stays untouched — it has
# other consumers; only the wrapper + overlay live here.
class Games::DetailCoverComponent < ViewComponent::Base
  def initialize(game:)
    @game = game
  end

  attr_reader :game

  # Ordered slug list used by the chip-overlay loop. Empty when no
  # `KNOWN_CHIPS` slug applies to the game (overlay is suppressed in
  # that case — see the template).
  def detail_chip_slugs
    @detail_chip_slugs ||= PlatformChipsHelper::KNOWN_CHIPS.select do |slug|
      (helpers.game_detail_chip_slugs(@game) +
        Array(helpers.game_index_tile_chip_slug(@game))).include?(slug)
    end
  end

  def wrapper_dom_id
    "game_detail_cover_#{@game.id}"
  end
end
