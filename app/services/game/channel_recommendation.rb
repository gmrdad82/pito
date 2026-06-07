# Channels best suited to a game — the **game→channel** direction.
#
# "Which of my channels suits this game/video?" Design B: a channel has no
# embedding of its own; it IS its videos and the games those videos are linked
# to. A channel's score for game `g` is the strongest of three signals:
#
#   K  — explicit link: the channel owns a video linked to `g`. Definitive,
#        human-asserted → LINK_SCORE (100), regardless of facets/embedding.
#   GG — composed game→game similarity: the best `Pito::Recommendation::
#        GameSimilarity.between(g, linked_game)` across the games the channel
#        already covers. THIS is the Dead Space hop — a never-recorded game
#        routes to the channel whose covered games are most like it.
#   E  — video-embedding cold-start fallback: the channel's video nearest `g`
#        (cosine), for relevant-but-not-yet-linked content.
#
#   channel_score = max(K, GG, E)
#
# Ranked best-first; no count cap. Below FLOOR is a "bad" score and dropped
# (unless `include_all:`). `limit:` optionally takes a top-N slice.
#
# `include_all: true` returns EVERY channel — ones with no relevant videos/links
# score 0 and sort last — so the user always sees their full channel slate.
class Game
  class ChannelRecommendation
    FLOOR      = Pito::Recommendation::Weights::FLOOR
    LINK_SCORE = Pito::Recommendation::Weights::LINK_SCORE

    Result = Struct.new(:channel, :score, :breakdown, keyword_init: true)

    def self.call(game, limit: nil, include_all: false)
      new(game, limit: limit, include_all: include_all).call
    end

    def initialize(game, limit: nil, include_all: false)
      @game        = game
      @limit       = limit
      @include_all = include_all
    end

    def call
      return [] if @game.nil?

      scores = Hash.new(0.0) # channel_id => best score so far (0–100 float)

      apply_embedding_signal(scores) # E
      apply_similarity_signal(scores) # GG
      linked_channel_ids.each { |cid| scores[cid] = LINK_SCORE.to_f } # K (definitive)

      channel_ids = @include_all ? ::Channel.pluck(:id) : scores.keys
      return [] if channel_ids.empty?

      channels = ::Channel.where(id: channel_ids).index_by(&:id)
      ranked = channel_ids.filter_map { |cid|
        channel = channels[cid] or next
        score = scores[cid].round
        next if !@include_all && score < FLOOR

        Result.new(channel: channel, score: score, breakdown: nil)
      }.sort_by { |result| [ -result.score, result.channel.id ] }

      @limit ? ranked.first(@limit) : ranked
    end

    private

    # E — best video-embedding similarity per channel.
    def apply_embedding_signal(scores)
      return if @game.summary_embedding.blank?

      embedded_videos.each do |video|
        e = Pito::Recommendation::Signals.embedding(video.neighbor_distance)
        scores[video.channel_id] = e if e > scores[video.channel_id]
      end
    end

    # GG — best composed game→game similarity between the target and each
    # channel's already-linked games.
    def apply_similarity_signal(scores)
      linked_games_by_channel.each do |channel_id, games|
        gg = games.map { |lg| Pito::Recommendation::GameSimilarity.between(@game, lg)[:score] }.max
        scores[channel_id] = gg if gg && gg > scores[channel_id]
      end
    end

    # Channel ids that own at least one video explicitly linked to this game.
    def linked_channel_ids
      ::Video
        .joins(:video_game_links)
        .where(video_game_links: { game_id: @game.id })
        .distinct
        .pluck(:channel_id)
    end

    # { channel_id => [linked Game, …] } across all channels' videos, with the
    # games' facets preloaded so `GameSimilarity.between` does no extra queries.
    def linked_games_by_channel
      pairs = ::VideoGameLink
        .joins(:video)
        .pluck(Arel.sql("videos.channel_id"), :game_id)
      return {} if pairs.empty?

      games = ::Game
        .where(id: pairs.map(&:last).uniq)
        .includes(:genres, :developer_companies, :publisher_companies)
        .index_by(&:id)

      pairs.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(channel_id, game_id), acc|
        game = games[game_id] and acc[channel_id] << game
      end
    end

    # All embedded videos, ordered nearest-first; grouped by channel above so
    # each channel surfaces on its best-matching video.
    def embedded_videos
      ::Video
        .where.not(summary_embedding: nil)
        .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
    end
  end
end
