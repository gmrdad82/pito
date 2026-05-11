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
class GamePlatformOwnership < ApplicationRecord
  # `belongs_to` is required by default (Rails 5+), so the row cannot
  # be saved without both sides. The explicit `uniqueness` validation
  # enforces "one ownership per (game, platform)" alongside the unique
  # composite DB index.
  belongs_to :game
  belongs_to :platform

  validates :platform_id, uniqueness: { scope: :game_id,
                                        message: "ownership already exists for this game" }
end
