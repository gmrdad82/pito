# frozen_string_literal: true

module Pito
  module Games
    # Renders the "similar games" section of the recommendations message.
    #
    # Shows an inline strip of similar-game cover cards.
    # Uses the similar_games_header copy key as the intro/lead line.
    class SimilarGamesComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def intro
        Pito::Copy.render_html("pito.copy.games.similar_games_header")
      end

      # Top 4 (owner 2026-07-16) — 4 covers at the 20%-bumped 216px width fit the
      # 964px conversation column on one row (4×216 + 3×4px gap = 876), and wrap
      # to a clean 2,2 on mobile (no 2,2,1 orphan). See the strip CSS.
      def similar_game_results
        @similar_game_results ||= Pito::Recommendations.similar_games(@game, limit: 4)
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
