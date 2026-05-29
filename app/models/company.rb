# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :game_developers, dependent: :destroy
  has_many :game_publishers, dependent: :destroy
  has_many :developed_games, through: :game_developers, source: :game
  has_many :published_games, through: :game_publishers, source: :game

  validates :igdb_id,
            presence: true,
            uniqueness: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true
end
