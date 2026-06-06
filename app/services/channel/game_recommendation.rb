# frozen_string_literal: true

# Games a channel's content overlaps with — the **channel→game** direction.
#
# Design B: channels have no embedding of their own. A channel IS its videos, so
# this probes with the channel's **top videos by view count** (materialized in
# the polymorphic `stats` table) and, for each, finds the nearest games (cosine).
# Game hits are merged keeping the best (closest) distance per game. Bounded:
# `TOP_VIDEOS` probes × `GAMES_PER_VIDEO` neighbors — a handful of sub-ms HNSW
# lookups, no synthetic channel vector and no centroid blur.
#
# Returns an Array of `Result` structs (game, 0–100 score, cosine distance),
# ranked best-first, dropping games below `THRESHOLD_SCORE`.
#
# Nil channel / no embedded videos → `[]`. Games without an embedding are skipped.
class Channel
  class GameRecommendation
    DEFAULT_LIMIT   = 8
    THRESHOLD_SCORE = 25  # drop hits below this 0–100 score floor
    TOP_VIDEOS      = 10  # top videos by views used to probe games
    GAMES_PER_VIDEO = 8   # nearest games fetched per probe video

    Result = Struct.new(:game, :score, :distance, keyword_init: true)

    def self.call(channel, limit: DEFAULT_LIMIT)
      new(channel, limit: limit).call
    end

    def initialize(channel, limit: DEFAULT_LIMIT)
      @channel = channel
      @limit   = limit
    end

    def call
      return [] if @channel.nil?

      videos = probe_videos
      return [] if videos.empty?

      best = {} # game_id => smallest cosine distance across the probes
      videos.each do |video|
        nearest_games(video).each do |game|
          distance = game.neighbor_distance
          best[game.id] = distance if best[game.id].nil? || distance < best[game.id]
        end
      end
      return [] if best.empty?

      games = ::Game.where(id: best.keys).index_by(&:id)
      best
        .filter_map { |gid, dist| games[gid] && build_result(games[gid], dist) }
        .select { |result| result.score >= THRESHOLD_SCORE }
        .sort_by { |result| -result.score }
        .first(@limit)
    end

    private

    # Top videos by view count (materialized in `stats`) that actually have an
    # embedding — the probes for the channel's interests. COALESCE keeps videos
    # with no view stat (ordered last) so a channel still recommends something.
    def probe_videos
      @channel.videos
        .where.not(summary_embedding: nil)
        .joins(views_join)
        .order(Arel.sql("COALESCE(stats.value, 0) DESC"))
        .limit(TOP_VIDEOS)
    end

    def views_join
      "LEFT JOIN stats ON stats.entity_type = 'Video' " \
        "AND stats.entity_id = videos.id AND stats.kind = 'views'"
    end

    def nearest_games(video)
      ::Game
        .where.not(summary_embedding: nil)
        .nearest_neighbors(:summary_embedding, video.summary_embedding, distance: "cosine")
        .first(GAMES_PER_VIDEO)
    end

    def build_result(game, distance)
      score = ((1 - distance) * 100).round.clamp(0, 100)
      Result.new(game: game, score: score, distance: distance)
    end
  end
end
