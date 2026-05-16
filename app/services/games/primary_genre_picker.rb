# Phase 27 v2 spec 01 — Single main genre per Game.
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
#   2. The game has at least one linked genre → return the
#      alphabetical winner, case-insensitive, tie-broken by `id`.
#      Stable, deterministic, locale-independent (ASCII collation),
#      and re-evaluable on every IGDB re-sync — the same multi-genre
#      set always yields the same primary pick across requests. We
#      deliberately do NOT follow IGDB's per-game genre array order:
#      IGDB does not document a "most-significant-first" ordering for
#      that array, so trusting it would silently reshuffle the shelf
#      on every re-sync.
#   3. The game has zero linked genres → return `nil`. The shelf
#      partial then drops the game from every sub-shelf (correct
#      behavior — there's no genre to file it under).
#
# Tie-break (LOCKED — Phase 27 v2 spec 01, "Behavior contracts"):
#
#   ORDER BY LOWER(genres.name) ASC, genres.id ASC
#
# The case-insensitive primary key plus the integer-id secondary key
# guarantee a single deterministic winner even when two genres differ
# only in case (`"Action"` vs `"action"` vs `"ACTION"`). Without the
# secondary key, the choice between equal-lowercase genres would be
# left to the database's row order — undefined and unstable across
# Postgres versions / vacuum states.
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
module Games
  class PrimaryGenrePicker
    # Returns one `Genre` instance or `nil`. Does NOT persist anything;
    # callers (model `before_save`, IGDB sync orchestrator, backfill
    # migration, rake task) write `primary_genre_id` explicitly when
    # they want the pick recorded.
    def pick(game)
      return nil if game.nil?

      pinned = pinned_primary(game)
      return pinned if pinned

      # LOWER(name) ASC primary, id ASC secondary — the locked
      # tie-break. `Arel.sql` is used so Rails 7+ does not reject the
      # SQL expression as an unsafe ORDER value.
      game.genres
          .order(Arel.sql("LOWER(genres.name) ASC, genres.id ASC"))
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
