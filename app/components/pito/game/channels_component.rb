# frozen_string_literal: true

module Pito
  module Game
    # Renders the "channel matches" section of the recommendations message.
    #
    # Shows a CSS grid of matched channels (handle / title / ScoreBar).
    # Uses the channels_match_header copy key as the intro/lead line.
    #
    # NAMESPACE GOTCHA: inside Pito::Game::*, the bareword `Game` resolves to
    # the Pito::Game MODULE. Use the fully-qualified ::Game constant for the model.
    class ChannelsComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def intro
        Pito::Copy.render_html("pito.copy.games.channels_match_header")
      end

      def channel_results
        # Every channel the user has, ranked best-first. Channels with no
        # relevant videos/links score 0 and sort last, so the user always
        # sees the full slate to pick from.
        @channel_results ||= Pito::Recommendations.channels_for(@game, include_all: true)
      end

      def channels?
        channel_results.any?
      end
    end
  end
end
