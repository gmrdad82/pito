# Phase 27 v2 spec 01 — Single main genre per Game (IGDB-order policy).
#
# Given a `Game`, returns a single canonical `Genre` so the `/games`
# Genres outer-shelf can list each game in exactly one sub-shelf. Before
# this picker landed (Phase 27 2026-05-11 follow-up), the shelf rendered
# each multi-genre game once per linked genre, which felt noisy
# ("Cyberpunk 2077 in adventure AND in rpg AND in shooter").
#
# Rules, applied top-down — first match wins:
#
#   1. `game.primary_genre_id` is set → return that Genre directly.
#      Pinning is honored end-to-end so a manual override (future
#      surface — Phase 27 follow-up) wins over inference.
#   2. The game has at least one linked genre → return the IGDB-order
#      winner. IGDB's per-game genre array order IS the primacy order
#      (the first array entry is the canonical primary). The
#      `game_genres.position` column captures that ordering at sync
#      time (see `Game::Igdb::SyncGame#sync_genres`).
#
#      Tie-break (in priority order):
#        a. `game_genres.position ASC NULLS LAST`
#        b. `LOWER(genres.name) ASC`
#        c. `genres.id ASC`
#
#      `NULLS LAST` keeps rows with a recorded IGDB position ahead of
#      legacy rows (pre-2026-05-17 migration) whose `position` is
#      NULL. The alphabetical secondary key only fires when EVERY row
#      in `game_genres` for this game has `position IS NULL` (the
#      legacy state) OR when two rows somehow share the same integer
#      position (defensive — IGDB does not duplicate).
#
#      User-feedback example (Mandragora, IGDB → Role-playing /
#      Adventure / Indie): with positions [0, 1, 2] the picker
#      returns "Role-playing" (position 0). Without positions (legacy
#      pre-resync), it falls back to "Adventure" (alphabetical).
#
#   3. The game has zero linked genres → return `nil`. The shelf
#      partial then drops the game from every sub-shelf (correct
#      behavior — there's no genre to file it under).
#
# Tie-break (LOCKED — Phase 27 v2 spec 01, "Behavior contracts"):
#
#   ORDER BY game_genres.position ASC NULLS LAST,
#            LOWER(genres.name) ASC,
#            genres.id ASC
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
#   - `nil` input: returns `nil` (does not raise). Pins the existing
#     defensive behavior so the model `before_save` hook and the IGDB
#     sync re-pick path can both call `pick(game)` without an extra
#     nil guard.
#   - Legacy rows where every `game_genres.position` is NULL: the
#     alphabetical secondary key drives the choice. These rows keep
#     their pre-2026-05-17 primary until the next user-triggered
#     re-sync repopulates `position` for them.
class Game
  class PrimaryGenrePicker
    # Returns one `Genre` instance or `nil`. Does NOT persist anything;
    # callers (model `before_save`, IGDB sync orchestrator, backfill
    # migration, rake task) write `primary_genre_id` explicitly when
    # they want the pick recorded.
    def pick(game)
      return nil if game.nil?

      pinned = pinned_primary(game)
      return pinned if pinned

      # `game.genres` is `through: :game_genres`. The position column
      # lives on `game_genres`, so we must order via the join — Rails
      # already constructs the JOIN under the through-association, the
      # raw SQL just names the join column. `NULLS LAST` keeps rows with
      # an IGDB-derived position ahead of legacy NULL-position rows.
      # `Arel.sql` is required so Rails 7+ does not reject the SQL
      # expression as an unsafe ORDER value.
      game.genres
          .order(Arel.sql("game_genres.position ASC NULLS LAST, LOWER(genres.name) ASC, genres.id ASC"))
          .first
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
