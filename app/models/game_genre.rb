# Phase 14 §1 — Game ↔ Genre join.
class GameGenre < ApplicationRecord
  belongs_to :game
  belongs_to :genre

  validates :game_id, uniqueness: { scope: :genre_id }

  # Phase 27 follow-up (2026-05-11) — keep `games.primary_genre_id`
  # fresh when the join changes. `game.genres << g` and `game.genres
  # = [...]` flow through `GameGenre.create` / `destroy` (NOT through
  # `Game#save`), so the Game model's `before_save` hook does NOT
  # fire. These callbacks re-run the picker on the parent game when
  # its genre membership changes.
  #
  # `after_save` + `after_destroy` (NOT the `_commit` variants) so the
  # callback fires inside the surrounding transaction. RSpec wraps
  # every test in a transaction that never commits, so the `_commit`
  # callbacks would never fire under test — the production code path
  # behaves identically because IGDB sync calls `game.genres << g`
  # inside a `transaction do … end` block which DOES commit.
  #
  # The `unless game.primary_genre_id.present?` guard short-circuits
  # when a pin is already in place — repeated `<<` adds on the same
  # game do not thrash the pin.
  after_save    :recompute_primary_genre, if: :game
  after_destroy :recompute_primary_genre, if: :game

  private

  def recompute_primary_genre
    g = game
    return if g.nil?
    # Reload so `g.genres` reflects the freshly-committed join state
    # (avoid relying on in-memory association caches).
    g.reload
    # Honor an explicit pin — re-running the picker would never pick
    # the same row twice in a row, but we also do not want to
    # silently re-pick on every `game.genres << x` when the operator
    # has chosen a primary in the future surface.
    return if g.primary_genre_id.present?
    pick = Games::PrimaryGenrePicker.new.pick(g)
    new_id = pick&.id
    return if new_id.nil?
    g.update_column(:primary_genre_id, new_id)
  end
end
