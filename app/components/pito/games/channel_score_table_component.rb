# frozen_string_literal: true

module Pito
  module Games
    # Column 2 of the show-game channel-matches message: the channel
    # RECOMMENDATION as a kv-table — each row is a small (40×40 :xs variant)
    # channel avatar in the key column and the channel's fit ScoreBar in the value
    # column. Top-5 by score (caller passes ranked results); renders directly (not
    # progressive — it's cheap).
    class ChannelScoreTableComponent < ViewComponent::Base
      MAX_ROWS = 5

      # @param results [Array<#channel, #score>] ranked channel recommendation results.
      # @param caption [String] pre-rendered/plain caption.
      def initialize(results:, caption:)
        @results = Array(results).first(MAX_ROWS)
        @caption = caption
      end

      attr_reader :results, :caption

      # 40×40 :xs avatar variant URL (distinct variant — no browser downscale), or
      # nil → placeholder.
      def avatar_url(channel)
        channel.avatar_xs_url
      end
    end
  end
end
