# frozen_string_literal: true

module Pito
  module Recommendation
    # How well a game fits a channel's PERSONALITY profile (ChannelProfile) — the
    # core of both channel directions. Per facet, the game's "coverage" of the
    # channel's normalized facet mass (the sum of the channel's weights for the
    # game's values, 0–100), blended with the score/TTB smiles, era proximity,
    # and embedding-to-centroid similarity — over ONLY the signals present
    # (Weights.blend). The channel's identity is the reference; a game that hits
    # the channel's HIGH-weight facets scores high, and that weight grows as more
    # of the channel's videos confirm the throughline (reinforce).
    module ProfileFit
      module_function

      def call(game, profile)
        return 0 if game.nil? || profile.nil? || profile.empty?

        Weights.blend(breakdown(game, profile))
      end

      def breakdown(game, profile)
        bd = {}
        bd[:g]  = coverage(profile.genres,       ids(game, :genres))                if profile.genres.any?
        bd[:t]  = coverage(profile.themes,       Array(game.themes))               if profile.themes.any?
        bd[:pp] = coverage(profile.perspectives, Array(game.player_perspectives))  if profile.perspectives.any?
        bd[:d]  = coverage(profile.developers,   ids(game, :developer_companies))  if profile.developers.any?
        bd[:p]  = coverage(profile.publishers,   ids(game, :publisher_companies))  if profile.publishers.any?
        bd[:platform] = coverage(profile.platforms, Array(game.platforms))         if profile.platforms.any?
        bd[:s]   = Signals.score_smile(game.score, profile.score)                  if game.score && profile.score
        bd[:ttb] = Signals.ttb_smile(game.ttb_main_seconds, profile.ttb_seconds)   if game.ttb_main_seconds && profile.ttb_seconds
        bd[:era] = Signals.era(game.release_year, profile.year)                    if game.release_year && profile.year
        bd[:e]   = Signals.embedding(GameSimilarity.cosine_distance(game.summary_embedding, profile.embedding)) if game.summary_embedding && profile.embedding
        bd
      end

      # Fraction (×100) of the channel's normalized facet mass the game covers.
      def coverage(profile_weights, game_values)
        Array(game_values).sum { |v| profile_weights[v].to_f } * 100.0
      end

      def ids(game, association)
        game.public_send(association).map(&:id)
      end
    end
  end
end
