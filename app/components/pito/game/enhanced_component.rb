# frozen_string_literal: true

module Pito
  module Game
    # Renders the "enhanced" game message streamed after Voyage indexing.
    #
    # Sections (each omitted when data is absent):
    #   1. Intro line      — Pito::Copy.render("pito.copy.games.enhanced_intro")
    #   2. Channel matches — ALL matched channels from Pito::Recommendations.channels_for,
    #                        displayed as a CSS grid with handle / title / ScoreBar.
    #   3. Similar games   — up to 8 games from Pito::Recommendations.similar_games,
    #                        displayed as an inline strip of small cover cards.
    #
    # NAMESPACE GOTCHA: inside Pito::Game::*, the bareword `Game` resolves to
    # the Pito::Game MODULE. Use the fully-qualified ::Game constant for the model.
    class EnhancedComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def intro
        Pito::Copy.render("pito.copy.games.enhanced_intro")
      end

      def channels_header
        Pito::Copy.render("pito.copy.games.channels_match_header")
      end

      def similar_games_header
        Pito::Copy.render("pito.copy.games.similar_games_header")
      end

      def channel_results
        # Every channel the user has, ranked best-first — each gets its own
        # ScoreBarComponent. Channels with no relevant videos/links score 0 and
        # sort last, so the user always sees the full slate to pick from.
        @channel_results ||= Pito::Recommendations.channels_for(@game, include_all: true)
      end

      def similar_game_results
        @similar_game_results ||= Pito::Recommendations.similar_games(@game, limit: 6)
      end

      def channels?
        channel_results.any?
      end

      def similar_games?
        similar_game_results.any?
      end

      # Host-less ActiveStorage proxy path for a similar-game cover variant, or
      # nil when no attachment (the view falls back to the placeholder).
      def cover_art_url_for(game)
        Pito::ImagePath.call(game.cover_art, variant: ::Game::COVER_VARIANT)
      end
    end
  end
end
