# Phase 28 §01a — version-parent typeahead picker.
#
# Renders on the game edit page. Stimulus-driven typeahead:
#   - Search input the user types into.
#   - Hidden input carries the resolved `version_parent_id` (integer)
#     submitted with the form.
#   - `[detach]` bracketed link clears the value to nil.
#
# The picker is DISABLED when the current game has editions (a row
# with children cannot itself become an edition — single-level
# nesting locked in the umbrella plan). Server-side validation
# enforces the same guard.
#
# Source list comes from `GET /games/search?q=...` — primaries only,
# title-only ILIKE, capped at 20 results (architect lean #2 locked).
class Game
  class VersionParentPickerComponent < ViewComponent::Base
    def initialize(game:, form:)
      @game = game
      @form = form
    end

    attr_reader :game, :form

    def disabled?
      game.persisted? && Game.where(version_parent_id: game.id).exists?
    end

    def current_parent
      @current_parent ||= game.version_parent
    end

    def current_parent_id
      current_parent&.id
    end

    def current_parent_title
      current_parent&.title.to_s
    end

    def search_url
      helpers.version_parent_search_games_path
    end
  end
end
