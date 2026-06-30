# frozen_string_literal: true

module Pito
  module Channel
    # The ONE channel item, rendered identically everywhere (centered column,
    # 120px circular avatar, handle / title). The @handle is always a clickable
    # prefill token that auto-runs `show channel @handle` via the chat controller.
    #
    # kwargs:
    #   channel:          [Channel]      — the channel record to display.
    #   show_avatar:      [Boolean]      — render the cached avatar variant (default false).
    #   score:            [Integer, nil] — when present, render a ScoreBarComponent.
    #                                      nil omits the bar.
    #   show_title:       [Boolean]      — render the channel name/title line
    #                                      (default true). `show game` channel matches
    #                                      pass false → @handle only (avatar + score kept).
    #   show_stats:       [Boolean]      — render a one-line "subs · views" stats row
    #                                      (default false). Used on `list channels` only.
    #   show_video_count: [Boolean]      — include the video count in the stats row
    #                                      (default false). Opt-in for `list channels`.
    #
    # Usage:
    #   # list channels — avatar + prefill handle + title + one-line stats, no score bar:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, show_stats: true, show_video_count: true))
    #
    #   # recommended channels — avatar + score bar, no stats:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, score: result.score))
    #
    #   # show game channel matches — avatar + handle + score, NO title:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, score:, show_title: false))
    class ItemComponent < ViewComponent::Base
      def initialize(channel:, score: nil, show_avatar: false, show_title: true, show_stats: false, show_video_count: false)
        @channel          = channel
        @score            = score
        @show_avatar      = show_avatar
        @show_title       = show_title
        @show_stats       = show_stats
        @show_video_count = show_video_count
      end

      attr_reader :channel

      def show_avatar?
        @show_avatar
      end

      def show_title?
        @show_title
      end

      def show_stats?
        @show_stats
      end

      def show_video_count?
        @show_video_count
      end

      # Our locally-cached avatar variant (never the YouTube CDN). nil → placeholder.
      def avatar_url
        channel.avatar_variant_url
      end

      def score?
        !@score.nil?
      end

      def score
        @score
      end

      # Row-1 counters: "N Subs · M Views" (always shown when show_stats: true).
      def stat_row1_metrics
        [
          { key: :subs,  value: channel.subscriber_count.to_i },
          { key: :views, value: channel.view_count.to_i }
        ]
      end

      # Row-2 counters: "P Vids" (second line, only when show_video_count: true).
      def stat_row2_metrics
        [ { key: :vids, value: channel.videos.count } ]
      end
    end
  end
end
