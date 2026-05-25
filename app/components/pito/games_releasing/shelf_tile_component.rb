module Pito
  module GamesReleasing
    # Pito::GamesReleasing::ShelfTileComponent — one tile in the
    # `Pito::GamesReleasingPanelComponent`'s horizontal "upcoming games" shelf.
    #
    # ## Layout (top-to-bottom)
    #
    #   - Cover art — `Game::CoverComponent` `:shelf_fill` variant.
    #   - Title — `.upcoming-tile__title`, single-line + `text-overflow: ellipsis`.
    #   - Relative time-to-release — compact "in Nd" / "in Nw" string.
    #
    # ## Focusables
    #
    # Each tile carries `data-tui-focusable="upcoming_<id>"` so the
    # `tui-cursor` controller's j/k focus-list traversal advances
    # left-to-right across the shelf row.
    class ShelfTileComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      attr_reader :game

      def focusable_key
        "upcoming_#{game.id}"
      end

      def game_path
        helpers.game_path(game)
      end

      def time_until_release
        return nil if game.release_date.blank?
        helpers.in_time_until(game.release_date)
      end
    end
  end
end
