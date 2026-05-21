# Beta-3 Lane B (B2) — Game::GenresLineComponent.
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
#
# 2026-05-19 (Wave B) — when `game.resyncing?` is true the whole line
# renders as a `sync-indicator` dot-loader (`=---` cycling) so the
# stale, refreshing signal is visible at-a-glance. Phase offset is
# 0 (the canonical "first slot" in the staggered set across
# /games/:id — genre line is phase 0, kv-table date / dev / pub are
# 1 / 2 / 3, summary is back to 0).
class Game::GenresLineComponent < ViewComponent::Base
  # Canonical 4-frame cycle for the sync-indicator across /games/:id.
  # Each zone passes the same FRAMES with a different `phase_offset`
  # so the loaders read as a wave rather than a single pulse.
  SYNC_INDICATOR_FRAMES = [ "=---", "-=--", "--=-", "---=" ].freeze
  SYNC_INDICATOR_PHASE_OFFSET = 0

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

  def resyncing?
    @game.resyncing?
  end
end
