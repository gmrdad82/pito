# Phase 14 §1 — Game ↔ Company (developer role) join.
class GameDeveloper < ApplicationRecord
  belongs_to :game
  belongs_to :company

  validates :game_id, uniqueness: { scope: :company_id }
end
