# frozen_string_literal: true

# Materialize a Game's `views` stat as the sum of its linked
# videos' view counts.
#
# Video views live on the polymorphic `stats` table (`kind: "views"`),
# written by ImportVideosJob. A game has no view count of its own, so
# this recomputes it by summing the `views` stat across every video
# linked through `video_game_links` and upserts the result via
# `Pito::Stats.set` (kind `views`).
#
# Games with no linked videos (or whose videos carry no view stat) get
# a materialized value of 0 — distinguishing "computed, none" from
# "never computed" (no row).
#
# Invoked from `GameStatsRefreshJob`; enqueue it whenever the linked-video
# set or a linked video's view count changes (import / sync / link edit).
class Game
  class StatsRefresh
    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      Pito::Stats.set(@game, :views, total_linked_views)
    end

    private

    def total_linked_views
      Stat
        .where(entity_type: "Video", kind: "views")
        .where(entity_id: @game.linked_videos.select(:id))
        .sum(:value)
    end
  end
end
