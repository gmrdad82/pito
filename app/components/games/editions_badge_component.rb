# Phase 28 §01a — `+N editions` badge.
#
# Renders next to a primary game's title on listing surfaces when the
# primary has at least one edition. Click target is the primary's show
# page anchored to `#editions`. Bracketed-link convention with no inner
# padding spaces (e.g. `[+2 editions]`). Renders NOTHING when the game
# is an edition or has no editions.
module Games
  class EditionsBadgeComponent < ViewComponent::Base
    # `bare: true` skips the surrounding `<a>` so the badge can render
    # safely INSIDE another link (e.g. the games `_tile.html.erb`
    # wraps the whole tile in an anchor — nesting a second anchor
    # would be invalid HTML). When bare, the bracketed text is still
    # rendered with the same `[+N editions]` shape; the outer link
    # carries the click target.
    def initialize(game:, bare: false)
      @game = game
      @bare = bare
    end

    attr_reader :game

    def render?
      game.primary? && editions_count.positive?
    end

    def editions_count
      @editions_count ||= game.editions.count
    end

    def label
      noun = I18n.t("games.editions_badge.noun", count: editions_count)
      I18n.t("games.editions_badge.label", count: editions_count, noun: noun)
    end

    def href
      helpers.game_path(game, anchor: "editions")
    end

    def bare?
      @bare
    end
  end
end
