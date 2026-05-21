# Beta-3 Lane B (B4) — Game::BundlesSectionComponent.
#
# Extracts the inline `<section class="game-bundles">` block from
# `app/views/games/show.html.erb` (RIGHT pane, below the TTB fuel-gauge
# section, above the similar-games shelf) into a focused ViewComponent.
#
# Business rule (2026-05-18 DW slice — game show page bundles row):
#   - LEFT half  — bundles the game is a MEMBER OF (`game.bundles`,
#     alphabetized via `LOWER(name)`).
#   - RIGHT half — up to 3 `Bundle::SuggestedFor` recommendations
#     MINUS any bundle the game is already a member of (subtraction
#     happens HERE, not in the template, so a bundle the game is in
#     never leaks into the suggested row).
#   - Three render branches:
#       * both halves empty  → `shelf-empty-tile` "nothing yet" placeholder.
#       * LEFT only          → only `default`-mode tiles, no separator.
#       * RIGHT only         → cover-art separator tile FIRST, then
#                              `:suggest`-mode tiles. The CSS rule on
#                              `.game-bundles .shelf-row:has(.bundles-suggested-separator:first-child)`
#                              zeros the row gap so the separator butts
#                              against the pane edge.
#       * BOTH               → LEFT tiles + cover-art separator tile
#                              (`Game::BundlesSuggestedSeparatorComponent`)
#                              + RIGHT tiles. The old
#                              `.bundles-section-divider` vertical
#                              hairline is gone (2026-05-19).
#   - LEFT tiles render `Game::BundleTileComponent.new(bundle: …)` in
#     its default mode (anchor → layout-level bundles modal).
#   - RIGHT tiles render `Game::BundleTileComponent.new(bundle: …,
#     mode: :suggest, target_game: game)` so the click POSTs the game
#     into the bundle.
#   - `Bundle::SuggestedFor.call` is invoked with `limit: 3` — never
#     a higher value, even though the post-subtraction list may end up
#     shorter than 3.
#
# Out of scope (stays SIBLING of this section in `show.html.erb` so the
# native `<dialog>` does not nest inside interactive content):
#   - `games/_bundles_modal` partial.
#   - Per-bundle `ConfirmModalComponent` confirm-delete dialogs.
class Game
  class BundlesSectionComponent < ViewComponent::Base
    SUGGESTED_LIMIT = 3

    def initialize(game:)
      @game = game
    end

    # Bundles the game is currently a member of, alphabetized via the
    # same `LOWER(name)` ordering the inline template used.
    def bundles_in
      @bundles_in ||= @game.bundles.order(Arel.sql("LOWER(name)")).to_a
    end

    # Up to `SUGGESTED_LIMIT` `Bundle::SuggestedFor` recommendations
    # MINUS any bundle the game is already a member of (subtraction
    # lives here so the silent-failure-prone "a bundle the game is in
    # leaks into the right shelf" regression is caught by the component
    # spec).
    def bundles_suggested
      @bundles_suggested ||= (Bundle::SuggestedFor.call(@game, limit: SUGGESTED_LIMIT).to_a - bundles_in)
    end

    def both_empty?
      bundles_in.empty? && bundles_suggested.empty?
    end

    # 2026-05-19 — The cover-art separator tile renders whenever there
    # is a RIGHT half to introduce. When there is no LEFT half, the
    # separator becomes the first child of the shelf (CSS
    # `.game-bundles .shelf-row:has(.bundles-suggested-separator:first-child)`
    # zeros the row gap so it butts against the pane edge). When there
    # is a LEFT half, the separator sits between the two halves —
    # replacing the old vertical hairline (`.bundles-section-divider`)
    # that the template used to render.
    def render_separator?
      bundles_suggested.any?
    end

    private

    attr_reader :game
  end
end
