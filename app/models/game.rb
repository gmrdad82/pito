# frozen_string_literal: true

class Game < ApplicationRecord
  belongs_to :primary_genre, class_name: "Genre", optional: true

  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres

  has_many :game_developers, dependent: :destroy
  has_many :developer_companies, through: :game_developers, source: :company

  has_many :game_publishers, dependent: :destroy
  has_many :publisher_companies, through: :game_publishers, source: :company

  has_many :game_platform_ownerships, dependent: :destroy
  has_many :video_game_links, dependent: :destroy
  has_many :linked_videos, through: :video_game_links, source: :video

  has_many :footages, dependent: :destroy

  has_neighbors :summary_embedding

  attribute :release_precision, :integer
  enum :release_precision,
       { day: 0, month: 1, quarter: 2, year: 3, tba: 4 },
       prefix: true

  validates :title, presence: true
end
