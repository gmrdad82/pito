# Phase 27 follow-up (2026-05-11) — primary-genre picker.
#
# Given a `Game`, returns a single canonical `Genre` so the `/games`
# Genres outer-shelf can list each game in exactly one sub-shelf. Before
# this picker landed, the shelf rendered each multi-genre game once per
# linked genre, which felt noisy ("Cyberpunk 2077 in adventure AND in
# rpg AND in shooter").
#
# Rules, applied top-down — first match wins:
#
#   1. `game.primary_genre_id` is set → return that Genre directly.
#      Pinning is honored end-to-end so a manual override (future
#      surface — Phase 27 follow-up) wins over inference.
#   2. The game has at least one linked genre → return the first row
#      from `game.genres.order(:name)`. Alphabetical by canonical IGDB
#      name is deterministic, locale-independent (ASCII collation), and
#      stable across re-syncs — the same multi-genre set always yields
#      the same primary pick across requests. We deliberately do NOT
#      follow IGDB's per-game genre array order: IGDB does not document
#      a "most-significant-first" ordering for that array, so trusting
#      it would silently reshuffle the shelf on every re-sync.
#   3. The game has zero linked genres → return `nil`. The shelf
#      partial then drops the game from every sub-shelf (correct
#      behavior — there's no genre to file it under).
#
# Edge cases:
#   - Genre deleted mid-flight (pinned primary FK is `on_delete:
#     :nullify`). Rule 1 still fires on a `primary_genre_id` value, but
#     the dereferenced association is `nil`. The picker falls through
#     to rule 2 in that case.
#   - Soft-deleted / scoped-out genres: this picker reads the bare
#     `game.genres` association — there are no default scopes on
#     `Genre`, so this is moot today. If a scope is added later, callers
#     should be aware that the picker honors it.
module Games
  class PrimaryGenrePicker
    # Returns one `Genre` instance or `nil`. Does NOT persist anything;
    # callers (model `before_save`, rake task) write `primary_genre_id`
    # explicitly when they want the pick recorded.
    def pick(game)
      return nil if game.nil?

      pinned = pinned_primary(game)
      return pinned if pinned

      game.genres.order(:name).first
    end

    private

    # Rule 1: explicit pin. Reads through the association so the picker
    # gracefully handles a stale `primary_genre_id` pointing at a row
    # that has since been nullified (returns nil → falls through to
    # rule 2 above).
    def pinned_primary(game)
      return nil if game.primary_genre_id.blank?
      game.primary_genre
    end
  end
end
