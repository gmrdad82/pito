# frozen_string_literal: true

# Games best suited to a channel — the **channel→game** direction ("what should
# this channel cover next?"). (v2) Symmetric to Game::ChannelRecommendation:
# build the channel's aggregate `Pito::Recommendation::ChannelProfile`, then
# score candidate games by their fit to it plus the small graded-K link bonus:
#
#   game_score = clamp(ProfileFit(game, profile) + gradedK(depth, other), 0, 100)
#
# Candidate games = the channel's already-linked games, UNION games sharing a
# genre/developer/publisher with the profile, UNION games nearest the profile's
# embedding centroid. nil channel / empty profile → `[]`.
class Channel
  class GameRecommendation
    FLOOR          = Pito::Recommendation::Weights::FLOOR
    CANDIDATE_POOL = 50 # games nearest the profile centroid pulled before the facet union

    Result = Struct.new(:game, :score, :breakdown, keyword_init: true)

    def self.call(channel, limit: nil)
      new(channel, limit: limit).call
    end

    def initialize(channel, limit: nil)
      @channel = channel
      @limit   = limit
    end

    def call
      return [] if @channel.nil?

      profile = Pito::Recommendation::ChannelProfile.call(@channel)
      return [] if profile.empty?

      counts     = link_counts
      total      = counts.values.sum
      candidates = candidate_games(profile)
      return [] if candidates.empty?

      ranked = candidates.filter_map { |game|
        fit   = Pito::Recommendation::ProfileFit.call(game, profile)
        depth = counts[game.id] || 0
        link  = Pito::Recommendation::Weights.graded_link(depth, total - depth).round
        score = [ fit + link, 100 ].min
        next if score < FLOOR

        Result.new(game: game, score: score, breakdown: { fit: fit, link: link })
      }.sort_by { |result| [ -result.score, result.game.id ] }

      @limit ? ranked.first(@limit) : ranked
    end

    private

    # { game_id => published_video_count } for this channel.
    def link_counts
      ::Video.where(channel_id: @channel.id, privacy_status: ::Video.privacy_statuses[:public])
             .joins(:video_game_links)
             .group("video_game_links.game_id")
             .count
    end

    def candidate_games(profile)
      ids = (profile.linked_game_ids + facet_candidate_ids(profile) + embedding_candidate_ids(profile)).uniq
      return [] if ids.empty?

      ::Game.where(id: ids).includes(:genres, :developer_companies, :publisher_companies).to_a
    end

    # Games sharing >= 1 genre / developer / publisher with the channel's profile.
    def facet_candidate_ids(profile)
      ids = []
      ids += join_pool(:game_genres, :genre_id, profile.genres.keys)
      ids += join_pool(:game_developers, :company_id, profile.developers.keys)
      ids += join_pool(:game_publishers, :company_id, profile.publishers.keys)
      ids.uniq
    end

    def join_pool(join, column, values)
      return [] if values.blank?

      ::Game.joins(join).where(join => { column => values }).distinct.pluck(:id)
    end

    # Games nearest the channel's embedding centroid (cold-start reach).
    def embedding_candidate_ids(profile)
      return [] if profile.embedding.blank?

      ::Game.where.not(::Game::EMBEDDING_COLUMN => nil)
            .nearest_neighbors(::Game::EMBEDDING_COLUMN, profile.embedding, distance: "cosine")
            .limit(CANDIDATE_POOL)
            .pluck(:id)
    end
  end
end
