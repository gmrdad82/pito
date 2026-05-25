# Game::DetailCoverComponent — cover image for the /games/:id show page.
#
# Wraps `shared/_igdb_cover` in the stable `.game-cover-detail` container
# that downstream Turbo Stream targets can replace.
#
# kwargs:
#   game: [Game] the game whose cover is rendered.
class Game::DetailCoverComponent < ViewComponent::Base
  def initialize(game:)
    @game = game
  end

  attr_reader :game

  def wrapper_dom_id
    "game_detail_cover_#{@game.id}"
  end
end
