# frozen_string_literal: true

class Genre < ApplicationRecord
  has_many :game_genres, dependent: :destroy
  has_many :games, through: :game_genres

  validates :igdb_id,
            presence: true,
            uniqueness: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true
end
