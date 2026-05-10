# Phase 14 §1 — Game ↔ Company (publisher role) join.
class GamePublisher < ApplicationRecord
  belongs_to :game
  belongs_to :company

  validates :game_id, uniqueness: { scope: :company_id }
end
