# frozen_string_literal: true

class VideoGameLink < ApplicationRecord
  belongs_to :video
  belongs_to :game

  validates :video_id, uniqueness: { scope: :game_id }
end
