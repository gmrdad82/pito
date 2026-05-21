# Phase 34+ (2026-05-19) — Channels a game's audience overlaps with.
#
# Returns the CHANNELS whose Voyage `summary_embedding` sits closest
# (cosine distance) to a given game's `summary_embedding`. Backs the
# "channels covering this game" right shelf on the game show page.
#
# Mirrors `Bundle::SuggestedFor` and `Game::SimilarGames` in query
# shape — the cosine ORDER BY rides on the `neighbor` gem's
# `nearest_neighbors` helper (declared via `has_neighbors
# :summary_embedding` on `Channel`), hitting the pgvector HNSW index
# (`vector_cosine_ops`).
#
# Departs from those two services in its return shape: instead of an
# ActiveRecord relation, this service returns an Array of `Result`
# structs carrying the channel, the raw cosine distance, and a
# 0–100 score linearly mapped from distance. Results below
# `THRESHOLD_SCORE` are dropped — the shelf renders nothing when the
# embedding space puts no channel within a meaningful neighborhood.
#
# Cosine distance ranges 0 (identical) → 2 (opposite); for normalized
# Voyage embeddings practical hits sit in [0, 1]. The score formula
# `((1 - distance) * 100).round.clamp(0, 100)` maps that to 100 → 0.
#
# Empty / unembedded input → `[]`. Channels without an embedding are
# skipped via the `where.not(summary_embedding: nil)` guard so the
# `neighbor` gem never sees a NULL vector.
class Game
  class ChannelRecommendation
    DEFAULT_LIMIT = 8
    THRESHOLD_SCORE = 25 # drop hits below this 0–100 score floor

    Result = Struct.new(:channel, :score, :distance, keyword_init: true)

    def self.call(game, limit: DEFAULT_LIMIT)
      new(game, limit: limit).call
    end

    def initialize(game, limit: DEFAULT_LIMIT)
      @game = game
      @limit = limit
    end

    def call
      return [] if @game.nil?
      return [] if @game.summary_embedding.blank?

      candidates = Channel
        .where.not(summary_embedding: nil)
        .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
        .first(@limit)

      candidates
        .map { |channel| build_result(channel) }
        .select { |result| result.score >= THRESHOLD_SCORE }
    end

    private

    def build_result(channel)
      distance = channel.neighbor_distance
      score = ((1 - distance) * 100).round.clamp(0, 100)
      Result.new(channel: channel, score: score, distance: distance)
    end
  end
end
