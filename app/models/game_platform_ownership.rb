# Phase 27 §1a — Game ↔ Platform ownership join.
#
# Replaces the single-valued `games.platform_owned_id` pointer with a
# multi-valued ownership join. A row in this table answers "the user
# owns this game on this platform" — no optional metadata. The editor
# revamp (2026-05-12) reduced the surface to a single bracketed
# checkbox per platform; the previous `acquired_at` / `store` / `notes`
# columns were dropped because nothing read or wrote them outside the
# editor itself.
#
# Cascade-on-delete from games (deleting a game wipes its ownership
# rows); restrict-on-delete from platforms (the IGDB platform sync
# never deletes — see `Platforms::SyncFromIgdb`).
#
# B7 (2026-05-25) — `play_on` flag.
#   Exactly ONE ownership row per game may have `play_on: true` at any
#   time (enforced by a partial unique DB index on `(game_id, play_on)
#   WHERE play_on = true`). The model-layer custom validation provides a
#   readable error at the application level as a secondary guard.
#
#   When the very first ownership for a game is created (no prior rows
#   exist before the insert), `play_on` is automatically set to `true`
#   via a `before_create` callback so the user always has a sensible
#   default without manual selection.
#
#   `Game#play_on_ownership` → the ownership with `play_on = true` (or nil).
#   `Game#play_on_platform`  → that ownership's platform (or nil).
class GamePlatformOwnership < ApplicationRecord
  # `belongs_to` is required by default (Rails 5+), so the row cannot
  # be saved without both sides. The explicit `uniqueness` validation
  # enforces "one ownership per (game, platform)" alongside the unique
  # composite DB index.
  belongs_to :game
  belongs_to :platform

  validates :platform_id, uniqueness: { scope: :game_id,
                                        message: "ownership already exists for this game" }

  # Application-level guard: at most one TRUE `play_on` per game.
  # The partial unique DB index is the authoritative constraint; this
  # validation surfaces a readable error before the DB layer raises.
  validate :at_most_one_play_on_per_game, if: :play_on?

  # Auto-set `play_on: true` when this is the first ownership for the
  # game (i.e. no existing rows before this insert). The check reads
  # `game_id` directly so it works even before the record is persisted.
  before_create :auto_set_play_on_for_first_ownership

  private

  def at_most_one_play_on_per_game
    conflicting = GamePlatformOwnership
                    .where(game_id: game_id, play_on: true)
                    .where.not(id: id)
    errors.add(:play_on, "is already set for another ownership of this game") if conflicting.exists?
  end

  def auto_set_play_on_for_first_ownership
    return if play_on?  # caller explicitly set it — honor that choice
    return unless game_id.present?

    first_for_game = !GamePlatformOwnership.where(game_id: game_id).exists?
    self.play_on = true if first_for_game
  end
end
