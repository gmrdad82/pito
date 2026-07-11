# frozen_string_literal: true

module Pito
  module Games
    # Column 1 of the show-game channel-matches message: the per-game
    # CHANNEL DISTRIBUTION — an offset bar-group (Analytics::Visualizers::Bar) of
    # each channel's weighted coverage share, OR a NoData dotted canvas while the
    # data is still pending / when no channel covers the game.
    #
    # Progressive (owner): the message renders this column as NoData instantly;
    # ChannelDistributionFillJob computes the shares and rewrites the message to
    # the bar version (persisted ready body + replace_event), exactly like the
    # analyze/glance finalize. The caption is chosen ONCE at pending time and
    # passed in (stored in the marker) so it never changes under the user.
    class ChannelDistributionComponent < ViewComponent::Base
      # Per-bar colour cycle (tokens defined by Analytics::Visualizers::Bar).
      COLORS = %i[blue green purple cyan yellow orange red pink].freeze

      # @param caption [String] pre-rendered/plain caption (stable across the swap).
      # @param shares  [Array<Game::ChannelDistribution::Share>, nil] nil → NoData.
      def initialize(caption:, shares: nil)
        @caption = caption
        @shares  = shares
      end

      attr_reader :caption

      def data?
        @shares.present?
      end

      def bars
        @shares.each_with_index.map do |s, i|
          { label: s.channel.handle, pct: s.share, color: COLORS[i % COLORS.size] }
        end
      end
    end
  end
end
