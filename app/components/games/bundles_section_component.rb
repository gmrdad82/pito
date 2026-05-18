# Beta-3 Lane B (B4) — Games::BundlesSectionComponent.
#
# Extracts the inline `<section class="game-bundles">` block from
# `app/views/games/show.html.erb` (RIGHT pane, below the TTB fuel-gauge
# section, above the similar-games shelf) into a focused ViewComponent.
#
# Business rule (2026-05-18 DW slice — game show page bundles row):
#   - LEFT half  — bundles the game is a MEMBER OF (`game.bundles`,
#     alphabetized via `LOWER(name)`).
#   - RIGHT half — up to 3 `Bundles::SuggestedFor` recommendations
#     MINUS any bundle the game is already a member of (subtraction
#     happens HERE, not in the template, so a bundle the game is in
#     never leaks into the suggested row).
#   - Three render branches:
#       * both halves empty  → `shelf-empty-tile` "nothing yet" placeholder.
#       * LEFT only          → only `default`-mode tiles, NO divider.
#       * RIGHT only         → only `:suggest`-mode tiles, NO divider.
#       * BOTH               → LEFT tiles + `.bundles-section-divider`
#                              + RIGHT tiles.
#   - LEFT tiles render `Games::BundleTileComponent.new(bundle: …)` in
#     its default mode (anchor → layout-level bundles modal).
#   - RIGHT tiles render `Games::BundleTileComponent.new(bundle: …,
#     mode: :suggest, target_game: game)` so the click POSTs the game
#     into the bundle.
#   - `Bundles::SuggestedFor.call` is invoked with `limit: 3` — never
#     a higher value, even though the post-subtraction list may end up
#     shorter than 3.
#
# Out of scope (stays SIBLING of this section in `show.html.erb` so the
# native `<dialog>` does not nest inside interactive content):
#   - `games/_bundles_modal` partial.
#   - Per-bundle `ConfirmModalComponent` confirm-delete dialogs.
module Games
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

    # Up to `SUGGESTED_LIMIT` `Bundles::SuggestedFor` recommendations
    # MINUS any bundle the game is already a member of (subtraction
    # lives here so the silent-failure-prone "a bundle the game is in
    # leaks into the right shelf" regression is caught by the component
    # spec).
    def bundles_suggested
      @bundles_suggested ||= (Bundles::SuggestedFor.call(@game, limit: SUGGESTED_LIMIT).to_a - bundles_in)
    end

    def both_empty?
      bundles_in.empty? && bundles_suggested.empty?
    end

    def render_divider?
      bundles_in.any? && bundles_suggested.any?
    end

    private

    attr_reader :game
  end
end
