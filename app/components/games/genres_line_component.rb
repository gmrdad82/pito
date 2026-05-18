# Beta-3 Lane B (B2) — Games::GenresLineComponent.
#
# Extracts the inline `<div class="game-genres">` block from
# `app/views/games/show.html.erb` (the primary-bold + up-to-2 secondaries
# + em-dash empty fallback business rule) into a focused ViewComponent.
#
# Business rule (Wave C2 spec 08 §"Genres"):
#   - `primary` = `game.primary_genre` (can be nil).
#   - `secondaries` = `game.genres` MINUS `primary`, ordered by `name`,
#     capped at 2.
#   - Composite list is `[primary, *secondaries].compact` — so at most
#     3 tokens render (1 primary + 2 secondaries).
#   - First token renders in `<strong>`, the rest plain.
#   - Separator between tokens is ` · ` (space-dot-space).
#   - Empty composite (no primary AND no secondaries) renders a muted
#     `<em>—</em>` fallback.
#
# Labels flow through `GenresHelper#genre_display_name` (handles the
# `GENRE_DISPLAY_RENAMES` cosmetic-rename table) — IGDB names render
# verbatim except for the renames declared there.
class Games::GenresLineComponent < ViewComponent::Base
  def initialize(game:)
    @game = game
  end

  attr_reader :game

  # The composite list rendered between `<strong>` (first) and plain
  # spans (rest), separated by ` · `. Empty when the game has no
  # primary_genre AND no secondaries.
  def genres_list
    @genres_list ||= ([ primary ] + secondaries.to_a).compact
  end

  def primary
    @primary ||= @game.primary_genre
  end

  # `Genre` association MINUS the primary, alphabetical, capped at 2.
  # Matches the inline query the source template ran.
  def secondaries
    @secondaries ||= @game.genres
                          .where.not(id: primary&.id)
                          .order(:name)
                          .limit(2)
  end
end
