# Phase 28 §01a — Editions sub-section on the primary's show page.
#
# Lists each edition with cover thumb, title, `version_title`, and the
# per-edition owned-platforms chip strip. Anchored `#editions`. Renders
# NOTHING when the game has no editions.
module Games
  class EditionsSectionComponent < ViewComponent::Base
    def initialize(game:)
      @game = game
    end

    attr_reader :game

    def render?
      game.primary? && editions.any?
    end

    def editions
      @editions ||= game.editions.order(:title)
    end

    def editions_count
      editions.size
    end

    def heading
      I18n.t("games.editions_section.heading", count: editions_count)
    end
  end
end
