# Phase 14 §1 — IGDB-sourced genre reference table.
#
# Thin row keyed by `igdb_id`. Populated lazily as games reference
# new genres during sync.
class Genre < ApplicationRecord
  has_many :game_genres, dependent: :destroy
  has_many :games, through: :game_genres

  validates :igdb_id, presence: true, uniqueness: true,
                      numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true, length: { maximum: 255 }
end
