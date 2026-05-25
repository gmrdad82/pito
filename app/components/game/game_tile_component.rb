# Game::GameTileComponent — rich game tile for the /games grid and shelf rows.
#
# kwargs:
#   game:    [Game]   the game to render.
#   variant: [:grid, :shelf] default :grid. Controls caption typography;
#            cover slot stays 150 × 200 px in both variants.
class Game
  class GameTileComponent < ViewComponent::Base
    VARIANTS = %i[grid shelf].freeze

    def initialize(game:, variant: :grid)
      @game = game
      @variant = variant.to_sym

      unless VARIANTS.include?(@variant)
        raise ArgumentError,
              "Unknown variant #{variant.inspect} (expected one of #{VARIANTS.inspect})"
      end
    end

    private

    attr_reader :game, :variant

    # A game is "not yet released" when its `release_date` is nil OR in
    # the future. The title renders bold via `.not-released` at a glance.
    def not_released?
      game.release_date.blank? || game.release_date > Date.current
    end

    def caption_font_size
      variant == :shelf ? "10px" : "11px"
    end

    def meta_font_size
      variant == :shelf ? "9px" : "10px"
    end

    # Phase 28 §01a — show muted parent pointer on edition tiles.
    def parent_pointer
      return nil unless game.edition?
      game.version_parent
    end

    def show_editions_badge?
      game.primary?
    end

    def game_path
      helpers.game_path(game)
    end
  end
end
