# Channels a game's content overlaps with — the **game→channel** direction.
#
# Design B: channels have no embedding of their own. A channel IS its videos, so
# this finds the VIDEOS nearest (cosine) to the game's `summary_embedding`, then
# groups them by `channel_id` — the channel's best (closest) video is its score.
# One HNSW query over videos + an in-memory group; no synthetic channel vector,
# and a channel covering many games surfaces on whichever video matches (no
# centroid blur).
#
# Returns an Array of `Result` structs (channel, 0–100 score, cosine distance),
# ranked best-first, dropping channels below `THRESHOLD_SCORE`. The score maps
# distance via `((1 - distance) * 100)`.
#
# Empty / unembedded game → `[]`. Videos without an embedding are skipped.
class Game
  class ChannelRecommendation
    DEFAULT_LIMIT   = 8
    THRESHOLD_SCORE = 25  # drop hits below this 0–100 score floor
    VIDEO_POOL      = 50  # nearest videos scanned before grouping by channel

    Result = Struct.new(:channel, :score, :distance, keyword_init: true)

    def self.call(game, limit: DEFAULT_LIMIT)
      new(game, limit: limit).call
    end

    def initialize(game, limit: DEFAULT_LIMIT)
      @game  = game
      @limit = limit
    end

    def call
      return [] if @game.nil?
      return [] if @game.summary_embedding.blank?

      best = {} # channel_id => smallest cosine distance among its videos
      nearest_videos.each do |video|
        distance = video.neighbor_distance
        if best[video.channel_id].nil? || distance < best[video.channel_id]
          best[video.channel_id] = distance
        end
      end
      return [] if best.empty?

      channels = ::Channel.where(id: best.keys).index_by(&:id)
      best
        .filter_map { |cid, dist| channels[cid] && build_result(channels[cid], dist) }
        .select { |result| result.score >= THRESHOLD_SCORE }
        .sort_by { |result| -result.score }
        .first(@limit)
    end

    private

    def nearest_videos
      ::Video
        .where.not(summary_embedding: nil)
        .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
        .first(VIDEO_POOL)
    end

    def build_result(channel, distance)
      score = ((1 - distance) * 100).round.clamp(0, 100)
      Result.new(channel: channel, score: score, distance: distance)
    end
  end
end
