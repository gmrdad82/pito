# frozen_string_literal: true

class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game

  has_neighbors :summary_embedding

  attribute :privacy_status, :integer
  enum :privacy_status,
       { private: 0, public: 1, unlisted: 2 },
       prefix: true

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
