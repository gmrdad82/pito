# Phase 14 §1 — Game ↔ Platform join.
#
# `platforms_available` on Game routes through this join. The
# `platform_owned_id` on Game is a separate FK (single-valued
# "platform the user owns the copy on"); this join carries the
# multi-valued "platforms the game ships on" set.
class GamePlatform < ApplicationRecord
  belongs_to :game
  belongs_to :platform

  validates :game_id, uniqueness: { scope: :platform_id }
end
