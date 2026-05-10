# Phase 14 §1 — IGDB-sourced company reference table.
#
# One Company row per IGDB company. Role flags (developer / publisher
# / porting / supporting) live on the join — `GameDeveloper` /
# `GamePublisher` — not on the entity, mirroring IGDB's
# `involved_companies` shape.
class Company < ApplicationRecord
  has_many :game_developers, dependent: :destroy
  has_many :game_publishers, dependent: :destroy
  has_many :developed_games, through: :game_developers, source: :game
  has_many :published_games, through: :game_publishers, source: :game

  validates :igdb_id, presence: true, uniqueness: true,
                      numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true, length: { maximum: 255 }
end
