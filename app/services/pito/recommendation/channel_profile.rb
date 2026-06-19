# frozen_string_literal: true

module Pito
  module Recommendation
    # Aggregate personality profile of a channel — distilled from the games its
    # PUBLISHED videos link to, weighted by video count (effort). The channel
    # directions score a game against THIS profile rather than against individual
    # linked games, so the channel's identity sharpens (reinforces) as more
    # videos confirm a throughline: a genre/theme/perspective that many of the
    # channel's videos share carries more weight, and a new game matching that
    # high-weight part of the profile scores higher.
    #
    # All facet weights are normalized to sum to 1.0 so a per-facet "fit" is just
    # the share of the channel's mass the candidate game covers. The
    # scalar centroids (score / TTB / year) and the embedding centroid are
    # video-count-weighted means over the linked games that carry the value.
    class ChannelProfile
      Profile = Struct.new(
        :genres, :themes, :perspectives, :developers, :publishers, :platforms,
        :score, :ttb_seconds, :year, :embedding,
        :linked_game_ids, :total_videos,
        keyword_init: true
      ) do
        def empty? = linked_game_ids.empty?
      end

      def self.call(channel)
        new(channel).call
      end

      def initialize(channel)
        @channel = channel
      end

      def call
        rows = linked_games_with_counts
        return empty_profile if rows.empty?

        Profile.new(
          genres:       weighted_facet(rows) { |g| g.genres.map(&:id) },
          themes:       weighted_facet(rows) { |g| Array(g.themes) },
          perspectives: weighted_facet(rows) { |g| Array(g.player_perspectives) },
          developers:   weighted_facet(rows) { |g| g.developer_companies.map(&:id) },
          publishers:   weighted_facet(rows) { |g| g.publisher_companies.map(&:id) },
          platforms:    weighted_facet(rows) { |g| Array(g.platforms) },
          score:        weighted_mean(rows, &:score),
          ttb_seconds:  weighted_mean(rows, &:ttb_main_seconds),
          year:         weighted_mean(rows, &:release_year),
          embedding:    weighted_embedding(rows),
          linked_game_ids: rows.map { |g, _| g.id },
          total_videos:    rows.sum { |_, c| c }
        )
      end

      private

      # [[Game, published_video_count], …] — games the channel's PUBLISHED videos
      # link to, each with how many of those videos point at it (the effort).
      def linked_games_with_counts
        counts = ::Video
                 .where(channel_id: @channel.id, privacy_status: ::Video.privacy_statuses[:public])
                 .joins(:video_game_links)
                 .group("video_game_links.game_id")
                 .count

        return [] if counts.empty?

        games = ::Game.where(id: counts.keys)
                      .includes(:genres, :developer_companies, :publisher_companies)
                      .index_by(&:id)
        counts.filter_map { |game_id, c| [ games[game_id], c ] if games[game_id] }
      end

      # Facet → normalized weight (Σ = 1), each occurrence weighted by the game's
      # video count. The yielded block returns the game's facet values.
      def weighted_facet(rows)
        tally = Hash.new(0.0)
        rows.each { |game, count| yield(game).each { |v| tally[v] += count } }
        total = tally.values.sum
        return {} if total.zero?

        tally.transform_values { |w| w / total }
      end

      # Video-count-weighted mean of a scalar (score / ttb / year), skipping nils.
      def weighted_mean(rows)
        num = den = 0.0
        rows.each do |game, count|
          v = yield(game)
          next if v.nil?

          num += v.to_f * count
          den += count
        end
        den.zero? ? nil : num / den
      end

      # Video-count-weighted mean embedding vector (nil when none embedded).
      def weighted_embedding(rows)
        vectors = rows.filter_map do |game, count|
          vec = GameSimilarity.coerce_vector(game.summary_embedding)
          [ vec, count ] if vec
        end
        return nil if vectors.empty?

        dim = vectors.first[0].size
        sum = Array.new(dim, 0.0)
        total = 0.0
        vectors.each do |vec, count|
          next if vec.size != dim

          vec.each_index { |i| sum[i] += vec[i] * count }
          total += count
        end
        total.zero? ? nil : sum.map { |x| x / total }
      end

      def empty_profile
        Profile.new(
          genres: {}, themes: {}, perspectives: {}, developers: {}, publishers: {}, platforms: {},
          score: nil, ttb_seconds: nil, year: nil, embedding: nil,
          linked_game_ids: [], total_videos: 0
        )
      end
    end
  end
end
