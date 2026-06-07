# Channels a game's content overlaps with — the **game→channel** direction.
#
# Design B: channels have no embedding of their own. A channel IS its videos, so
# a channel matches a game on TWO signals, whichever is stronger:
#
#   1. Explicit link — a video the channel owns is linked to the game
#      (`video_game_links`). This is a definitive, human-asserted match, so it
#      scores 100 regardless of embedding proximity.
#   2. Semantic proximity — the channel's VIDEO nearest (cosine) to the game's
#      `summary_embedding`. The channel's best (closest) video is its score.
#
# Per channel we keep the better of the two (a linked channel is pinned at 100).
#
# Returns an Array of `Result` structs (channel, 0–100 score, cosine distance),
# ranked best-first. There is no count cap — every channel scoring at or above
# `THRESHOLD_SCORE` is returned, each rendering its own ScoreBarComponent.
# Below the floor is just a "bad" score (mirrors the game-score tiers where 25
# is the worst meaningful tier), so it's dropped. Score maps distance via
# `((1 - distance) * 100)`.
#
# `limit:` is optional — nil (default) returns all qualifying channels; pass an
# Integer only when a caller deliberately wants a top-N slice.
#
# Videos without an embedding are skipped by the semantic path (but still count
# via an explicit link). A game with no embedding AND no links → `[]`.
class Game
  class ChannelRecommendation
    THRESHOLD_SCORE = 25 # drop hits below this 0–100 score floor ("bad")
    LINKED_DISTANCE = 0.0 # explicit video→game link → perfect match (score 100)

    Result = Struct.new(:channel, :score, :distance, keyword_init: true)

    def self.call(game, limit: nil)
      new(game, limit: limit).call
    end

    def initialize(game, limit: nil)
      @game  = game
      @limit = limit
    end

    def call
      return [] if @game.nil?

      best = {} # channel_id => smallest cosine distance among its videos

      if @game.summary_embedding.present?
        embedded_videos.each do |video|
          distance = video.neighbor_distance
          if best[video.channel_id].nil? || distance < best[video.channel_id]
            best[video.channel_id] = distance
          end
        end
      end

      # Channels with a video explicitly linked to this game are definitive
      # matches — pin them at distance 0 (score 100), beating any embedding score.
      linked_channel_ids.each { |cid| best[cid] = LINKED_DISTANCE }

      return [] if best.empty?

      channels = ::Channel.where(id: best.keys).index_by(&:id)
      ranked = best
        .filter_map { |cid, dist| channels[cid] && build_result(channels[cid], dist) }
        .select { |result| result.score >= THRESHOLD_SCORE }
        .sort_by { |result| -result.score }
      @limit ? ranked.first(@limit) : ranked
    end

    private

    # Channel ids that own at least one video explicitly linked to this game.
    def linked_channel_ids
      ::Video
        .joins(:video_game_links)
        .where(video_game_links: { game_id: @game.id })
        .distinct
        .pluck(:channel_id)
    end

    # All embedded videos, ordered nearest-first, grouped by channel above so
    # every channel surfaces on its best-matching video. No pool cap: a cap
    # could hide a channel whose closest video falls outside the top-N. (At
    # scale this could move to a DISTINCT ON (channel_id) query.)
    def embedded_videos
      ::Video
        .where.not(summary_embedding: nil)
        .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
    end

    def build_result(channel, distance)
      score = ((1 - distance) * 100).round.clamp(0, 100)
      Result.new(channel: channel, score: score, distance: distance)
    end
  end
end
