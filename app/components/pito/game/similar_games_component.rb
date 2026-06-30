# frozen_string_literal: true

module Pito
  module Game
    # Renders the "similar games" section of the recommendations message.
    #
    # Shows an inline strip of similar-game cover cards.
    # Uses the similar_games_header copy key as the intro/lead line.
    #
    # NAMESPACE GOTCHA: inside Pito::Game::*, the bareword `Game` resolves to
    # the Pito::Game MODULE. Use the fully-qualified ::Game constant for the model.
    class SimilarGamesComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def intro
        Pito::Copy.render_html("pito.copy.games.similar_games_header")
      end

      # Top 5 so the cover strip fits the 964px conversation column on one row
      # (5×180 + 4×4px gap = 916; see the strip CSS) — 13.40.
      def similar_game_results
        @similar_game_results ||= Pito::Recommendations.similar_games(@game, limit: 5)
      end

      def similar_games?
        similar_game_results.any?
      end

      # Host-less ActiveStorage proxy path for a similar-game cover variant, or
      # nil when no attachment (the view falls back to the placeholder).
      def cover_art_url_for(game)
        Pito::ImagePath.call(game.cover_art, variant: :strip)
      end
    end
  end
end
