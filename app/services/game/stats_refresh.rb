# frozen_string_literal: true

# Materialize a Game's `views` and `likes` stats as the sums of its linked
# videos' counts.
#
# Video views/likes live on the polymorphic `stats` table (kinds "views" /
# "likes"), written by the video sync + snapshot passes. A game has no
# audience counters of its own, so this recomputes each as the sum across
# every video linked through `video_game_links` and upserts the results via
# `Pito::Stats.set` (the list surfaces read `Pito::Stats.get`, never
# live-sum at render).
#
# Games with no linked videos (or whose videos carry no stat rows) get a
# materialized value of 0 — distinguishing "computed, none" from "never
# computed" (no row), and guaranteeing a fully-unlinked game can't keep a
# stale non-zero aggregate.
#
# Invoked from `GameStatsRefreshJob`; enqueued whenever the linked-video set
# or a linked video's counts change (import / sync / snapshot / link edit).
class Game
  class StatsRefresh
    KINDS = %i[views likes].freeze

    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      KINDS.each do |kind|
        Pito::Stats.set(@game, kind, total_linked(kind))
      end
    end

    private

    def total_linked(kind)
      Stat
        .where(entity_type: "Video", kind: kind.to_s)
        .where(entity_id: @game.linked_videos.select(:id))
        .sum(:value)
    end
  end
end
