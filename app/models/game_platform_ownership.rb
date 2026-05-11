# Phase 27 §1a — Game ↔ Platform ownership join.
#
# Replaces the single-valued `games.platform_owned_id` pointer with a
# multi-valued ownership join. A row in this table answers "the user
# owns this game on this platform"; optional metadata records when /
# where / why (acquired_at, store, notes).
#
# Cascade-on-delete from games (deleting a game wipes its ownership
# rows); restrict-on-delete from platforms (the IGDB platform sync
# never deletes — see `Platforms::SyncFromIgdb`).
class GamePlatformOwnership < ApplicationRecord
  belongs_to :game
  belongs_to :platform

  validates :game_id, presence: true
  validates :platform_id, presence: true,
                          uniqueness: { scope: :game_id,
                                        message: "ownership already exists for this game" }
end
