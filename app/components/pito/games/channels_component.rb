# frozen_string_literal: true

module Pito
  module Games
    # The show-game CHANNEL-MATCHES message, reworked into TWO 450px
    # columns that align row-for-row on desktop (stack on mobile):
    #
    #   col 1 — per-game CHANNEL DISTRIBUTION (ChannelDistributionComponent):
    #           offset bars of each channel's weighted coverage share, or a NoData
    #           dotted canvas (rendered NoData on the instant `pending` message;
    #           filled to bars by ChannelDistributionFillJob).
    #   col 2 — channel RECOMMENDATION (ChannelScoreTableComponent): the same top-5
    #           channels by score as an avatar + score-bar kv-table. Rendered
    #           directly (cheap, no streaming).
    #
    # Same 5 channels, same order (by score) in both columns. The intro + captions
    # are chosen ONCE by the message builder and passed in, so they never change
    # under the user when the distribution fills (the ready re-render reuses them).
    class ChannelsComponent < ViewComponent::Base
      TOP_N = 5

      # @param game                   [::Game]
      # @param intro                  [String] pre-rendered intro (stable).
      # @param distribution_caption   [String] col-1 caption (stable).
      # @param recommendation_caption [String] col-2 caption.
      # @param shares                 [Array<Game::ChannelDistribution::Share>, nil]
      #   nil → col-1 renders NoData (pending); present → col-1 renders the bars (ready).
      def initialize(game:, intro:, distribution_caption:, recommendation_caption:, shares: nil)
        @game                   = game
        @intro                  = intro
        @distribution_caption   = distribution_caption
        @recommendation_caption = recommendation_caption
        @shares                 = shares
      end

      attr_reader :game, :intro, :distribution_caption, :recommendation_caption, :shares

      # Top-N channels by score (results already ranked best-first). Same set/order
      # the distribution charts (the fill job recomputes this identically).
      def channel_results
        @channel_results ||= Pito::Recommendations.channels_for(@game, include_all: true).first(TOP_N)
      end

      def channels?
        channel_results.any?
      end
    end
  end
end
