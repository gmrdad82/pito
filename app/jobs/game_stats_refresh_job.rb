# frozen_string_literal: true

# Recompute a Game's materialized `views` stat (sum of its linked
# videos' views) off the request path.
#
# Enqueue whenever the linked-video set or a linked video's view count
# changes (video import, IGDB sync, link add/remove). A missing game is
# a no-op so a stale enqueue after a delete never raises.
class GameStatsRefreshJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Game::StatsRefresh.call(game)
  end
end
