# Phase 14 §1 — IGDB-sourced platform reference table.
#
# Thin row keyed by `igdb_id`. Populated lazily as games reference
# new platforms during sync. The `Game.platform_owned` association
# points to a row in this table (local-only — survives re-sync).
class Platform < ApplicationRecord
  has_many :game_platforms, dependent: :destroy
  has_many :games, through: :game_platforms
  has_many :games_owning, class_name: "Game", foreign_key: :platform_owned_id,
                          dependent: :nullify, inverse_of: :platform_owned

  validates :igdb_id, presence: true, uniqueness: true,
                      numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true, length: { maximum: 255 }
end
