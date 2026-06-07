# frozen_string_literal: true

class VideoGameLink < ApplicationRecord
  belongs_to :video
  belongs_to :game

  validates :video_id, uniqueness: { scope: :game_id }

  # P4 — keep the game's materialized `views` stat (sum of linked-video
  # views) in sync when the link set changes.
  after_commit :enqueue_game_stats_refresh, on: %i[create destroy]

  private

  def enqueue_game_stats_refresh
    GameStatsRefreshJob.perform_later(game_id)
  end
end
