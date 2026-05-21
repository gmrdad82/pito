# Phase 27 §01f — Owned-platforms chip list.
#
# Renders the list of platforms a Game is owned on as bracketed chips
# on the show page. Each chip links to the filtered
# `/games?filters=<slug>,owned` URL (the 01b filter row consumes this
# shape). Empty ownership renders a muted placeholder.
class Game
  class OwnedPlatformsChipListComponent < ViewComponent::Base
    def initialize(game:)
      @game = game
    end

    attr_reader :game

    # Alphabetical (locked per spec). Case-insensitive so "PS5" / "Steam"
    # / "epic" render stably regardless of capitalization.
    def owned_platforms
      @owned_platforms ||= game.owned_platforms.to_a.sort_by { |p| p.name.to_s.downcase }
    end

    def any?
      owned_platforms.any?
    end

    def filter_path_for(platform)
      # Filter token shape locked by Phase 27 01b: a comma-separated
      # list of platform-slug + scope tokens.
      helpers.games_path(filters: "#{platform.slug},owned")
    end
  end
end
